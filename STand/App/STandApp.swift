import SwiftUI

@main
struct STandApp: App {
    @StateObject private var model = StandViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
