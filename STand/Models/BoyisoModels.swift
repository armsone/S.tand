import CryptoKit
import Foundation
import Security

enum BoyisoRole: String, Codable, CaseIterable, Identifiable {
    case host
    case guest

    var id: String { rawValue }
    var title: String { self == .host ? "볼 사람" : "말할 사람" }
    var description: String {
        self == .host
            ? "같은 공간의 소리와 연결 상태를 봅니다."
            : "이 기기에서 소리와 큰 뒤척임을 살펴 알립니다."
    }
}

enum BoyisoEventKind: String, Codable, Equatable {
    case heartbeat, sound, movement, toktok

    var title: String {
        switch self {
        case .heartbeat: "연결 상태"
        case .sound: "특별한 소리"
        case .movement: "큰 뒤척임"
        case .toktok: "톡톡"
        }
    }
}

enum BoyisoDisplayMode: String, Codable, Equatable {
    case object, mate
}

struct BoyisoInvitation: Equatable {
    static let scheme = "stand"
    static let host = "boyiso"
    static let version = "2"

    let roomID: String
    let roomKey: String

    init(roomID: String, roomKey: String) throws {
        guard Self.decoded(roomID)?.count == 12, Self.decoded(roomKey)?.count == 32 else {
            throw BoyisoCodecError.invalidInvitation
        }
        self.roomID = roomID
        self.roomKey = roomKey
    }

    init(url: URL) throws {
        guard url.scheme == Self.scheme, url.host == Self.host,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "v" })?.value == Self.version,
              let room = parts.queryItems?.first(where: { $0.name == "room" })?.value,
              let key = parts.queryItems?.first(where: { $0.name == "key" })?.value
        else { throw BoyisoCodecError.invalidInvitation }
        try self.init(roomID: room, roomKey: key)
    }

    static func make() -> BoyisoInvitation {
        try! BoyisoInvitation(roomID: randomToken(bytes: 12), roomKey: randomToken(bytes: 32))
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = Self.host
        parts.queryItems = [
            URLQueryItem(name: "v", value: Self.version),
            URLQueryItem(name: "room", value: roomID),
            URLQueryItem(name: "key", value: roomKey)
        ]
        return parts.url!
    }

    private static func randomToken(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func decoded(_ token: String) -> Data? { Data(base64URL: token) }
}

struct BoyisoEvent: Codable, Equatable, Identifiable {
    static let protocolVersion = 2

    let version: Int
    let id: UUID
    let sourceID: UUID
    let sourceName: String
    let role: BoyisoRole
    let kind: BoyisoEventKind
    let sentAtMilliseconds: Int64
    let intensity: Double?
    let detail: String?
    let monitoring: Bool
    let batteryPercent: Int?
    let displayMode: BoyisoDisplayMode?
    let sessionActive: Bool

    init(
        id: UUID = UUID(), sourceID: UUID, sourceName: String, role: BoyisoRole,
        kind: BoyisoEventKind, sentAt: Date = Date(), intensity: Double? = nil,
        detail: String? = nil, monitoring: Bool, batteryPercent: Int?,
        displayMode: BoyisoDisplayMode? = nil, sessionActive: Bool = false
    ) {
        version = Self.protocolVersion
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.role = role
        self.kind = kind
        sentAtMilliseconds = Int64((sentAt.timeIntervalSince1970 * 1_000).rounded())
        self.intensity = intensity.map { min(1, max(0, $0)) }
        self.detail = detail
        self.monitoring = monitoring
        self.batteryPercent = batteryPercent.map { min(100, max(0, $0)) }
        self.displayMode = displayMode
        self.sessionActive = sessionActive
    }

    var sentAt: Date { Date(timeIntervalSince1970: Double(sentAtMilliseconds) / 1_000) }
    var isCryingSound: Bool {
        kind == .sound && ["big_sound", "continuous_sound", "finger_snap"].contains(detail)
    }
}

enum BoyisoCodecError: Error, Equatable {
    case invalidInvitation, invalidFrame, unsupportedVersion
}

