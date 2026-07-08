import UserNotifications

actor NotificationManager {
    static let shared = NotificationManager()

    func requestPermission() async {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func postFailure(volumeID: UUID, volumeName: String, checkType: String, issues: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = volumeName
        content.subtitle = "\(checkType) Check Failed"
        content.body = "\(issues.count) issue\(issues.count == 1 ? "" : "s") found"
        content.sound = .default
        content.userInfo = ["volumeID": volumeID.uuidString]

        let id = "ai.failure.\(volumeName.lowercased().filter(\.isLetter))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// For a check that couldn't run at all because the archive wasn't reachable (e.g. an
    /// unplugged drive) — distinct from postFailure since no issue was actually found and
    /// nothing gets recorded in the UI, so this must not claim otherwise.
    func postUnreachable(volumeID: UUID, volumeName: String, checkType: String) async {
        let content = UNMutableNotificationContent()
        content.title = volumeName
        content.subtitle = "\(checkType) Check Skipped"
        content.body = "Archive not found — is the drive connected?"
        content.sound = .default
        content.userInfo = ["volumeID": volumeID.uuidString]

        let id = "ai.unreachable.\(volumeName.lowercased().filter(\.isLetter))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Routes a tap on a failure notification back into the app: open Settings and select that volume.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    var onTapVolume: ((UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let idString = response.notification.request.content.userInfo["volumeID"] as? String,
           let volumeID = UUID(uuidString: idString) {
            onTapVolume?(volumeID)
        }
        completionHandler()
    }
}
