import UserNotifications

actor NotificationManager {
    static let shared = NotificationManager()

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func postFailure(volumeName: String, issues: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = "Archive Check Failed"
        content.subtitle = volumeName
        content.body = issues.first ?? "\(issues.count) issue(s) detected"
        content.sound = .default

        let id = "ai.failure.\(volumeName.lowercased().filter(\.isLetter))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
