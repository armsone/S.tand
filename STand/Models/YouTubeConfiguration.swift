import Foundation

enum YouTubeConfigurationError: LocalizedError, Equatable {
    case emptyAddress
    case addressTooLong
    case secureAddressRequired
    case unsupportedHost
    case credentialsNotAllowed
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            "YouTube 주소를 입력해 주세요."
        case .addressTooLong:
            "YouTube 주소가 너무 깁니다."
        case .secureAddressRequired:
            "https://로 시작하는 YouTube 주소만 사용할 수 있습니다."
        case .unsupportedHost:
            "youtube.com 또는 youtu.be 주소를 확인해 주세요."
        case .credentialsNotAllowed:
            "아이디나 비밀번호가 포함된 주소는 저장할 수 없습니다."
        case .unsupportedContent:
            "YouTube 영상, 라이브 또는 재생목록 주소를 입력해 주세요."
        }
    }
}

struct YouTubeConfiguration: Codable, Equatable, Hashable, Identifiable {
    static let defaultDisplayName = "YouTube"
    static let maximumAddressLength = 2_048

    let displayName: String
    let urlString: String
    let videoID: String?
    let playlistID: String?

    var id: String { urlString }

    var originalURL: URL? { URL(string: urlString) }

    init(displayName: String, urlString: String) throws {
        let trimmedAddress = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw YouTubeConfigurationError.emptyAddress
        }
        guard trimmedAddress.count <= Self.maximumAddressLength else {
            throw YouTubeConfigurationError.addressTooLong
        }
        guard let components = URLComponents(string: trimmedAddress),
              components.scheme?.lowercased() == "https"
        else {
            throw YouTubeConfigurationError.secureAddressRequired
        }
        guard let host = components.host?.lowercased(), Self.allowedHosts.contains(host) else {
            throw YouTubeConfigurationError.unsupportedHost
        }
        guard components.user == nil, components.password == nil else {
            throw YouTubeConfigurationError.credentialsNotAllowed
        }

        let content = Self.content(from: components, host: host)
        guard content.videoID != nil || content.playlistID != nil else {
            throw YouTubeConfigurationError.unsupportedContent
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = trimmedName.isEmpty
            ? Self.defaultDisplayName
            : String(trimmedName.prefix(30))
        self.urlString = trimmedAddress
        self.videoID = content.videoID
        self.playlistID = content.playlistID
    }

    var embedURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = videoID.map { "/embed/\($0)" } ?? "/embed/videoseries"

        var queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "origin", value: "https://www.youtube.com")
        ]
        if let playlistID {
            queryItems.append(URLQueryItem(name: "list", value: playlistID))
        }
        components.queryItems = queryItems
        return components.url!
    }

    var contentDescription: String {
        if videoID != nil, playlistID != nil { return "영상 · 재생목록" }
        if playlistID != nil { return "재생목록" }
        return "영상 또는 라이브"
    }

    private static let allowedHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be"
    ]

    private static func content(
        from components: URLComponents,
        host: String
    ) -> (videoID: String?, playlistID: String?) {
        let queryItems = components.queryItems ?? []
        let playlistID = validatedPlaylistID(
            queryItems.first(where: { $0.name == "list" })?.value
        )

        if host == "youtu.be" {
            return (
                validatedVideoID(components.path.split(separator: "/").first.map(String.init)),
                playlistID
            )
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        if components.path == "/watch" {
            let videoID = validatedVideoID(
                queryItems.first(where: { $0.name == "v" })?.value
            )
            return (videoID, playlistID)
        }
        if components.path == "/playlist" {
            return (nil, playlistID)
        }
        if pathParts.count >= 2,
           ["live", "shorts", "embed"].contains(pathParts[0]) {
            return (validatedVideoID(pathParts[1]), playlistID)
        }
        return (nil, nil)
    }

    private static func validatedVideoID(_ candidate: String?) -> String? {
        guard let candidate,
              candidate.count == 11,
              candidate.unicodeScalars.allSatisfy(allowedIdentifierCharacters.contains)
        else { return nil }
        return candidate
    }

    private static func validatedPlaylistID(_ candidate: String?) -> String? {
        guard let candidate,
              (10...128).contains(candidate.count),
              candidate.unicodeScalars.allSatisfy(allowedIdentifierCharacters.contains)
        else { return nil }
        return candidate
    }

    private static let allowedIdentifierCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )
}
