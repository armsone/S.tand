import Combine
import CoreBluetooth
import Foundation
import Network
import UIKit

enum BoyisoTransportKind: String, Hashable {
    case localNetwork
    case bluetooth

    var title: String {
        switch self {
        case .localNetwork: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        }
    }
}

struct BoyisoPeerStatus: Identifiable, Equatable {
    let id: UUID
    var name: String
    var lastSeen: Date
    var monitoring: Bool
    var batteryPercent: Int?
    var transports: Set<BoyisoTransportKind>

    func isFresh(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(lastSeen) < BoyisoConnectivityService.staleInterval
    }
}

final class BoyisoConnectivityService: NSObject, ObservableObject {
    static let staleInterval: TimeInterval = 15

    @Published private(set) var isEnabled = false
    @Published private(set) var role: BoyisoRole = .host
    @Published private(set) var roomCode = ""
    @Published private(set) var peers: [BoyisoPeerStatus] = []
    @Published private(set) var lastRemoteEvent: BoyisoEvent?
    @Published private(set) var localNetworkReady = false
    @Published private(set) var bluetoothReady = false
    @Published private(set) var guardianConnectionCount = 0
    @Published private(set) var issueMessage: String?

    var onRemoteAlert: ((BoyisoEvent) -> Void)?

    var activePeers: [BoyisoPeerStatus] {
        peers.filter { $0.isFresh() }.sorted { $0.name < $1.name }
    }

    var statusText: String {
        guard isEnabled else { return "사용 안 함" }
        let count = activePeers.count
        if role == .guest {
            return guardianConnectionCount == 0
                ? "보호자 기기를 기다리는 중"
                : "보호자 연결 \(guardianConnectionCount)개 유지 중"
        }
        return count == 0 ? "아이 곁 기기를 찾는 중" : "아이 곁 기기 \(count)대 감시 중"
    }

    private static let serviceType = "_boyiso._tcp"
    private static let bluetoothServiceUUID = CBUUID(
        string: "B0150001-7A4D-4F6B-9D7A-5354414E4401"
    )
    private static let bluetoothEventUUID = CBUUID(
        string: "B0150002-7A4D-4F6B-9D7A-5354414E4401"
    )
    private static let enabledKey = "boyiso.isEnabled"
    private static let roleKey = "boyiso.role"
    private static let roomCodeKey = "boyiso.roomCode"
    private static let deviceIDKey = "boyiso.deviceID"

