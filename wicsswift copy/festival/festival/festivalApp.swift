import SwiftUI

@main
struct festivalApp: App {
    init() {
        SafetyNotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await SafetyNotificationManager.shared.requestAuthorizationIfNeeded()
                }
        }
    }
}
