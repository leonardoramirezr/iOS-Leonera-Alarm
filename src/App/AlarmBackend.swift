import Foundation

/// Whether the app may schedule alarms.
enum AlarmAuthorization: Equatable {
    case notDetermined, denied, authorized
}

enum AlarmKind: String {
    case main, retry, test
}

/// When an alarm rings.
enum AlarmSchedule: Equatable {
    /// Once, at that moment.
    case fixed(Date)
    /// Every week on `weekday` (Calendar numbering: 1 = Sunday … 7 = Saturday) at `time`.
    case weekly(weekday: Int, time: AlarmTime)
}

/// One of the app's alarms as the system has it.
struct SystemAlarm {
    var id: UUID
    /// Ringing right now.
    var isAlerting: Bool
}

/// What actually schedules the alarms in iOS:
/// - iOS 26 or later: AlarmKit (`AlarmKitBackend`).
/// - iOS 18 to 25: local notifications (`NotificationAlarmBackend`), since AlarmKit
///   does not exist there.
@MainActor
protocol AlarmBackend: AnyObject {
    /// The latest known authorization (the notification fallback learns it
    /// asynchronously, see `updateAuthorization()`).
    var authorization: AlarmAuthorization { get }
    /// Asks the system for the current authorization.
    func updateAuthorization() async -> AlarmAuthorization
    func requestAuthorization() async -> AlarmAuthorization

    /// The app's alarms the system has right now: scheduled, or ringing.
    func alarms() throws -> [SystemAlarm]
    /// Brings `alarms()` and `authorization` up to date where the system only
    /// answers asynchronously.
    func refresh() async
    /// When each alarm started ringing, as far as the app knows: the moment iOS delivered
    /// it when the system reports that, otherwise when the app first saw it ringing.
    var lastRings: [UUID: Date] { get }

    func schedule(id: UUID, kind: AlarmKind, schedule: AlarmSchedule, sound: String?) async throws
    func cancel(id: UUID)
    /// Silences an alarm that is ringing.
    func stop(id: UUID)

    /// `alarms` runs whenever the app's alarms change; `authorization` whenever the
    /// authorization does.
    func startObserving(
        alarms: @escaping @MainActor ([SystemAlarm]) -> Void,
        authorization: @escaping @MainActor (AlarmAuthorization) -> Void)

    /// The system refused to schedule more alarms.
    func isLimitReached(_ error: Error) -> Bool
}
