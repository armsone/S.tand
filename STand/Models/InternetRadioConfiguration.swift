import Foundation

enum InternetRadioConfigurationError: LocalizedError, Equatable {
    case emptyAddress
    case addressTooLong
    case secureAddressRequired
    case missingHost
    case credentialsNotAllowed

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            "라디오 주소를 입력해 주세요."
        case .addressTooLong:
            "라디오 주소가 너무 깁니다."
        case .secureAddressRequired:
            "https://로 시작하는 안전한 스트림 주소만 사용할 수 있습니다."
        case .missingHost:
            "서버 주소를 확인해 주세요."
        case .credentialsNotAllowed:
            "아이디나 비밀번호가 포함된 주소는 저장할 수 없습니다."
        }
    }
}

struct InternetRadioConfiguration: Codable, Equatable, Hashable, Identifiable {
    static let defaultDisplayName = "인터넷 라디오"
    static let maximumAddressLength = 2_048

    let id: UUID
    let displayName: String
    let urlString: String

    init(
        id: UUID = UUID(),
        displayName: String,
        urlString: String
    ) throws {
        let trimmedAddress = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw InternetRadioConfigurationError.emptyAddress
        }
        guard trimmedAddress.count <= Self.maximumAddressLength else {
            throw InternetRadioConfigurationError.addressTooLong
        }
        guard let components = URLComponents(string: trimmedAddress),
              components.scheme?.lowercased() == "https"
        else {
            throw InternetRadioConfigurationError.secureAddressRequired
        }
        guard let host = components.host, !host.isEmpty, components.url != nil else {
            throw InternetRadioConfigurationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw InternetRadioConfigurationError.credentialsNotAllowed
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.displayName = trimmedName.isEmpty ? Self.defaultDisplayName : String(trimmedName.prefix(30))
        self.urlString = trimmedAddress
    }

    var streamURL: URL {
        // The throwing initializer only stores URLComponents values that can form a URL.
        URL(string: urlString)!
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case urlString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: (try? container.decode(UUID.self, forKey: .id)) ?? UUID(),
            displayName: container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
            urlString: container.decode(String.self, forKey: .urlString)
        )
    }

    func updated(displayName: String, urlString: String) throws -> Self {
        try Self(id: id, displayName: displayName, urlString: urlString)
    }
}

struct SharedInternetRadioImportStore {
    static let appGroupIdentifier = "group.com.armsone.stand"
    static let pendingConfigurationKey = "internetRadio.pendingSharedConfiguration"

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: Self.appGroupIdentifier)) {
        self.defaults = defaults
    }

    @discardableResult
    func save(_ configuration: InternetRadioConfiguration) -> Bool {
        guard let defaults,
              let data = try? JSONEncoder().encode(configuration)
        else { return false }
        defaults.set(data, forKey: Self.pendingConfigurationKey)
        return true
    }

    func pendingConfiguration() -> InternetRadioConfiguration? {
        guard let defaults,
              let data = defaults.data(forKey: Self.pendingConfigurationKey)
        else { return nil }
        guard let configuration = try? JSONDecoder().decode(
            InternetRadioConfiguration.self,
            from: data
        ) else {
            defaults.removeObject(forKey: Self.pendingConfigurationKey)
            return nil
        }
        return configuration
    }

    func clearPendingConfiguration() {
        defaults?.removeObject(forKey: Self.pendingConfigurationKey)
    }
}

enum InternetRadioImportPolicy {
    static func draft(
        shared: InternetRadioConfiguration,
        existing: InternetRadioConfiguration?
    ) -> InternetRadioConfiguration {
        (try? InternetRadioConfiguration(
            id: existing?.id ?? shared.id,
            displayName: existing?.displayName ?? shared.displayName,
            urlString: shared.urlString
        )) ?? shared
    }

    static func draft(
        shared: InternetRadioConfiguration,
        existingChannels: [InternetRadioConfiguration]
    ) -> InternetRadioConfiguration {
        guard let existing = existingChannels.first(where: {
            $0.urlString == shared.urlString
        }) else { return shared }

        return (try? InternetRadioConfiguration(
            id: existing.id,
            displayName: existing.displayName,
            urlString: shared.urlString
        )) ?? shared
    }
}
