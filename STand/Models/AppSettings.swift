import Combine
import Foundation

struct AppSettings: Codable, Equatable {
    var lampIntensity = 0.72
    var holdDuration = 60.0
    var fadeDuration = 30.0
    var soundThresholdDB: Float = -36
    var recordingEnabled = true

    static let recommended = AppSettings()
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.0.0"
    }

    static var display: String { "\(marketing) (\(build))" }
}
