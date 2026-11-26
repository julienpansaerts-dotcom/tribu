import FirebaseFirestore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Délégué de l'application : notifications push (Firebase Cloud Messaging) et action « C'est fait ».
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    /// Appelé quand Firebase fournit (ou renouvelle) le jeton de notification de cet iPhone.
    static var onToken: ((String) -> Void)?
    static var latestToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "C'est fait", options: [])
        let later = UNNotificationAction(identifier: "OPEN", title: "Ouvrir", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "REMINDER", actions: [done, later], intentIdentifiers: []),
        ])
        if Backend.isConfigured {
            Messaging.messaging().delegate = self
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if Backend.isConfigured {
            Messaging.messaging().apnsToken = deviceToken
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Self.latestToken = fcmToken
        DispatchQueue.main.async { Self.onToken?(fcmToken) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        guard
            response.actionIdentifier == "DONE",
            Backend.isConfigured,
            let householdId = info["householdId"] as? String,
            let reminderId = info["reminderId"] as? String
        else {
            completionHandler()
            return
        }
        let name = UserDefaults.standard.string(forKey: "tribu.authorName") ?? ""
        Firestore.firestore()
            .collection("households").document(householdId)
            .collection("reminders").document(reminderId)
            .updateData(["doneAt": Timestamp(date: .now), "doneByName": name]) { _ in
                completionHandler()
            }
    }
}

enum NotificationPermission {
    /// Demande l'autorisation d'afficher des notifications puis inscrit l'iPhone auprès d'Apple.
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}
