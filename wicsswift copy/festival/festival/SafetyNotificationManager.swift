import Foundation
import UserNotifications

@MainActor
final class SafetyNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SafetyNotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            }
        } catch {
            // Intentionally ignore here; app should continue even if notifications fail.
        }
    }

    func postSafetyAlert(title: String = "Friend Safety Alert", body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        content.interruptionLevel = .critical

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        SafetyLog.debug("[SAFETY][NOTIF] enqueue title=\(title) body=\(body)")
        center.add(request) { error in
            if let error {
                SafetyLog.error("[SAFETY][NOTIF] enqueue failed error=\(error.localizedDescription)")
            } else {
                SafetyLog.debug("[SAFETY][NOTIF] enqueue success")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