enum BoyisoCodec {
    static func routingChannel(invitation: BoyisoInvitation) -> String {
        let data = Data("boyiso-route-v2|\(invitation.roomID)|\(invitation.roomKey)".utf8)
        return Data(SHA256.hash(data: data)).base64URLEncodedString()
    }

    static func seal(_ event: BoyisoEvent, invitation: BoyisoInvitation) throws -> Data {
        let encoded = try JSONEncoder().encode(event)
        guard let combined = try AES.GCM.seal(encoded, using: key(invitation)).combined else {
            throw BoyisoCodecError.invalidFrame
        }
        return combined
    }

    static func open(_ combined: Data, invitation: BoyisoInvitation) throws -> BoyisoEvent {
        let cleartext = try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key(invitation))
        let event = try JSONDecoder().decode(BoyisoEvent.self, from: cleartext)
        guard event.version == BoyisoEvent.protocolVersion else { throw BoyisoCodecError.unsupportedVersion }
        return event
    }

    static func lanFrame(for event: BoyisoEvent, invitation: BoyisoInvitation) throws -> Data {
        var frame = try seal(event, invitation: invitation).base64EncodedData()
        frame.append(0x0A)
        return frame
    }

    static func openLANFrame(_ frame: Data, invitation: BoyisoInvitation) throws -> BoyisoEvent {
        let trimmed = frame.prefix { $0 != 0x0A && $0 != 0x0D }
        guard let combined = Data(base64Encoded: Data(trimmed)) else { throw BoyisoCodecError.invalidFrame }
        return try open(combined, invitation: invitation)
    }

    static func bluetoothFragments(
        for event: BoyisoEvent, invitation: BoyisoInvitation, maximumPayloadLength: Int
    ) throws -> [Data] {
        let headerLength = 9
        let chunkLength = max(1, maximumPayloadLength - headerLength)
        let combined = try seal(event, invitation: invitation)
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

    private static func key(_ invitation: BoyisoInvitation) -> SymmetricKey {
        SymmetricKey(data: Data(SHA256.hash(data: Data("boyiso-v2|\(invitation.roomKey)".utf8))))
    }
}

struct BoyisoBluetoothReassembler {
    private struct Pending { let count: Int; let createdAt: Date; var chunks: [Int: Data] }
    private var pending: [String: Pending] = [:]

    mutating func append(_ fragment: Data, peerID: String, now: Date = Date()) -> Data? {
        pending = pending.filter { now.timeIntervalSince($0.value.createdAt) < 15 }
        guard fragment.count >= 9, fragment[fragment.startIndex] == 1 else { return nil }
        let messageID = fragment.readUInt32(at: 1)
        let index = Int(fragment.readUInt16(at: 5))
        let count = Int(fragment.readUInt16(at: 7))
        guard count > 0, index >= 0, index < count else { return nil }
        let key = "\(peerID)|\(messageID)"
        var value = pending[key] ?? Pending(count: count, createdAt: now, chunks: [:])
        guard value.count == count else { pending.removeValue(forKey: key); return nil }
        value.chunks[index] = Data(fragment.dropFirst(9))
        pending[key] = value
        guard value.chunks.count == count else { return nil }
        let combined = (0..<count).reduce(into: Data()) { output, chunk in output.append(value.chunks[chunk]!) }
        pending.removeValue(forKey: key)
        return combined
    }
}

struct BoyisoEventDeduplicator {
    private var seen: [UUID: Date] = [:]
    private let retention: TimeInterval
    init(retention: TimeInterval = 600) { self.retention = retention }
    mutating func accepts(_ event: BoyisoEvent, now: Date = Date()) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) < retention }
        guard seen[event.id] == nil else { return false }
        seen[event.id] = now
        return true
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] { withUnsafeBytes(of: bigEndian) { Array($0) } }
}

private extension Data {
    init?(base64URL: String) {
        var value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func readUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[startIndex + offset]) << 8) | UInt16(self[startIndex + offset + 1])
    }
    func readUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[startIndex + offset]) << 24) | (UInt32(self[startIndex + offset + 1]) << 16)
            | (UInt32(self[startIndex + offset + 2]) << 8) | UInt32(self[startIndex + offset + 3])
    }
}
