import Foundation
import UserNotifications

/// iOS 18 to 25: AlarmKit does not exist, so each alarm is a time-sensitive local
/// notification with the day's sound. The weekly alarms, the re-rings and the test
/// are scheduled in iOS exactly as with AlarmKit, so they ring with the app closed.
///
/// What a notification can't do (only AlarmKit and Apple-approved critical alerts can):
/// - It doesn't ring with the iPhone on silent: it only vibrates.
/// - In a Focus it only rings if the Focus lets time-sensitive notifications through.
/// - It plays its sound once (28 s); the re-ring every minute makes up for it.
///
/// Swiping the notification away (`customDismissAction`) counts as stopping the alarm
/// from the system UI; tapping it or «Resolver reto» opens the challenge.
@MainActor
final class NotificationAlarmBackend: NSObject, AlarmBackend, UNUserNotificationCenterDelegate {
    private static let categoryID = "vigilia.alarm"
    private static let challengeActionID = "vigilia.challenge"
    private static let authorizationKey = "vigilia.notificationAuthorization"
    /// The sounds last 28 s: that long after it is delivered, a notification is ringing.
    private static let ringDuration: TimeInterval = 30

    private let center = UNUserNotificationCenter.current()
    private var calendar: Calendar { Calendar.autoupdatingCurrent }

    /// Known on the last launch, so the permission request doesn't flash on screen
    /// while iOS answers.
    private(set) var authorization: AlarmAuthorization
    /// The scheduled notifications, as of the last `refresh()` plus every change since.
    private var pending: [UUID: AlarmSchedule] = [:]
    /// When each recent notification was delivered.
    private var delivered: [UUID: Date] = [:]
    /// When each alarm was silenced with `stop(id:)`.
    private var silenced: [UUID: Date] = [:]
    private var onAlarmsChange: (@MainActor ([SystemAlarm]) -> Void)?
    private var onAuthorizationChange: (@MainActor (AlarmAuthorization) -> Void)?

