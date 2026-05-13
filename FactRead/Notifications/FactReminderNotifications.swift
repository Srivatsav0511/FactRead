import Foundation
import UserNotifications
import UIKit

@MainActor
final class FactReminderNotifications {
    static let shared = FactReminderNotifications()

    private init() {}

    private enum IDs {
        static let morning = "factbook.reminder.morning"
        static let night = "factbook.reminder.night"
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func sync(enabled: Bool, language: AppLanguage) async -> Bool {
        _ = language
        if enabled {
            let granted = await requestAuthorizationIfNeeded()
            guard granted else {
                await cancelAll()
                return false
            }
            await scheduleDaily()
            return true
        }

        await cancelAll()
        return true
    }

    private func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [IDs.morning, IDs.night, "factbook.reminder.evening"])
        await clearDeliveredAndBadge()
    }

    private func scheduleDaily() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [IDs.morning, IDs.night, "factbook.reminder.evening"])

        let morning = makeContent(slot: .morning)
        let night = makeContent(slot: .night)

        let morningTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 7, minute: 0),
            repeats: true
        )
        let nightTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 21, minute: 0),
            repeats: true
        )

        let morningRequest = UNNotificationRequest(identifier: IDs.morning, content: morning, trigger: morningTrigger)
        let nightRequest = UNNotificationRequest(identifier: IDs.night, content: night, trigger: nightTrigger)

        do {
            try await center.add(morningRequest)
            try await center.add(nightRequest)
            await clearDeliveredAndBadge()
        } catch {
            // Best-effort scheduling.
        }
    }

    func clearDeliveredAndBadge() async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [IDs.morning, IDs.night, "factbook.reminder.evening"])
        try? await center.setBadgeCount(0)
    }

    private enum Slot {
        case morning
        case night
    }

    private func makeContent(slot: Slot) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        let lines = englishLines
        let morningLine = lines.morning.randomElement() ?? "Start with one fact."
        let nightLine = lines.night.randomElement() ?? "One last page before sleep."

        content.title = (slot == .morning) ? lines.titleMorning : lines.titleNight
        content.body = (slot == .morning) ? morningLine : nightLine
        content.sound = .default
        content.badge = 1
        return content
    }

    private var englishLines: (titleMorning: String, titleNight: String, morning: [String], night: [String]) {
        (
            "Morning Read",
            "Night Read",
            [
                "Start with one fact.",
                "One page. Sharper mind.",
                "Tiny fact. Big perspective."
            ],
            [
                "One last page before sleep.",
                "Trade scrolling for a single fact.",
                "Quiet brain. One clean idea."
            ]
        )
    }
}
