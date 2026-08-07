import SwiftUI
import UIKit

final class OrientationController {
    static let shared = OrientationController()

    private(set) var preference: OrientationPreference = .automatic

    var supportedMask: UIInterfaceOrientationMask {
        switch preference {
        case .automatic: .allButUpsideDown
        case .portrait: .portrait
        case .landscape: .landscape
        }
    }

    private init() {}

    func setPreference(_ preference: OrientationPreference) {
        guard self.preference != preference else { return }
        self.preference = preference
        requestGeometryUpdate()
    }

    func reapply() {
        requestGeometryUpdate()
    }

    func preferenceForCurrentOrientation() -> OrientationPreference {
        guard let orientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation
        else { return .portrait }

        return orientation.isLandscape ? .landscape : .portrait
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
