import Combine
import CoreBluetooth
import Foundation
import Network
import UIKit
import UserNotifications

enum BoyisoTransportKind: String, CaseIterable, Hashable {
    case localNetwork, bluetooth, internet
    var title: String {
        switch self {
        case .localNetwork: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .internet: "인터넷"
        }
    }
}

struct BoyisoPeerStatus: Identifiable, Equatable {
    let id: UUID
    var name: String
    var role: BoyisoRole
    var lastSeen: Date
    var monitoring: Bool
    var batteryPercent: Int?
    var displayMode: BoyisoDisplayMode?
    var sessionActive: Bool
    var transports: Set<BoyisoTransportKind>

    func isFresh(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(lastSeen) < BoyisoConnectivityService.staleInterval
    }
}

final class BoyisoConnectivityService: NSObject, ObservableObject {
    static let staleInterval: TimeInterval = 15

    @Published private(set) var isEnabled = false
    @Published private(set) var role: BoyisoRole = .host
    @Published private(set) var deviceName = UIDevice.current.name
    @Published private(set) var invitation: BoyisoInvitation?
    @Published private(set) var canInvite = false
    @Published private(set) var peers: [BoyisoPeerStatus] = []
    @Published private(set) var lastRemoteEvent: BoyisoEvent?
    @Published private(set) var localNetworkConnectionCount = 0
    @Published private(set) var bluetoothConnectionCount = 0
    @Published private(set) var issueMessage: String?
    @Published private(set) var hadConnectedPeer = false

    var onRemoteEvent: ((BoyisoEvent) -> Void)?
    var activePeers: [BoyisoPeerStatus] {
        peers.filter { $0.isFresh() }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var currentParticipant: BoyisoPeerStatus {
        BoyisoPeerStatus(
            id: deviceID,
            name: deviceName,
            role: role,
            lastSeen: Date(),
            monitoring: localMonitoring,
            batteryPercent: localBatteryPercent,
            displayMode: localDisplayMode,
            sessionActive: localSessionActive,
            transports: []
        )
    }
    var statusText: String { isEnabled ? "공간에 연결됨" : "설정 필요" }
    var homeRoleText: String { isEnabled ? role.title : "연결 안 됨" }

    private static let serviceType = "_boyiso._tcp"
    private static let bluetoothServiceUUID = CBUUID(string: "B0150001-7A4D-4F6B-9D7A-5354414E4401")
    private static let bluetoothEventUUID = CBUUID(string: "B0150002-7A4D-4F6B-9D7A-5354414E4401")
    private static let roleKey = "boyiso.v2.role"
    private static let nameKey = "boyiso.v2.name"
    private static let roomIDKey = "boyiso.v2.roomID"
    private static let roomKeyKey = "boyiso.v2.roomKey"
    private static let canInviteKey = "boyiso.v2.canInvite"
    private static let enabledKey = "boyiso.v2.enabled"
    private static let deviceIDKey = "boyiso.deviceID"

    private let queue = DispatchQueue(label: "com.armsone.stand.boyiso.network")
    private let defaults: UserDefaults
    private let deviceID: UUID
    private var localMonitoring = false
    private var localBatteryPercent: Int?
    private var localDisplayMode: BoyisoDisplayMode = .object
    private var localSessionActive = false
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var lanConnections: [String: NWConnection] = [:]
    private var receiveBuffers: [String: Data] = [:]
    private var knownEndpoints: [String: NWEndpoint] = [:]
    private lazy var centralManager = CBCentralManager(delegate: self, queue: queue)
    private lazy var peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
    private var bluetoothStarted = false
    private var eventCharacteristic: CBMutableCharacteristic?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var subscribedCharacteristics: [UUID: CBCharacteristic] = [:]
    private var subscribedCentrals: Set<UUID> = []
    private var pendingFragments: [Data] = []
    private var maximumBluetoothPayloadLength = 160
    private var reassembler = BoyisoBluetoothReassembler()
    private var deduplicator = BoyisoEventDeduplicator()
    private var heartbeatTimer: Timer?
    private var lastTokTokSentAt = Date.distantPast

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.deviceIDKey), let id = UUID(uuidString: stored) {
            deviceID = id
        } else {
            let id = UUID(); deviceID = id; defaults.set(id.uuidString, forKey: Self.deviceIDKey)
        }
        super.init()
        role = BoyisoRole(rawValue: defaults.string(forKey: Self.roleKey) ?? "") ?? .host
        deviceName = defaults.string(forKey: Self.nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(32).description.nonEmpty ?? UIDevice.current.name
        if let room = defaults.string(forKey: Self.roomIDKey), let key = defaults.string(forKey: Self.roomKeyKey) {
            invitation = try? BoyisoInvitation(roomID: room, roomKey: key)
        }
        canInvite = defaults.bool(forKey: Self.canInviteKey)
        if defaults.bool(forKey: Self.enabledKey), invitation != nil { start() }
    }