    private let queue = DispatchQueue(label: "com.armsone.stand.boyiso.network")
    private let defaults: UserDefaults
    private let deviceID: UUID
    private var deviceName: String { UIDevice.current.name }
    private var localMonitoring = false
    private var localBatteryPercent: Int?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var lanConnections: [String: NWConnection] = [:]
    private var receiveBuffers: [String: Data] = [:]
    private var readyGuestLANConnections: Set<String> = []
    private lazy var centralManager = CBCentralManager(delegate: self, queue: queue)
    private lazy var peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
    private var eventCharacteristic: CBMutableCharacteristic?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var subscribedCharacteristics: [UUID: CBCharacteristic] = [:]
    private var pendingBluetoothFragments: [Data] = []
    private var subscribedBluetoothCentrals: Set<UUID> = []
    private var maximumBluetoothPayloadLength = 160
    private var reassembler = BoyisoBluetoothReassembler()
    private var deduplicator = BoyisoEventDeduplicator()
    private var heartbeatTimer: Timer?
    private var alertClearTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.deviceIDKey),
           let id = UUID(uuidString: stored) {
            deviceID = id
        } else {
            let id = UUID()
            deviceID = id
            defaults.set(id.uuidString, forKey: Self.deviceIDKey)
        }
        super.init()
        role = BoyisoRole(rawValue: defaults.string(forKey: Self.roleKey) ?? "") ?? .host
        roomCode = BoyisoCodec.normalizedRoomCode(
            defaults.string(forKey: Self.roomCodeKey) ?? ""
        )
        if defaults.bool(forKey: Self.enabledKey), BoyisoCodec.isValidRoomCode(roomCode) {
            start()
        }
    }

    deinit {
        heartbeatTimer?.invalidate()
        alertClearTask?.cancel()
    }

    func configure(role: BoyisoRole, roomCode: String) throws {
        let normalized = BoyisoCodec.normalizedRoomCode(roomCode)
        guard BoyisoCodec.isValidRoomCode(normalized) else {
            throw BoyisoCodecError.invalidRoomCode
        }
        stop(clearConfiguration: false)
        self.role = role
        self.roomCode = normalized
        defaults.set(role.rawValue, forKey: Self.roleKey)
        defaults.set(normalized, forKey: Self.roomCodeKey)
        defaults.set(true, forKey: Self.enabledKey)
        start()
    }

    func disable() {
        stop(clearConfiguration: false)
        defaults.set(false, forKey: Self.enabledKey)
    }

    func updateLocalState(monitoring: Bool, batteryPercent: Int?) {
        localMonitoring = monitoring
        localBatteryPercent = batteryPercent.map { min(100, max(0, $0)) }
        guard isEnabled, role == .guest else { return }
        emit(kind: .heartbeat)
    }

    func sendSoundEvent(intensity: Double, detail: String? = nil) {
        guard isEnabled, role == .guest, localMonitoring else { return }
        emit(kind: .sound, intensity: intensity, detail: detail)
    }

    func sendMovementEvent(intensity: Double = 1) {
        guard isEnabled, role == .guest, localMonitoring else { return }
        emit(kind: .movement, intensity: intensity)
    }

    private func start() {
        guard BoyisoCodec.isValidRoomCode(roomCode) else { return }
        isEnabled = true
        issueMessage = nil
        peers = []
        startHeartbeatTimer()
        if role == .guest {
            startLocalNetworkListener()
            queue.async { [weak self] in self?.prepareBluetoothPeripheralIfPossible() }
        } else {
            startLocalNetworkBrowser()
            queue.async { [weak self] in self?.startBluetoothScanIfPossible() }
        }
    }

    private func stop(clearConfiguration: Bool) {
        isEnabled = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        alertClearTask?.cancel()
        alertClearTask = nil
        lastRemoteEvent = nil
        peers = []
        issueMessage = nil
        localNetworkReady = false
        bluetoothReady = false
        guardianConnectionCount = 0
        queue.async { [weak self] in
            guard let self else { return }
            listener?.cancel()
            listener = nil
            browser?.cancel()
            browser = nil
            lanConnections.values.forEach { $0.cancel() }
            lanConnections.removeAll()
            receiveBuffers.removeAll()
            readyGuestLANConnections.removeAll()
            centralManager.stopScan()
            discoveredPeripherals.values.forEach {
                self.centralManager.cancelPeripheralConnection($0)
            }
            discoveredPeripherals.removeAll()
            subscribedCharacteristics.removeAll()
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
            eventCharacteristic = nil
            pendingBluetoothFragments.removeAll()
            subscribedBluetoothCentrals.removeAll()
        }
        if clearConfiguration {
            roomCode = ""
            defaults.removeObject(forKey: Self.roomCodeKey)
        }
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            if self.role == .guest { self.emit(kind: .heartbeat) }
            self.pruneStalePeers()
        }
        if role == .guest { emit(kind: .heartbeat) }
    }

    private func emit(
        kind: BoyisoEventKind,
        intensity: Double? = nil,
        detail: String? = nil
    ) {
        let event = BoyisoEvent(
            sourceID: deviceID,
            sourceName: deviceName,
            kind: kind,
            intensity: intensity,
            detail: detail,
            monitoring: localMonitoring,
            batteryPercent: localBatteryPercent
        )
        queue.async { [weak self] in
            self?.sendOverLocalNetwork(event)
            self?.sendOverBluetooth(event)
        }
    }

    private func startLocalNetworkListener() {
        queue.async { [weak self] in
            guard let self, self.isEnabled, self.role == .guest else { return }
            do {
                let listener = try NWListener(using: .tcp)
                listener.service = NWListener.Service(
                    name: "보이소-\(self.deviceID.uuidString.prefix(6))",
                    type: Self.serviceType
                )
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.register(connection: connection)
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.publishIssue("로컬 네트워크 수신을 시작하지 못했습니다.")
            }
        }
    }

    private func startLocalNetworkBrowser() {
        queue.async { [weak self] in
            guard let self, self.isEnabled, self.role == .host else { return }
            let browser = NWBrowser(
                for: .bonjour(type: Self.serviceType, domain: nil),
                using: .tcp
            )
            browser.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.publish { $0.localNetworkReady = true }
                case .failed:
                    self?.publishIssue("로컬 네트워크에서 기기를 찾지 못했습니다.")
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.connectToBrowseResults(results)
            }
            self.browser = browser
            browser.start(queue: self.queue)
        }
    }

    private func connectToBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard isEnabled, role == .host else { return }
        let endpoints = Set(results.map { $0.endpoint.debugDescription })
        for result in results {
            let key = result.endpoint.debugDescription
            guard lanConnections[key] == nil else { continue }
            register(connection: NWConnection(to: result.endpoint, using: .tcp), key: key)
        }
        for key in lanConnections.keys where !endpoints.contains(key) {
            lanConnections[key]?.cancel()
            lanConnections.removeValue(forKey: key)
            receiveBuffers.removeValue(forKey: key)
        }
    }

    private func register(connection: NWConnection, key: String? = nil) {
        let connectionKey = key ?? UUID().uuidString
        lanConnections[connectionKey] = connection
        receiveBuffers[connectionKey] = Data()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.publish { $0.localNetworkReady = true }
                if self.role == .guest {
                    self.readyGuestLANConnections.insert(connectionKey)
                    self.publishGuardianConnectionCount()
                }
                self.receive(on: connection, key: connectionKey)
                if self.role == .guest { self.emit(kind: .heartbeat) }
            case .failed, .cancelled:
                self.lanConnections.removeValue(forKey: connectionKey)
                self.receiveBuffers.removeValue(forKey: connectionKey)
                self.readyGuestLANConnections.remove(connectionKey)
                self.publishGuardianConnectionCount()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, key: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty {
                var buffer = self.receiveBuffers[key, default: Data()]
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let frame = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    if let event = try? BoyisoCodec.openLANFrame(frame, roomCode: self.roomCode) {
                        self.receive(event, through: .localNetwork)
                    }
                }
                self.receiveBuffers[key] = buffer
            }
            if isComplete || error != nil {
                connection.cancel()
                self.lanConnections.removeValue(forKey: key)
                self.receiveBuffers.removeValue(forKey: key)
                self.readyGuestLANConnections.remove(key)
                self.publishGuardianConnectionCount()
            } else {
                self.receive(on: connection, key: key)
            }
        }
    }

    private func sendOverLocalNetwork(_ event: BoyisoEvent) {
        guard let frame = try? BoyisoCodec.lanFrame(for: event, roomCode: roomCode) else { return }
        for connection in lanConnections.values {
            connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    private func prepareBluetoothPeripheralIfPossible() {
        guard isEnabled, role == .guest, peripheralManager.state == .poweredOn else { return }
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        let characteristic = CBMutableCharacteristic(
            type: Self.bluetoothEventUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        let service = CBMutableService(type: Self.bluetoothServiceUUID, primary: true)
        service.characteristics = [characteristic]
        eventCharacteristic = characteristic
        peripheralManager.add(service)
    }

    private func startBluetoothScanIfPossible() {
        guard isEnabled, role == .host, centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(
            withServices: [Self.bluetoothServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        publish { $0.bluetoothReady = true }
    }

    private func sendOverBluetooth(_ event: BoyisoEvent) {
        guard role == .guest, let eventCharacteristic else { return }
        guard let fragments = try? BoyisoCodec.bluetoothFragments(
            for: event,
            roomCode: roomCode,
            maximumPayloadLength: maximumBluetoothPayloadLength
        ) else { return }
        pendingBluetoothFragments.append(contentsOf: fragments)
        flushBluetoothFragments(characteristic: eventCharacteristic)
    }

    private func flushBluetoothFragments(characteristic: CBMutableCharacteristic) {
        while let fragment = pendingBluetoothFragments.first {
            guard peripheralManager.updateValue(fragment, for: characteristic, onSubscribedCentrals: nil) else {
                return
            }
            pendingBluetoothFragments.removeFirst()
        }
    }

    private func receive(_ event: BoyisoEvent, through transport: BoyisoTransportKind) {
        guard role == .host else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePeer(with: event, transport: transport)
            guard self.deduplicator.accepts(event) else { return }
            guard event.kind != .heartbeat else { return }
            self.lastRemoteEvent = event
            self.onRemoteAlert?(event)
            self.alertClearTask?.cancel()
            self.alertClearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.lastRemoteEvent = nil
            }
        }
    }

    private func updatePeer(with event: BoyisoEvent, transport: BoyisoTransportKind) {
        let now = Date()
        if let index = peers.firstIndex(where: { $0.id == event.sourceID }) {
            peers[index].name = event.sourceName
            peers[index].lastSeen = now
            peers[index].monitoring = event.monitoring
            peers[index].batteryPercent = event.batteryPercent
            peers[index].transports.insert(transport)
        } else {
            peers.append(BoyisoPeerStatus(
                id: event.sourceID,
                name: event.sourceName,
                lastSeen: now,
                monitoring: event.monitoring,
                batteryPercent: event.batteryPercent,
                transports: [transport]
            ))
        }
    }

    private func pruneStalePeers() {
        let cutoff = Date().addingTimeInterval(-120)
        peers.removeAll { $0.lastSeen < cutoff }
        objectWillChange.send()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            publish { $0.localNetworkReady = true }
        case .failed:
            publishIssue("로컬 네트워크 수신을 시작하지 못했습니다.")
        default:
            break
        }
    }

    private func publish(_ mutation: @escaping (BoyisoConnectivityService) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            mutation(self)
        }
    }

    private func publishIssue(_ message: String) {
        publish { $0.issueMessage = message }
    }

    private func publishGuardianConnectionCount() {
        let count = readyGuestLANConnections.count + subscribedBluetoothCentrals.count
        publish { $0.guardianConnectionCount = count }
    }
}

