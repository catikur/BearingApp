import Foundation
import UserNotifications

/// Yerel bildirimleri kurar. iOS uygulama başına en fazla 64 BEKLEYEN bildirime izin verir;
/// bu yüzden tekrarlayan trigger yerine "yuvarlanan pencere" kullanıyoruz:
/// yalnızca önümüzdeki N günü kuruyoruz, uygulama her öne geldiğinde yeniden dolduruyoruz.
@MainActor
final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()

    @Published var authorized = false
    @Published var pendingCount = 0
    @Published var lastScheduled: Date?

    private let center = UNUserNotificationCenter.current()
    private let categoryId = "PLAN_ITEM"

    private init() {}

    // MARK: İzin + aksiyonlar
    func registerCategories() {
        let done = UNNotificationAction(identifier: "DONE", title: "Yaptım", options: [])
        let skip = UNNotificationAction(identifier: "SKIP", title: "Atladım", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "30 dk ertele", options: [])
        let cat = UNNotificationCategory(identifier: categoryId,
                                         actions: [done, skip, snooze],
                                         intentIdentifiers: [],
                                         options: [])
        center.setNotificationCategories([cat])
    }

    func requestAuthorization() async {
        do {
            let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorized = ok
        } catch {
            authorized = false
        }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        pendingCount = await center.pendingNotificationRequests().count
    }

    // MARK: Kurulum
    /// Tüm bekleyenleri temizleyip yeni pencereyi kurar.
    func reschedule(items: [PlanItem],
                    settings: NotificationSettings,
                    unlockedPhase: Int,
                    phaseEnabled: Bool) async {

        center.removeAllPendingNotificationRequests()
        guard settings.enabled, authorized else {
            await refreshStatus(); return
        }

        let cal = Calendar.current
        let now = Date()
        var planned: [(Date, PlanOccurrence)] = []

        for offset in 0..<max(1, settings.horizonDays) {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let occ = PlanEngine.occurrences(on: day, items: items,
                                             unlockedPhase: unlockedPhase, phaseEnabled: phaseEnabled)
            for o in occ {
                guard o.item.notify, !o.item.locked else { continue }
                guard settings.allows(o.item.category) else { continue }
                let fireDate = o.when.addingTimeInterval(TimeInterval(-o.item.leadMinutes * 60))
                guard fireDate > now else { continue }
                guard !settings.isQuiet(TimeOfDay.from(fireDate)) else { continue }
                planned.append((fireDate, o))
            }
        }

        // En yakın tarihliler öncelikli, sınırı aşma
        planned.sort { $0.0 < $1.0 }
        for (fireDate, occ) in planned.prefix(settings.maxScheduled) {
            let content = UNMutableNotificationContent()
            content.title = occ.item.title
            content.body = occ.item.detail.isEmpty
                ? occ.item.category.label
                : occ.item.detail
            content.sound = .default
            content.categoryIdentifier = categoryId
            content.userInfo = ["occurrenceKey": occ.key]
            content.threadIdentifier = occ.item.category.rawValue

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: occ.key, content: content, trigger: trigger)
            try? await center.add(req)
        }

        lastScheduled = Date()
        await refreshStatus()
    }

    /// "30 dk ertele" aksiyonu
    func snooze(occurrenceKey: String, title: String, body: String, minutes: Int = 30) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["occurrenceKey": occurrenceKey]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let req = UNNotificationRequest(identifier: occurrenceKey + "|snooze", content: content, trigger: trigger)
        try? await center.add(req)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        pendingCount = 0
    }
}

/// Bildirim aksiyonlarını yakalar (uygulama kapalıyken de tetiklenir).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// (occurrenceKey, actionId) — App tarafından PlanStore'a bağlanır
    var onAction: ((String, String) -> Void)?
    /// Erteleme için (key, title, body)
    var onSnooze: ((String, String, String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification) async
                               -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]      // uygulama açıkken de göster
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let key = info["occurrenceKey"] as? String else { return }
        let action = response.actionIdentifier

        if action == "SNOOZE" {
            let c = response.notification.request.content
            onSnooze?(key, c.title, c.body)
        } else if action == "DONE" || action == "SKIP" {
            onAction?(key, action)
        }
    }
}
