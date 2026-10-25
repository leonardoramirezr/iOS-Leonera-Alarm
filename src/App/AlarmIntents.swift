import AppIntents

/// Runs when the alarm is stopped from the system UI. Stopping is allowed (iOS
/// always offers it), but unless the challenge was completed the alarm comes back.
/// Only AlarmKit alarms (iOS 26 or later) have intents; on iOS 18 to 25
/// `NotificationAlarmBackend` handles the notification's actions instead.
@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Detener alarma"
    static let isDiscoverable = false

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await AlarmController.shared.alarmStoppedFromSystemUI()
        return .result()
    }
}

/// The alarm's only extra button: opens the app straight into the challenge.
@available(iOS 26.0, *)
struct OpenChallengeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resolver reto"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AlarmController.shared.openChallengeFromAlarm()
        return .result()
    }
}