extension BoyisoConnectivityService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startBluetoothScanIfPossible()
        } else if isEnabled, role == .host {
            publish { service in
                service.bluetoothReady = false
                if central.state == .unauthorized {
                    service.issueMessage = "Bluetooth 권한이 없어 Wi-Fi 연결만 사용합니다."
                }
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isEnabled, role == .host else { return }
        discoveredPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.bluetoothServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        subscribedCharacteristics.removeValue(forKey: peripheral.identifier)
        guard isEnabled, role == .host else { return }
        central.connect(peripheral)
    }
}

extension BoyisoConnectivityService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics([Self.bluetoothEventUUID], for: $0)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? []
        where characteristic.uuid == Self.bluetoothEventUUID {
            subscribedCharacteristics[peripheral.identifier] = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        guard let combined = reassembler.append(
            value,
            peerID: peripheral.identifier.uuidString
        ) else { return }
        guard let event = try? BoyisoCodec.open(combined, roomCode: roomCode) else { return }
        receive(event, through: .bluetooth)
    }
}

extension BoyisoConnectivityService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            prepareBluetoothPeripheralIfPossible()
        } else if isEnabled, role == .guest {
            publish { service in
                service.bluetoothReady = false
                if peripheral.state == .unauthorized {
                    service.issueMessage = "Bluetooth 권한이 없어 Wi-Fi 연결만 사용합니다."
                }
            }
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        guard error == nil, isEnabled, role == .guest else {
            if error != nil { publishIssue("Bluetooth 보조 연결을 시작하지 못했습니다.") }
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.bluetoothServiceUUID],
            CBAdvertisementDataLocalNameKey: "보이소"
        ])
        publish { $0.bluetoothReady = true }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscribedBluetoothCentrals.insert(central.identifier)
        maximumBluetoothPayloadLength = min(
            maximumBluetoothPayloadLength,
            central.maximumUpdateValueLength
        )
        publish { $0.bluetoothReady = true }
        publishGuardianConnectionCount()
        emit(kind: .heartbeat)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscribedBluetoothCentrals.remove(central.identifier)
        publishGuardianConnectionCount()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let eventCharacteristic else { return }
        flushBluetoothFragments(characteristic: eventCharacteristic)
    }
}
