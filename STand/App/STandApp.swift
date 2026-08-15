import SwiftUI
import UIKit
import WidgetKit

final class OrientationController {
    static let shared = OrientationController()

    let supportedMask: UIInterfaceOrientationMask = .allButUpsideDown

    private init() {}

    func reapply() {
        requestGeometryUpdate()
    }

    private func requestGeometryUpdate() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        windowScene.windows.first?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: supportedMask)
        ) { error in
            #if DEBUG
            print("화면 방향 변경 실패: \(error.localizedDescription)")
            #endif
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let circularGlyphReloadKey = "didReloadCircularWidgetGlyphV3"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.circularGlyphReloadKey) {
            WidgetCenter.shared.reloadTimelines(ofKind: "com.armsone.stand.launch.v2")
            defaults.set(true, forKey: Self.circularGlyphReloadKey)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationController.shared.supportedMask
    }
}

enum UICatalogLaunch {
    #if DEBUG
    static let fixtureID = "ui_catalog_v2"
    static let fixedDate: Date? = Date(timeIntervalSince1970: 1_786_747_325)

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-catalog")
    }

    static var showsPermissionExplanation: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains("--ui-catalog-permissions")
    }

    static var startsInEditor: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains("--ui-catalog-editor")
    }

    static func prepareDefaults() {
        guard isEnabled else { return }

        let defaults = UserDefaults.standard
        var settings = AppSettings.recommended
        settings.soundSensingEnabled = false
        settings.recordingEnabled = false
        settings.cameraAmbientSensingEnabled = false
        settings.weatherLocationEnabled = false

        let sampleChannels = [
            try? InternetRadioConfiguration(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                displayName: "편안한 재즈",
                urlString: "https://example.com/jazz.m3u8"
            ),
            try? InternetRadioConfiguration(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                displayName: "밤의 클래식",
                urlString: "https://example.com/classic.m3u8"
            )
        ].compactMap { $0 }
        for (index, channel) in sampleChannels.enumerated() {
            settings.addInternetRadioChannel(channel, select: index == 0)
        }

        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: "appSettings")
        }
        defaults.set(true, forKey: SettingsMigration.torchEnabledByDefaultKey)
        defaults.set(true, forKey: SettingsMigration.fiveSecondHoldDurationKey)
        defaults.set(true, forKey: SettingsMigration.internetRadioChannelsKey)
        defaults.set(true, forKey: SettingsMigration.currentExperienceDefaultsKey)
        prepareRecordingFixture()
    }

    static var recordingsDirectory: URL? {
        guard isEnabled else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("S.tand-\(fixtureID)", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    private static func prepareRecordingFixture() {
        guard let directory = recordingsDirectory else { return }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let samples = [
            (resource: "sample-snore-5s", minuteOffset: 0),
            (resource: "sample-snore-10s", minuteOffset: 20),
            (resource: "sample-snore-15s", minuteOffset: 40)
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        guard let fixedDate else { return }
        let sessionStart = fixedDate.addingTimeInterval(-6 * 60 * 60)

        for sample in samples {
            guard let sourceURL = Bundle.main.url(
                forResource: sample.resource,
                withExtension: "m4a"
            ) else { continue }
            let date = sessionStart.addingTimeInterval(Double(sample.minuteOffset * 60))
            let filename = "sleep-sound-\(formatter.string(from: date))-embedded-snore.m4a"
            try? fileManager.copyItem(
                at: sourceURL,
                to: directory.appendingPathComponent(filename)
            )
        }
    }
    #else
    static let fixtureID = "disabled"
    static let fixedDate: Date? = nil
    static let isEnabled = false
    static let showsPermissionExplanation = false
    static let startsInEditor = false
    static let recordingsDirectory: URL? = nil
    static func prepareDefaults() {}
    #endif
}

@main
struct STandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: StandViewModel
    @StateObject private var firstLaunchPermissions: FirstLaunchPermissionCoordinator

    init() {
        UICatalogLaunch.prepareDefaults()
        _model = StateObject(wrappedValue: StandViewModel())
        _firstLaunchPermissions = StateObject(
            wrappedValue: FirstLaunchPermissionCoordinator()
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, firstLaunchPermissions: firstLaunchPermissions)
                .transaction { transaction in
                    if UICatalogLaunch.isEnabled {
                        transaction.disablesAnimations = true
                    }
                }
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
