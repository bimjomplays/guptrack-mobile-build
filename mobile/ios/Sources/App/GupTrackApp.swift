import SwiftUI

@main
struct GupTrackApp: App {
    @State private var model = AppModel.make()

    var body: some Scene {
        WindowGroup {
            Group {
                // as the unit tests' host the app shows nothing; the screen tests draw their own RootView
                if NSClassFromString("XCTestCase") != nil { Color.clear } else { RootView() }
            }
            .environment(model)
            .preferredColorScheme(.dark)
            .tint(Theme.brand)
        }
    }
}