    deinit { heartbeatTimer?.invalidate() }

    func updateIdentity(role: BoyisoRole, name: String) {
        guard !isEnabled else { return }
        self.role = role
        deviceName = name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32).description
        defaults.set(role.rawValue, forKey: Self.roleKey)
        defaults.set(deviceName, forKey: Self.nameKey)
    }

    @discardableResult
    func updateDisplayName(_ name: String) -> Bool {
        let updated = name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32).description
        guard !updated.isEmpty else { return false }
        deviceName = updated
        defaults.set(updated, forKey: Self.nameKey)
        if isEnabled { emit(kind: .heartbeat) }
        return true
    }

    func createRoom(role: BoyisoRole, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BoyisoCodecError.invalidInvitation
        }
        stop(clearRoom: true)
        updateIdentity(role: role, name: name)
        invitation = .make()
        canInvite = true
        persistRoom(enabled: true)
        start()
    }

    func joinRoom(_ url: URL, role: BoyisoRole, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BoyisoCodecError.invalidInvitation
        }
        let parsed = try BoyisoInvitation(url: url)
        stop(clearRoom: true)
        updateIdentity(role: role, name: name)
        invitation = parsed
        canInvite = false
        persistRoom(enabled: true)
        start()
    }

    func leaveRoom() {
        stop(clearRoom: true)
        defaults.set(false, forKey: Self.enabledKey)
    }

    func updateLocalState(
        monitoring: Bool, batteryPercent: Int?, displayMode: BoyisoDisplayMode, sessionActive: Bool
    ) {
        localMonitoring = monitoring
        localBatteryPercent = batteryPercent.map { min(100, max(0, $0)) }
        localDisplayMode = displayMode
        localSessionActive = sessionActive
        if isEnabled { emit(kind: .heartbeat) }
    }

    func sendSoundEvent(intensity: Double, detail: String) {
        guard isEnabled, role == .guest, localMonitoring, localSessionActive,
              localDisplayMode == .mate, activePeersAreInActiveMate else { return }
        emit(kind: .sound, intensity: intensity, detail: detail)
    }

    func sendMovementEvent(intensity: Double = 1) {
        guard isEnabled, role == .guest, localMonitoring, localSessionActive,
              localDisplayMode == .mate, activePeersAreInActiveMate else { return }
        emit(kind: .movement, intensity: intensity, detail: "turning")
    }

    @discardableResult
    func sendTokTok(now: Date = Date()) -> Bool {
        guard isEnabled, now.timeIntervalSince(lastTokTokSentAt) >= 5 else { return false }
        lastTokTokSentAt = now
        emit(kind: .toktok, detail: "greeting")
        return true
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private var activePeersAreInActiveMate: Bool {
        !activePeers.isEmpty && activePeers.allSatisfy { $0.sessionActive && $0.displayMode == .mate }
    }

    private func persistRoom(enabled: Bool) {
        defaults.set(invitation?.roomID, forKey: Self.roomIDKey)
        defaults.set(invitation?.roomKey, forKey: Self.roomKeyKey)
        defaults.set(canInvite, forKey: Self.canInviteKey)
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    private func start() {
        guard invitation != nil, !deviceName.isEmpty else { return }
        isEnabled = true
        issueMessage = nil
        hadConnectedPeer = false
        peers = []
        startHeartbeatTimer()
        startLocalNetworkListener()
        startLocalNetworkBrowser()
        bluetoothStarted = true
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareBluetoothPeripheralIfPossible()
            self.startBluetoothScanIfPossible()
        }
        requestNotificationPermission()
    }

    private func stop(clearRoom: Bool) {
        isEnabled = false
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        peers = []; lastRemoteEvent = nil; issueMessage = nil
        hadConnectedPeer = false
        localNetworkConnectionCount = 0; bluetoothConnectionCount = 0
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel(); self.listener = nil
            self.browser?.cancel(); self.browser = nil
            self.lanConnections.values.forEach { $0.cancel() }
            self.lanConnections.removeAll(); self.receiveBuffers.removeAll(); self.knownEndpoints.removeAll()
            if self.bluetoothStarted {
                self.centralManager.stopScan()
                self.discoveredPeripherals.values.forEach { self.centralManager.cancelPeripheralConnection($0) }
                self.peripheralManager.stopAdvertising(); self.peripheralManager.removeAllServices()
            }
            self.discoveredPeripherals.removeAll(); self.subscribedCharacteristics.removeAll()
            self.subscribedCentrals.removeAll(); self.pendingFragments.removeAll(); self.eventCharacteristic = nil
        }
        if clearRoom {
            invitation = nil; canInvite = false
            defaults.removeObject(forKey: Self.roomIDKey)
            defaults.removeObject(forKey: Self.roomKeyKey)
            defaults.set(false, forKey: Self.canInviteKey)
        }
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            self.emit(kind: .heartbeat)
            self.pruneStalePeers()
        }
        emit(kind: .heartbeat)
    }

    private func emit(kind: BoyisoEventKind, intensity: Double? = nil, detail: String? = nil) {
        let event = BoyisoEvent(
            sourceID: deviceID, sourceName: deviceName, role: role, kind: kind,
            intensity: intensity, detail: detail, monitoring: localMonitoring,
            batteryPercent: localBatteryPercent, displayMode: localDisplayMode,
            sessionActive: localSessionActive
        )
        queue.async { [weak self] in self?.send(event) }
    }

    private func send(_ event: BoyisoEvent) {
        sendOverLocalNetwork(event)
        sendOverBluetooth(event)
    }

    private func startLocalNetworkListener() {
        queue.async { [weak self] in
            guard let self, self.isEnabled else { return }
            do {
                let listener = try NWListener(using: .tcp)
                listener.service = .init(name: "보이소-\(self.deviceID.uuidString.prefix(6))", type: Self.serviceType)
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed = state {
                        self?.publishIssue("Wi-Fi 수신을 다시 준비하고 있습니다.")
                        self?.queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startLocalNetworkListener() }
                    }
                }
                listener.newConnectionHandler = { [weak self] in self?.register(connection: $0) }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch { self.publishIssue("Wi-Fi 수신을 시작하지 못했습니다.") }
        }
    }

    private func startLocalNetworkBrowser() {
        queue.async { [weak self] in
            guard let self, self.isEnabled else { return }
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in self?.connect(results) }
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed = state { self?.publishIssue("같은 Wi-Fi의 기기를 다시 찾고 있습니다.") }
            }
            self.browser = browser
            browser.start(queue: self.queue)
        }
    }

    private func connect(_ results: Set<NWBrowser.Result>) {
        guard isEnabled else { return }
        let currentKeys = Set(results.map { $0.endpoint.debugDescription })
        knownEndpoints = Dictionary(uniqueKeysWithValues: results.map { ($0.endpoint.debugDescription, $0.endpoint) })
        for key in lanConnections.keys where !currentKeys.contains(key) {
            lanConnections[key]?.cancel(); lanConnections.removeValue(forKey: key); receiveBuffers.removeValue(forKey: key)
        }
        for result in results {
            let key = result.endpoint.debugDescription
            guard lanConnections[key] == nil else { continue }
            register(connection: NWConnection(to: result.endpoint, using: .tcp), key: key)
        }
    }

    private func register(connection: NWConnection, key: String = UUID().uuidString) {
        lanConnections[key] = connection
        receiveBuffers[key] = Data()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.publishConnectionCounts()
                self.receive(on: connection, key: key)
                self.emit(kind: .heartbeat)
            case .failed, .cancelled:
                self.lanConnections.removeValue(forKey: key)
                self.receiveBuffers.removeValue(forKey: key)
                self.publishConnectionCounts()
                self.reconnectLAN(key: key)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func reconnectLAN(key: String) {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isEnabled, self.lanConnections[key] == nil,
                  let endpoint = self.knownEndpoints[key] else { return }
            self.register(connection: NWConnection(to: endpoint, using: .tcp), key: key)
        }
    }

    private func receive(on connection: NWConnection, key: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty {
                var buffer = self.receiveBuffers[key, default: Data()]
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let frame = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    if let invitation = self.invitation,
                       let event = try? BoyisoCodec.openLANFrame(frame, invitation: invitation) {
                        self.accept(event, through: .localNetwork)
                    }
                }
                self.receiveBuffers[key] = buffer
            }
            if complete || error != nil {
                connection.cancel(); self.lanConnections.removeValue(forKey: key)
                self.receiveBuffers.removeValue(forKey: key); self.publishConnectionCounts()
            } else { self.receive(on: connection, key: key) }
        }
    }

    private func sendOverLocalNetwork(_ event: BoyisoEvent) {
        guard let invitation, let frame = try? BoyisoCodec.lanFrame(for: event, invitation: invitation) else { return }
        lanConnections.values.forEach { $0.send(content: frame, completion: .contentProcessed { _ in }) }
    }

    private func prepareBluetoothPeripheralIfPossible() {
        guard isEnabled, peripheralManager.state == .poweredOn else { return }
        peripheralManager.stopAdvertising(); peripheralManager.removeAllServices()
        let characteristic = CBMutableCharacteristic(
            type: Self.bluetoothEventUUID, properties: [.notify, .read], value: nil, permissions: [.readable]
        )
        let service = CBMutableService(type: Self.bluetoothServiceUUID, primary: true)
        service.characteristics = [characteristic]
        eventCharacteristic = characteristic
        peripheralManager.add(service)
    }

    private func startBluetoothScanIfPossible() {
        guard isEnabled, centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: [Self.bluetoothServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func sendOverBluetooth(_ event: BoyisoEvent) {
        guard let invitation, let characteristic = eventCharacteristic,
              let fragments = try? BoyisoCodec.bluetoothFragments(
                for: event, invitation: invitation, maximumPayloadLength: maximumBluetoothPayloadLength
              ) else { return }
        pendingFragments.append(contentsOf: fragments)
        flushBluetooth(characteristic)
    }

    private func flushBluetooth(_ characteristic: CBMutableCharacteristic) {
        while let fragment = pendingFragments.first {
            guard peripheralManager.updateValue(fragment, for: characteristic, onSubscribedCentrals: nil) else { return }
            pendingFragments.removeFirst()
        }
    }

    private func accept(_ event: BoyisoEvent, through transport: BoyisoTransportKind) {
        guard event.sourceID != deviceID else { return }
        let first = deduplicator.accepts(event)
        publish { service in service.updatePeer(event, transport: transport) }
        guard first else { return }
        send(event)
        guard event.kind != .heartbeat else { return }
        publish { service in
            service.lastRemoteEvent = event
            service.onRemoteEvent?(event)
            if event.kind == .toktok, UIApplication.shared.applicationState != .active {
                service.scheduleTokTokNotification(from: event.sourceName)
            } else if event.kind != .heartbeat, UIApplication.shared.applicationState != .active {
                service.scheduleDetectionNotification(for: event)
            }
        }
    }

    private func updatePeer(_ event: BoyisoEvent, transport: BoyisoTransportKind) {
        hadConnectedPeer = true
        issueMessage = nil
        if let index = peers.firstIndex(where: { $0.id == event.sourceID }) {
            peers[index].name = event.sourceName; peers[index].role = event.role
            peers[index].lastSeen = Date(); peers[index].monitoring = event.monitoring
            peers[index].batteryPercent = event.batteryPercent; peers[index].displayMode = event.displayMode
            peers[index].sessionActive = event.sessionActive; peers[index].transports.insert(transport)
        } else {
            peers.append(.init(id: event.sourceID, name: event.sourceName, role: event.role,
                lastSeen: Date(), monitoring: event.monitoring, batteryPercent: event.batteryPercent,
                displayMode: event.displayMode, sessionActive: event.sessionActive, transports: [transport]))
        }
    }

    private func pruneStalePeers() {
        peers.removeAll { !$0.isFresh() }
        objectWillChange.send()
    }

    private func scheduleTokTokNotification(from name: String) {
        let content = UNMutableNotificationContent()
        content.title = BoyisoBranding.primaryName
        content.subtitle = "톡톡"
        content.body = "\(name.isEmpty ? "같은 공간의 사람" : name)님이 인사를 보냈어요."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("boyiso_toktok.wav"))
        UNUserNotificationCenter.current().add(.init(identifier: "boyiso-toktok-\(UUID())", content: content, trigger: nil))
    }

    private func scheduleDetectionNotification(for event: BoyisoEvent) {
        let content = UNMutableNotificationContent()
        content.title = BoyisoBranding.primaryName
        content.body = event.kind == .movement
            ? "말할 사람의 큰 움직임이 감지되었습니다."
            : "말할 사람의 소리가 감지되었습니다."
        if !event.sourceName.isEmpty { content.subtitle = event.sourceName }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            .init(identifier: "boyiso-detection-\(event.id)", content: content, trigger: nil)
        )
    }

    private func publish(_ mutation: @escaping (BoyisoConnectivityService) -> Void) {
        DispatchQueue.main.async { [weak self] in guard let self else { return }; mutation(self) }
    }
    private func publishIssue(_ message: String) { publish { $0.issueMessage = message } }
    private func publishConnectionCounts() {
        let lan = lanConnections.values.filter { $0.state == .ready }.count
        let ble = subscribedCentrals.count + subscribedCharacteristics.count
        publish { $0.localNetworkConnectionCount = lan; $0.bluetoothConnectionCount = ble }
    }
}

