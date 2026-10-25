import SwiftUI
import UIKit

@main
struct VigiliaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AlarmController.shared)
                .environmentObject(AlarmAudioPlayer.shared)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// On iOS 18 to 25 the alarms are notifications, and the delegate that handles their
    /// actions must be in place before launching finishes (see `NotificationAlarmBackend`).
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = AlarmController.shared
        return true
    }
}
