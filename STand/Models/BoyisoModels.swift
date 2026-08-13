import CryptoKit
import Foundation

enum BoyisoRole: String, Codable, CaseIterable, Identifiable {
    case host
    case guest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .host: "호스트"
        case .guest: "게스트"
        }
    }

    var description: String {
        switch self {
        case .host: "부모·보호자 기기"
        case .guest: "아이 곁에서 소리와 움직임을 살피는 기기"
        }
    }
}

enum BoyisoEventKind: String, Codable, Equatable {
    case heartbeat
    case sound
    case movement

    var title: String {
        switch self {
        case .heartbeat: "감시 상태"
        case .sound: "특별한 소리"
        case .movement: "움직임"
        }
    }
}

struct BoyisoEvent: Codable, Equatable, Identifiable {
    static let protocolVersion = 1

    let version: Int
    let id: UUID
    let sourceID: UUID
    let sourceName: String
    let kind: BoyisoEventKind
    let sentAtMilliseconds: Int64
    let intensity: Double?
    let detail: String?
    let monitoring: Bool
    let batteryPercent: Int?

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        sourceName: String,
        kind: BoyisoEventKind,
        sentAt: Date = Date(),
        intensity: Double? = nil,
        detail: String? = nil,
        monitoring: Bool,
        batteryPercent: Int?
    ) {
        version = Self.protocolVersion
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.kind = kind
        sentAtMilliseconds = Int64((sentAt.timeIntervalSince1970 * 1_000).rounded())
        self.intensity = intensity.map { min(1, max(0, $0)) }
        self.detail = detail
        self.monitoring = monitoring
        self.batteryPercent = batteryPercent.map { min(100, max(0, $0)) }
    }

    var sentAt: Date {
        Date(timeIntervalSince1970: Double(sentAtMilliseconds) / 1_000)
    }
}

enum BoyisoCodecError: Error, Equatable {
    case invalidRoomCode
    case invalidFrame
    case unsupportedVersion
}

enum BoyisoCodec {
    static let minimumRoomCodeLength = 8
    static let maximumRoomCodeLength = 8
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func normalizedRoomCode(_ value: String) -> String {
        let allowed = value.uppercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(allowed)).prefix(maximumRoomCodeLength).description
    }

    static func isValidRoomCode(_ value: String) -> Bool {
        normalizedRoomCode(value).count == minimumRoomCodeLength
    }

    static func makeRoomCode() -> String {
        String((0..<minimumRoomCodeLength).compactMap { _ in alphabet.randomElement() })
    }

    static func seal(_ event: BoyisoEvent, roomCode: String) throws -> Data {
        let key = try key(for: roomCode)
        let encoded = try JSONEncoder().encode(event)
        guard let combined = try AES.GCM.seal(encoded, using: key).combined else {
            throw BoyisoCodecError.invalidFrame
        }
        return combined
    }

    static func open(_ combined: Data, roomCode: String) throws -> BoyisoEvent {
        let key = try key(for: roomCode)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let cleartext = try AES.GCM.open(sealedBox, using: key)
        let event = try JSONDecoder().decode(BoyisoEvent.self, from: cleartext)
        guard event.version == BoyisoEvent.protocolVersion else {
            throw BoyisoCodecError.unsupportedVersion
        }
        return event
    }

    static func lanFrame(for event: BoyisoEvent, roomCode: String) throws -> Data {
        var frame = try seal(event, roomCode: roomCode).base64EncodedData()
        frame.append(0x0A)
        return frame
    }

    static func openLANFrame(_ frame: Data, roomCode: String) throws -> BoyisoEvent {
        let trimmed = frame.prefix { $0 != 0x0A && $0 != 0x0D }
        guard let combined = Data(base64Encoded: Data(trimmed)) else {
            throw BoyisoCodecError.invalidFrame
        }
        return try open(combined, roomCode: roomCode)
    }

    static func bluetoothFragments(
        for event: BoyisoEvent,
        roomCode: String,
        maximumPayloadLength: Int
    ) throws -> [Data] {
        let headerLength = 9
        let chunkLength = max(1, maximumPayloadLength - headerLength)
        let combined = try seal(event, roomCode: roomCode)
        let count = Int(ceil(Double(combined.count) / Double(chunkLength)))
        guard count <= Int(UInt16.max) else { throw BoyisoCodecError.invalidFrame }
        let messageID = UInt32.random(in: .min ... .max)

        return (0..<count).map { index in
            let lower = index * chunkLength
            let upper = min(combined.count, lower + chunkLength)
            var fragment = Data([1])
            fragment.append(contentsOf: messageID.bigEndianBytes)
            fragment.append(contentsOf: UInt16(index).bigEndianBytes)
            fragment.append(contentsOf: UInt16(count).bigEndianBytes)
            fragment.append(combined[lower..<upper])
            return fragment
        }
    }

    private static func key(for roomCode: String) throws -> SymmetricKey {
        let normalized = normalizedRoomCode(roomCode)
        guard isValidRoomCode(normalized) else { throw BoyisoCodecError.invalidRoomCode }
        return SymmetricKey(data: Data(SHA256.hash(data: Data("boyiso-v1|\(normalized)".utf8))))
    }
}

struct BoyisoBluetoothReassembler {
    private struct PendingMessage {
        let expectedCount: Int
        let createdAt: Date
        var chunks: [Int: Data]
    }

    private var pending: [String: PendingMessage] = [:]

    mutating func append(_ fragment: Data, peerID: String, now: Date = Date()) -> Data? {
        pending = pending.filter { now.timeIntervalSince($0.value.createdAt) < 15 }
        guard fragment.count >= 9, fragment[fragment.startIndex] == 1 else { return nil }
        let messageID = fragment.readUInt32(at: 1)
        let index = Int(fragment.readUInt16(at: 5))
        let count = Int(fragment.readUInt16(at: 7))
        guard count > 0, index >= 0, index < count else { return nil }

        let key = "\(peerID)|\(messageID)"
        var message = pending[key] ?? PendingMessage(
            expectedCount: count,
            createdAt: now,
            chunks: [:]
        )
        guard message.expectedCount == count else {
            pending.removeValue(forKey: key)
            return nil
        }
        message.chunks[index] = Data(fragment.dropFirst(9))
        pending[key] = message
        guard message.chunks.count == count else { return nil }

        var combined = Data()
        for chunkIndex in 0..<count {
            guard let chunk = message.chunks[chunkIndex] else { return nil }
            combined.append(chunk)
        }
        pending.removeValue(forKey: key)
        return combined
    }
}

struct BoyisoEventDeduplicator {
    private var seen: [UUID: Date] = [:]
    private let retention: TimeInterval

    init(retention: TimeInterval = 120) {
        self.retention = retention
    }

    mutating func accepts(_ event: BoyisoEvent, now: Date = Date()) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) < retention }
        guard seen[event.id] == nil else { return false }
        seen[event.id] = now
        return true
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[startIndex + offset]) << 8)
            | UInt16(self[startIndex + offset + 1])
    }

    func readUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[startIndex + offset]) << 24)
            | (UInt32(self[startIndex + offset + 1]) << 16)
            | (UInt32(self[startIndex + offset + 2]) << 8)
            | UInt32(self[startIndex + offset + 3])
    }
}
