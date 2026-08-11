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

@main
struct STandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = StandViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
