import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Portrait everywhere except the full screen chart, which opts into landscape.
        MainActor.assumeIsolated { OrientationLock.mask }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PushNotificationCoordinator.shared.didRegister(token: token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { await PushNotificationCoordinator.shared.didFail() }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

actor PushNotificationCoordinator {
    static let shared = PushNotificationCoordinator()

    private var deviceToken: String?
    private var tokenContinuation: CheckedContinuation<String?, Never>?

    func requestDeviceToken() async -> String? {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return nil
        }

        guard granted else { return nil }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        if let deviceToken { return deviceToken }
        return await withCheckedContinuation { continuation in
            tokenContinuation = continuation
        }
    }

    func didRegister(token: String) {
        deviceToken = token
        tokenContinuation?.resume(returning: token)
        tokenContinuation = nil
    }

    func didFail() {
        tokenContinuation?.resume(returning: nil)
        tokenContinuation = nil
    }

    nonisolated static var environment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}
