import Combine
import Foundation

enum OrientationPreference: String, Codable, CaseIterable, Identifiable {
    case automatic
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "기기 설정 따르기"
        case .portrait: "세로 고정"
        case .landscape: "가로 고정"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "rectangle.rotate"
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var lampIntensity = 0.72
    var silhouetteIntensity = 0.035
    var holdDuration = 60.0
    var fadeDuration = 30.0
    var soundThresholdDB: Float = -36
    var recordingEnabled = true
    var orientationPreference: OrientationPreference = .automatic
    var torchEnabled = false
    var torchIntensity = 0.25
    var wakeOnSleepSound = false

    static let recommended = AppSettings()

    init(
        lampIntensity: Double = 0.72,
        silhouetteIntensity: Double = 0.035,
        holdDuration: Double = 60,
        fadeDuration: Double = 30,
        soundThresholdDB: Float = -36,
        recordingEnabled: Bool = true,
        orientationPreference: OrientationPreference = .automatic,
        torchEnabled: Bool = false,
        torchIntensity: Double = 0.25,
        wakeOnSleepSound: Bool = false
    ) {
        self.lampIntensity = lampIntensity
        self.silhouetteIntensity = silhouetteIntensity
        self.holdDuration = holdDuration
        self.fadeDuration = fadeDuration
        self.soundThresholdDB = soundThresholdDB
        self.recordingEnabled = recordingEnabled
        self.orientationPreference = orientationPreference
        self.torchEnabled = torchEnabled
        self.torchIntensity = torchIntensity
        self.wakeOnSleepSound = wakeOnSleepSound
    }

    private enum CodingKeys: String, CodingKey {
        case lampIntensity
        case silhouetteIntensity
        case holdDuration
        case fadeDuration
        case soundThresholdDB
        case recordingEnabled
        case orientationPreference
        case torchEnabled
        case torchIntensity
        case wakeOnSleepSound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lampIntensity = try container.decodeIfPresent(Double.self, forKey: .lampIntensity) ?? 0.72
        silhouetteIntensity = try container.decodeIfPresent(
            Double.self,
            forKey: .silhouetteIntensity
        ) ?? 0.035
        holdDuration = try container.decodeIfPresent(Double.self, forKey: .holdDuration) ?? 60
        fadeDuration = try container.decodeIfPresent(Double.self, forKey: .fadeDuration) ?? 30
        soundThresholdDB = try container.decodeIfPresent(Float.self, forKey: .soundThresholdDB) ?? -36
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? true
        orientationPreference = try container.decodeIfPresent(
            OrientationPreference.self,
            forKey: .orientationPreference
        ) ?? .automatic
        torchEnabled = try container.decodeIfPresent(Bool.self, forKey: .torchEnabled) ?? false
        torchIntensity = try container.decodeIfPresent(Double.self, forKey: .torchIntensity) ?? 0.25
        wakeOnSleepSound = try container.decodeIfPresent(Bool.self, forKey: .wakeOnSleepSound) ?? false
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let storageKey = "appSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard
            let data = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            value = .recommended
            return
        }

        value = saved
    }

    func restoreRecommendedValues() {
        value = .recommended
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.4.0"
    }

    static var display: String { "\(marketing) (\(build))" }
}