    /// Must run before the app finishes launching, so that the actions of a
    /// notification that launched it reach the delegate (see `AppDelegate`).
    override init() {
        authorization = UserDefaults.standard.bool(forKey: Self.authorizationKey) ? .authorized : .notDetermined
        super.init()
        center.delegate = self
        let challenge = UNNotificationAction(
            identifier: Self.challengeActionID,
            title: "Resolver reto",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "brain.head.profile"))
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID, actions: [challenge], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        Task { _ = await self.updateAuthorization() }
    }

    // MARK: - Authorization

    func updateAuthorization() async -> AlarmAuthorization {
        let settings = await center.notificationSettings()
        let updated: AlarmAuthorization
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            updated = .authorized
        case .denied:
            updated = .denied
        case .notDetermined, .provisional:
            // Provisional notifications arrive silently: not good enough for an alarm.
            updated = .notDetermined
        @unknown default:
            updated = .denied
        }
        setAuthorization(updated)
        return updated
    }

    func requestAuthorization() async -> AlarmAuthorization {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await updateAuthorization()
    }

    private func setAuthorization(_ updated: AlarmAuthorization) {
        UserDefaults.standard.set(updated == .authorized, forKey: Self.authorizationKey)
        guard updated != authorization else { return }
        authorization = updated
        onAuthorizationChange?(updated)
    }

    // MARK: - Alarms

    func alarms() throws -> [SystemAlarm] {
        let now = Date()
        var result: [UUID: Bool] = [:]
        for (id, schedule) in pending {
            switch schedule {
            case .fixed(let date):
                if date > now {
                    result[id] = false
                } else if isRinging(id, deliveredAt: date, now: now) {
                    result[id] = true
                }
                // Otherwise it rang and is gone, like a one-shot AlarmKit alarm once stopped.
            case .weekly(let weekday, let time):
                let last = AlarmMath.latestOccurrence(schedule: [weekday: time], notAfter: now, calendar: calendar)
                result[id] = last.map { isRinging(id, deliveredAt: $0, now: now) } ?? false
            }
        }
        for (id, date) in delivered where result[id] != true && isRinging(id, deliveredAt: date, now: now) {
            result[id] = true
        }
        return result.map { SystemAlarm(id: $0.key, isAlerting: $0.value) }
    }

    func refresh() async {
        _ = await updateAuthorization()
        let requests = await center.pendingNotificationRequests()
        let notifications = await center.deliveredNotifications()
        let now = Date()

        var scheduled: [UUID: AlarmSchedule] = [:]
        for request in requests {
            guard let id = UUID(uuidString: request.identifier),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger else { continue }
            let parts = trigger.dateComponents
            if trigger.repeats, let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute {
                scheduled[id] = .weekly(weekday: weekday, time: AlarmTime(hour: hour, minute: minute))
            } else if let date = trigger.nextTriggerDate() {
                scheduled[id] = .fixed(date)
            }
        }
        pending = scheduled

        var recent: [UUID: Date] = [:]
        var old: [String] = []
        for notification in notifications {
            if now.timeIntervalSince(notification.date) < Self.ringDuration,
               let id = UUID(uuidString: notification.request.identifier) {
                recent[id] = max(recent[id] ?? .distantPast, notification.date)
            } else {
                old.append(notification.request.identifier)
            }
        }
        delivered = recent
        // The app is open: the alarms that already rang are no longer needed in the
        // Notification Center.
        center.removeDeliveredNotifications(withIdentifiers: old)
        silenced = silenced.filter { now.timeIntervalSince($0.value) < Self.ringDuration }
    }

    func schedule(id: UUID, kind: AlarmKind, schedule: AlarmSchedule, sound: String?) async throws {
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: kind)
        content.body = "Vuelve a sonar hasta que completes el reto en Vigilia."
        if let sound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
        } else {
            content.sound = .default
        }
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = Self.categoryID
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1

        let trigger: UNCalendarNotificationTrigger
        switch schedule {
        case .fixed(let date):
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        case .weekly(let weekday, let time):
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: time.hour, minute: time.minute, weekday: weekday), repeats: true)
        }
        try await center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger))
        pending[id] = schedule
    }

    func cancel(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        pending[id] = nil
        delivered[id] = nil
    }

    /// Removing a delivered notification also silences its sound.
    func stop(id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        silenced[id] = Date()
    }

    func startObserving(
        alarms: @escaping @MainActor ([SystemAlarm]) -> Void,
        authorization: @escaping @MainActor (AlarmAuthorization) -> Void
    ) {
        onAlarmsChange = alarms
        onAuthorizationChange = authorization
    }

    /// iOS silently keeps only the 64 soonest notifications instead of failing.
    func isLimitReached(_ error: Error) -> Bool {
        false
    }

    private func isRinging(_ id: UUID, deliveredAt date: Date, now: Date) -> Bool {
        let sinceDelivery = now.timeIntervalSince(date)
        return sinceDelivery >= 0 && sinceDelivery < Self.ringDuration && (silenced[id] ?? .distantPast) < date
    }

    /// No snooze: tapping the notification or its only action opens the challenge.
    private static func title(for kind: AlarmKind) -> String {
        switch kind {
        case .main: return "¡Despierta! Haz el reto"
        case .retry: return "Sigue sonando: haz el reto"
        case .test: return "Prueba de Vigilia"
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// With the app open the alarm still shows up and rings.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        let date = notification.date
        await didDeliver(identifier: identifier, at: date)
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let identifier = response.notification.request.identifier
        await didReceive(action: action, identifier: identifier)
    }

    private func didDeliver(identifier: String, at date: Date) {
        guard let id = UUID(uuidString: identifier) else { return }
        delivered[id] = date
        if let alarms = try? alarms() {
            onAlarmsChange?(alarms)
        }
    }

    private func didReceive(action: String, identifier: String) async {
        if action == UNNotificationDismissActionIdentifier {
            // Swiped away: stopped from the system UI, so it must come back.
            if let id = UUID(uuidString: identifier) {
                silenced[id] = Date()
            }
            await AlarmController.shared.alarmStoppedFromSystemUI()
        } else {
            AlarmController.shared.openChallengeFromAlarm()
        }
    }
}
