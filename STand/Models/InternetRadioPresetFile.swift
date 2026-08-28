import Foundation

/// A single channel entry as stored in the shared `.standradio.json` file.
/// Field names and JSON keys intentionally match the Android v1 interchange contract.
struct InternetRadioPresetChannel: Codable, Equatable {
    let id: String
    let displayName: String
    let streamUrl: String
}

/// The root document of the `.standradio.json` interchange file, compatible with the
/// Android S.tand app so channels can round-trip between platforms.
struct InternetRadioPresetFile: Codable, Equatable {
    let format: String
    let version: Int
    let exportedAt: Int64
    let channels: [InternetRadioPresetChannel]

    static let formatIdentifier = "s.tand-radio"
    static let currentVersion = 1
    static let defaultFilename = "S.tand-Radio.standradio.json"
    static let maximumPayloadBytes = 128 * 1_024
}

enum InternetRadioPresetError: LocalizedError, Equatable {
    case emptyPayload
    case oversizedPayload
    case invalidFormat
    case unsupportedVersion
    case decodingFailed
    case noValidChannels
    case noChannelsToExport

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            "빈 파일은 가져올 수 없습니다."
        case .oversizedPayload:
            "파일이 너무 커서 가져올 수 없습니다."
        case .invalidFormat:
            "S.tand 라디오 파일 형식이 아닙니다."
        case .unsupportedVersion:
            "지원하지 않는 파일 버전입니다."
        case .decodingFailed:
            "파일 내용을 읽을 수 없습니다."
        case .noValidChannels:
            "가져올 수 있는 채널이 없습니다."
        case .noChannelsToExport:
            "내보낼 라디오 채널이 없습니다."
        }
    }
}

/// Encodes and decodes the Android-compatible `.standradio.json` preset file.
enum InternetRadioPresetCodec {
    private static let allowedIDCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.:"
    )

    static func exportData(
        channels: [InternetRadioConfiguration],
        exportedAt: Date = Date()
    ) throws -> Data {
        let exportableChannels = Array(
            channels.prefix(AppSettings.maximumInternetRadioChannelCount)
        )
        guard !exportableChannels.isEmpty else {
            throw InternetRadioPresetError.noChannelsToExport
        }

        let file = InternetRadioPresetFile(
            format: InternetRadioPresetFile.formatIdentifier,
            version: InternetRadioPresetFile.currentVersion,
            exportedAt: Int64((exportedAt.timeIntervalSince1970 * 1_000).rounded()),
            channels: exportableChannels.map {
                InternetRadioPresetChannel(
                    id: $0.id.uuidString,
                    displayName: $0.displayName,
                    streamUrl: $0.urlString
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    /// Parses and validates a `.standradio.json` payload, returning normalized,
    /// deduplicated channels ready for preview. Throws a concise Korean error
    /// for malformed, oversized, wrong-version, or empty-result payloads.
    static func parse(_ data: Data) throws -> [InternetRadioConfiguration] {
        guard !data.isEmpty else { throw InternetRadioPresetError.emptyPayload }
        guard data.count <= InternetRadioPresetFile.maximumPayloadBytes else {
            throw InternetRadioPresetError.oversizedPayload
        }

        let file: InternetRadioPresetFile
        do {
            file = try JSONDecoder().decode(InternetRadioPresetFile.self, from: data)
        } catch {
            throw InternetRadioPresetError.decodingFailed
        }

        guard file.format == InternetRadioPresetFile.formatIdentifier else {
            throw InternetRadioPresetError.invalidFormat
        }
        guard file.version == InternetRadioPresetFile.currentVersion else {
            throw InternetRadioPresetError.unsupportedVersion
        }

        var usedIDs = Set<UUID>()
        var seenURLKeys = Set<String>()
        var result: [InternetRadioConfiguration] = []

        for entry in file.channels {
            guard let configuration = try? InternetRadioConfiguration(
                id: resolvedID(entry.id, usedIDs: &usedIDs),
                displayName: entry.displayName,
                urlString: entry.streamUrl
            ) else { continue }

            let key = dedupeKey(for: configuration.streamURL)
            guard seenURLKeys.insert(key).inserted else { continue }

            result.append(configuration)
            if result.count >= AppSettings.maximumInternetRadioChannelCount { break }
        }

        guard !result.isEmpty else { throw InternetRadioPresetError.noValidChannels }
        return result
    }

    private static func isValidID(_ raw: String) -> Bool {
        guard (1...128).contains(raw.count) else { return false }
        return raw.unicodeScalars.allSatisfy { allowedIDCharacters.contains($0) }
    }

    private static func resolvedID(_ raw: String, usedIDs: inout Set<UUID>) -> UUID {
        if isValidID(raw), let parsed = UUID(uuidString: raw), usedIDs.insert(parsed).inserted {
            return parsed
        }
        var fresh = UUID()
        while !usedIDs.insert(fresh).inserted { fresh = UUID() }
        return fresh
    }

    static func isDuplicate(
        _ candidate: InternetRadioConfiguration,
        among existing: [InternetRadioConfiguration]
    ) -> Bool {
        let key = dedupeKey(for: candidate.streamURL)
        return existing.contains { dedupeKey(for: $0.streamURL) == key }
    }

    private static func dedupeKey(for url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        let query = url.query.map { "?\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(url.path)\(query)"
    }
}

/// A parsed and validated preview of an imported `.standradio.json` file,
/// shown to the user before any settings change.
struct InternetRadioImportPreview: Identifiable {
    struct Entry: Identifiable {
        let channel: InternetRadioConfiguration
        let isDuplicate: Bool
        var id: UUID { channel.id }
    }

    let id = UUID()
    let entries: [Entry]

    var newEntries: [Entry] { entries.filter { !$0.isDuplicate } }
    var hasInsecureStreams: Bool { entries.contains { $0.channel.isInsecureStream } }
    var allDuplicates: Bool { !entries.isEmpty && newEntries.isEmpty }
}
