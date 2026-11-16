import Foundation
import UserNotifications

/// Morning questionnaire reminders (Reminders.java): first at the set time (08:00 by default), then
/// every 2 hours until it's filled in or it's 21:00. iOS can't wake the app to check, so the next week
/// of reminders is booked ahead and today's are taken off as soon as the questionnaire is done here.
enum Reminders {
    static let prefix = "wellness-"
    static let repeatHours = 2
    static let lastHour = 21

    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// done = today's questionnaire is filled in on this phone.
    @MainActor
    static func schedule() {
        let center = UNUserNotificationCenter.current()
        let me = Prefs.athleteId
        let doneToday = !me.isEmpty && Wellness.done(Store.shared, me, Fmt.today())
        let athlete = !me.isEmpty && !Prefs.isCoach && !Prefs.demoMode
        let hour = Prefs.reminderHour, minute = Prefs.reminderMinute
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) })
            guard athlete else { return }
            let cal = Calendar.current
            let now = Date()
            for dayOffset in 0..<7 {
                if dayOffset == 0 && doneToday { continue }
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                var h = hour, m = minute, slot = 0
                while h < lastHour && slot < 7 {
                    var c = cal.dateComponents([.year, .month, .day], from: day)
                    c.hour = h
                    c.minute = m
                    if let when = cal.date(from: c), when > now {
                        let content = UNMutableNotificationContent()
                        content.title = slot == 0 ? "Dobro jutro! Jutarnji upitnik" : "Jutarnji upitnik još čeka"
                        content.body = "30 sekundi: san, upala, raspoloženje."
                        content.sound = .default
                        content.userInfo = ["wellness": true]
                        let trig = UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
                        center.add(UNNotificationRequest(identifier: prefix + "\(dayOffset)-\(slot)", content: content, trigger: trig))
                    }
                    h += repeatHours
                    m = 0
                    slot += 1
                }
            }
        }
    }

    static func test() {
        let content = UNMutableNotificationContent()
        content.title = "Dobro jutro! Jutarnji upitnik"
        content.body = "30 sekundi: san, upala, raspoloženje."
        content.sound = .default
        content.userInfo = ["wellness": true]
        let trig = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(Date().timeIntervalSince1970)", content: content, trigger: trig))
    }

    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}

@MainActor
enum Wellness {
    static func questionnaire(_ s: Store) -> JSON { s.doc(Store.config, "questionnaire") ?? Model.defaultQuestionnaire() }

    static func daily(_ s: Store, _ athleteId: String, _ date: String) -> JSON {
        s.doc(Store.daily, Model.dailyId(athleteId, date)) ?? ["id": .str(Model.dailyId(athleteId, date)), "athleteId": .str(athleteId), "date": .str(date)]
    }

    static func done(_ s: Store, _ athleteId: String, _ date: String) -> Bool {
        s.doc(Store.daily, Model.dailyId(athleteId, date))?.bool("wellnessDone") ?? false
    }
}
