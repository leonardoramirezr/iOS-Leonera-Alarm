import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

@available(iOS 26.0, *)
struct VigiliaAlarmMetadata: AlarmMetadata {
    var kind: String
}

/// iOS 26 or later: the alarms are AlarmKit alarms. They ring with the iPhone on
/// silent, in a Focus, with the app closed and after a restart.
@available(iOS 26.0, *)
@MainActor
final class AlarmKitBackend: AlarmBackend {
    private let manager = AlarmManager.shared

    var authorization: AlarmAuthorization {
        Self.map(manager.authorizationState)
    }

    func updateAuthorization() async -> AlarmAuthorization {
        authorization
    }

    func requestAuthorization() async -> AlarmAuthorization {
        Self.map((try? await manager.requestAuthorization()) ?? .denied)
    }

    func alarms() throws -> [SystemAlarm] {
        try manager.alarms.map { SystemAlarm(id: $0.id, isAlerting: $0.state == .alerting) }
    }

    /// AlarmKit answers synchronously: nothing to refresh.
    func refresh() async {}

    func schedule(id: UUID, kind: AlarmKind, schedule: AlarmSchedule, sound: String?) async throws {
        let attributes = AlarmAttributes<VigiliaAlarmMetadata>(
            presentation: AlarmPresentation(alert: Self.alert(for: kind)),
            metadata: VigiliaAlarmMetadata(kind: kind.rawValue),
            tintColor: Color(red: 0.95, green: 0.45, blue: 0.2))
        let alertSound: AlertConfiguration.AlertSound
        if let sound {
            alertSound = .named(sound)
        } else {
            alertSound = .default
        }
        let configuration = AlarmManager.AlarmConfiguration<VigiliaAlarmMetadata>.alarm(
            schedule: Self.alarmSchedule(schedule),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: OpenChallengeIntent(alarmID: id.uuidString),
            sound: alertSound)
        _ = try await manager.schedule(id: id, configuration: configuration)
    }

    func cancel(id: UUID) {
        try? manager.cancel(id: id)
    }

    func stop(id: UUID) {
        try? manager.stop(id: id)
    }

    func startObserving(
        alarms: @escaping @MainActor ([SystemAlarm]) -> Void,
        authorization: @escaping @MainActor (AlarmAuthorization) -> Void
    ) {
        Task {
            for await updated in manager.alarmUpdates {
                alarms(updated.map { SystemAlarm(id: $0.id, isAlerting: $0.state == .alerting) })
            }
        }
        Task {
            for await state in manager.authorizationUpdates {
                authorization(Self.map(state))
            }
        }
    }

    func isLimitReached(_ error: Error) -> Bool {
        (error as? AlarmManager.AlarmError) == .maximumLimitReached
    }

    // MARK: - Helpers

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private static func alarmSchedule(_ schedule: AlarmSchedule) -> Alarm.Schedule {
        switch schedule {
        case .fixed(let date):
            return .fixed(date)
        case .weekly(let weekday, let time):
            return .relative(.init(
                time: .init(hour: time.hour, minute: time.minute),
                repeats: .weekly([localeWeekday(weekday)])))
        }
    }

    /// No snooze button: the only extra action opens the challenge.
    private static func alert(for kind: AlarmKind) -> AlarmPresentation.Alert {
        let title: LocalizedStringResource
        switch kind {
        case .main: title = "¡Despierta! Haz el reto"
        case .retry: title = "Sigue sonando: haz el reto"
        case .test: title = "Prueba de Vigilia"
        }
        let challengeButton = AlarmButton(text: "Resolver reto", textColor: .white, systemImageName: "brain.head.profile")
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title, secondaryButton: challengeButton, secondaryButtonBehavior: .custom)
        } else {
            return AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Detener", textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: challengeButton,
                secondaryButtonBehavior: .custom)
        }
    }

    private static func localeWeekday(_ weekday: Int) -> Locale.Weekday {
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }
}