extension BoyisoConnectivityService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startBluetoothScanIfPossible() }
        else if isEnabled, central.state == .unauthorized { publishIssue("Bluetooth 권한 없이 Wi-Fi만 사용합니다.") }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isEnabled else { return }
        discoveredPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.bluetoothServiceUUID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isEnabled else { return }
        queue.asyncAfter(deadline: .now() + 2) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.isEnabled else { return }
            central.connect(peripheral)
        }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        subscribedCharacteristics.removeValue(forKey: peripheral.identifier); publishConnectionCounts()
        if isEnabled { central.connect(peripheral) }
    }
}

extension BoyisoConnectivityService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        peripheral.services?.forEach { peripheral.discoverCharacteristics([Self.bluetoothEventUUID], for: $0) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.bluetoothEventUUID {
            subscribedCharacteristics[peripheral.identifier] = characteristic
            peripheral.setNotifyValue(true, for: characteristic); publishConnectionCounts()
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value,
              let combined = reassembler.append(value, peerID: peripheral.identifier.uuidString),
              let invitation, let event = try? BoyisoCodec.open(combined, invitation: invitation) else { return }
        accept(event, through: .bluetooth)
    }
}

extension BoyisoConnectivityService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn { prepareBluetoothPeripheralIfPossible() }
        else if isEnabled, peripheral.state == .unauthorized { publishIssue("Bluetooth 권한 없이 Wi-Fi만 사용합니다.") }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil, isEnabled else { if error != nil { publishIssue("Bluetooth 연결을 다시 준비하고 있습니다.") }; return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.bluetoothServiceUUID]])
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals.insert(central.identifier)
        maximumBluetoothPayloadLength = min(maximumBluetoothPayloadLength, central.maximumUpdateValueLength)
        publishConnectionCounts(); emit(kind: .heartbeat)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.remove(central.identifier); publishConnectionCounts()
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        if let characteristic = eventCharacteristic { flushBluetooth(characteristic) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
