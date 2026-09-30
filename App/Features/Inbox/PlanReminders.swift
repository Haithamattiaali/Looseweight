import Foundation
import LooseweightKit
import UserNotifications

/// A gentle local reminder about an hour after a plan is saved. Nothing is sent anywhere.
enum PlanReminders {
    static func schedule(for record: PlannedMealRecord, isUITest: Bool) {
        guard !isUITest else { return }
        let id = record.id.uuidString
        let mealName = record.mealType.title.lowercased()
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "How did your \(mealName) go?"
            content.body = "Tap to confirm what you ate. Your plan only counts once you confirm it."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: PlanInbox.reminderDelay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "plan-\(id)", content: content, trigger: trigger))
        }
    }

    static func cancel(for record: PlannedMealRecord) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["plan-\(record.id.uuidString)"])
    }
}
