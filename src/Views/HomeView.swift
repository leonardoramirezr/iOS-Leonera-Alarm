import AlarmKit
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var controller: AlarmController
    @EnvironmentObject private var player: AlarmAudioPlayer

    var body: some View {
        NavigationStack {
            Form {
                if controller.authorization != .authorized {
                    permissionSection
                }
                alarmSection
                upcomingSection
                testSection
                volumeSection
                if let expiration = ProvisioningInfo.expirationDate {
                    signingSection(expiration)
                }
                statsSection
                if !controller.state.history.isEmpty {
                    historySection
                }
                howItWorksSection
                buildSection
            }
            .navigationTitle("Vigilia")
            .alert("Vigilia", isPresented: noticeIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.notice ?? "")
            }
        }
        .tint(.orange)
    }

    // MARK: Sections

    private var permissionSection: some View {
        Section {
            if controller.authorization == .denied {
                Label("Vigilia no tiene permiso para programar alarmas.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Text("Vigilia necesita permiso para crear alarmas que suenen aunque el iPhone esté en silencio o en modo Concentración.")
                Button("Permitir alarmas") {
                    Task { _ = await controller.ensureAuthorized() }
                }
            }
        }
    }

    private var alarmSection: some View {
        let settings = controller.state.settings
        let isEditable = !controller.isSettingsLocked && !controller.isAlarmRinging
        return Section {
            Toggle(isOn: enabledBinding) {
                Label("Alarma activada", systemImage: "alarm.fill")
            }
            .disabled(!isEditable)
            WeekdayPicker(selection: weekdaysBinding)
                .disabled(!isEditable)
            Toggle("Misma hora todos los días", isOn: sameTimeBinding)
                .disabled(!isEditable)
            if settings.sameTimeEveryDay {
                DatePicker("Hora", selection: timeBinding(for: nil), displayedComponents: .hourAndMinute)
                    .disabled(!isEditable)
            } else {
                ForEach(WeekdayPicker.orderedDays.filter { settings.weekdays.contains($0) }, id: \.self) { day in
                    DatePicker(WeekdayPicker.names[day - 1].capitalized, selection: timeBinding(for: day), displayedComponents: .hourAndMinute)
                        .disabled(!isEditable)
                }
            }
            Toggle(isOn: nextAlarmBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Cambiar siguiente alarma", systemImage: "calendar.badge.clock")
                    Text(nextAlarmDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!isEditable || !settings.isEnabled)
            if let override = controller.dayOverride {
                DatePicker("Hora del \(override.formatted(.dateTime.weekday(.wide).day()))",
                           selection: dayOverrideTimeBinding, displayedComponents: .hourAndMinute)
                    .disabled(!isEditable)
            }
            DifficultyPicker(selection: difficultyBinding)
                .disabled(!isEditable)
            DurationPicker(selection: durationBinding)
                .disabled(!isEditable)
            Toggle(isOn: locksSettingsBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Bloquear cambios", systemImage: "lock.fill")
                    Text(settings.locksSettings
                         ? "Unos minutos después de activar la alarma se bloquea: cambiarla o apagarla requiere el reto mental."
                         : "La alarma nunca se bloquea: puedes cambiarla o apagarla cuando quieras sin hacer el reto.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!isEditable)
            if controller.isAlarmRinging {
                Label("La alarma está sonando: no se puede cambiar hasta que completes el reto.", systemImage: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(.orange)
            } else if controller.isSettingsLocked {
                Button {
                    controller.requestUnlock()
                } label: {
                    Label("Desbloquear con el reto de \(ChallengeDuration.settingsUnlock.text)", systemImage: "lock.fill")
                }
            } else if settings.isEnabled, settings.locksSettings, let until = controller.state.settingsUnlockedUntil, until > controller.now {
                Label("Desbloqueada hasta las \(until.formatted(date: .omitted, time: .shortened))", systemImage: "lock.open.fill")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Alarma")
        } footer: {
            if settings.locksSettings {
                Text(settings.isEnabled
                     ? "Mientras esté activada, para cambiarla o apagarla tienes que completar el reto mental."
                     : "Al activarla tendrás 5 minutos para ajustarla; después queda bloqueada y cambiarla o apagarla requiere el reto mental.")
            }
        }
    }

    private var upcomingSection: some View {
        Section {
            if let next = controller.nextOccurrence {
                LabeledContent("Suena") {
                    Text(next.formatted(.dateTime.weekday(.wide).hour().minute()))
                }
                LabeledContent("Falta") {
                    Text(next, style: .relative)
                }
                if let sound = controller.soundInfo(for: next) {
                    LabeledContent("Sonido de ese día", value: sound.title)
                    previewButton(for: sound)
                }
                if controller.earlyDismissibleOccurrence != nil {
                    Button {
                        controller.requestEarlyDismissal()
                    } label: {
                        Label("Desactivarla con el reto de \(controller.state.settings.challengeDuration.text)", systemImage: "moon.zzz.fill")
                    }
                }
            } else {
                Text("No hay ninguna alarma programada.")
                    .foregroundStyle(.secondary)
            }
            if let dismissed = controller.dismissedOccurrence {
                LabeledContent("Desactivada") {
                    Text(dismissed.formatted(.dateTime.weekday(.wide).hour().minute()))
                }
            }
        } header: {
            Text("Próxima alarma")
        } footer: {
            Text("Desde 3 horas antes puedes desactivarla resolviendo el mismo reto que harías al sonar; solo se desactiva esa vez. Hay \(controller.sounds.sounds.count) sonidos y cada día suena uno distinto; no se repite ninguno hasta haberlos usado todos.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                controller.scheduleTest()
            } label: {
                Label("Probar: sonará en 1 minuto", systemImage: "bell.badge.fill")
            }
            .disabled(controller.authorization == .denied)
            if let test = controller.state.test, test.occurrence > controller.now {
                LabeledContent("Prueba programada") {
                    Text(test.occurrence, style: .relative)
                }
            }
        } footer: {
            Text("La prueba funciona igual que la alarma real: no se puede posponer y vuelve a sonar hasta que completes el reto.")
        }
    }

    /// AlarmKit plays at the volume iOS gives alarms and no app can raise it, so this
    /// only explains which settings keep it loud.
    private var volumeSection: some View {
        let isIOS27 = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Con el iPhone bloqueado la alarma suena al volumen de tono y alertas de iOS, y ninguna app puede subirlo. Si «Cambiar con botones» está activado, bajar el volumen con los botones también lo baja y la alarma puede sonar muy quedito o solo vibrar.")
                Text("En Ajustes › Sonidos y vibración:")
                Text("• Desactiva «Cambiar con botones».")
                Text("• Sube al máximo el volumen de tono y alertas.")
                if isIOS27 {
                    Text("• Si en «Alarmas y temporizadores» les diste su propio volumen, súbelo también al máximo.")
                }
            }
            .font(.callout)
            .padding(.vertical, 4)
        } header: {
            Text("Volumen de la alarma")
        } footer: {
            Text("Compruébalo con «Probar» y el iPhone bloqueado. Dentro de la app, si durante el reto te quedas 15 s sin acertar (25 s con 3 dígitos), la alarma vuelve a sonar a todo volumen en la bocina del iPhone aunque lo hayas bajado (con audífonos, al volumen que tengas).")
        }
    }

    private func signingSection(_ expiration: Date) -> some View {
        Section {
            LabeledContent("Vence") {
                Text(expiration.formatted(date: .abbreviated, time: .shortened))
            }
            if expiration < controller.now.addingTimeInterval(2 * 24 * 3600) {
                Label("Refresca o reinstala la app antes de que venza: si vence no abrirá y no podrás completar el reto.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Firma de la app")
        } footer: {
            Text("Con una cuenta gratuita de Apple la firma dura 7 días.")
        }
    }

    private var statsSection: some View {
        let week = WakeStatistics.samples(from: controller.state.history, period: .week, now: controller.now, calendar: .current)
        let average = WakeStatistics.summary(of: week, .offTime)?.average
        return Section {
            NavigationLink {
                StatsView()
            } label: {
                LabeledContent {
                    if let average {
                        Text(Clock.text(average))
                    }
                } label: {
                    Label("Estadísticas", systemImage: "chart.xyaxis.line")
                }
            }
        } footer: {
            if average != nil {
                Text("Hora promedio a la que apagaste la alarma en los últimos 7 días.")
            }
        }
    }

    private var historySection: some View {
        Section("Últimos despertares") {
            ForEach(controller.state.history.prefix(7)) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.occurrence.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))\(record.isTest ? " · prueba" : "")")
                    Text("Apagada \(minutesLate(record)) después · \(record.solved) aciertos, \(record.mistakes) errores")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let sound = record.sound {
                        Label(sound, systemImage: "music.note")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var howItWorksSection: some View {
        Section {
            DisclosureGroup("Cómo funciona") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("• Cada día suena un sonido distinto para que no te acostumbres.")
                    Text("• No existe posponer. Si la detienes desde la pantalla bloqueada o con los botones, vuelve a sonar cada minuto y luego más espaciado durante una hora.")
                    Text("• Para apagarla de verdad abre Vigilia (botón «Resolver reto») y haz el reto de cálculo mental. El tiempo solo avanza mientras respondes bien y cada error resta 5 segundos.")
                    Text("• Eliges la dificultad del reto (operaciones con números de 1, 2 o 3 dígitos) y cuánto dura: de 15 segundos a 10 minutos.")
                    Text("• Con «Cambiar siguiente alarma» eliges otra hora solo para la próxima alarma; ese día suena solo a esa hora y los demás días siguen igual.")
                    Text("• Desde 3 horas antes de que suene puedes desactivar esa alarma haciendo el mismo reto desde la app. Solo se salta esa vez; las siguientes suenan como siempre.")
                    Text("• Si durante el reto te quedas 15 s sin acertar (25 s con 3 dígitos), la alarma vuelve a sonar dentro de la app hasta tu siguiente respuesta correcta, a todo volumen en la bocina del iPhone aunque lo hayas bajado.")
                    Text("• Si sales de la app durante el reto, empieza de nuevo; si la cierras, la alarma vuelve a sonar en poco más de un minuto.")
                    Text("• Las alarmas viven en iOS (AlarmKit): suenan aunque cierres la app, reinicies el iPhone o esté en silencio o en Concentración.")
                }
                .font(.callout)
                .padding(.vertical, 4)
            }
        }
    }

    private var buildSection: some View {
        Section {
            LabeledContent("Build", value: BuildInfo.name)
        }
    }

    // MARK: Helpers

    private func previewButton(for sound: SoundInfo) -> some View {
        let playing = player.playingFile == sound.file
        return Button {
            if playing {
                player.stop()
            } else {
                player.play(sound.file)
            }
        } label: {
            Label(playing ? "Detener" : "Escuchar", systemImage: playing ? "stop.circle.fill" : "play.circle.fill")
        }
    }

    private func minutesLate(_ record: WakeRecord) -> String {
        let minutes = max(0, Int(record.completedAt.timeIntervalSince(record.occurrence) / 60))
        return minutes == 1 ? "1 minuto" : "\(minutes) minutos"
    }

    private var nextAlarmDescription: String {
        if let override = controller.dayOverride {
            return "El \(override.formatted(.dateTime.weekday(.wide).day())) suena solo a esta hora; los demás días siguen igual."
        }
        guard let next = controller.nextOccurrence else {
            return "Cambia la hora solo de la próxima alarma."
        }
        let day = next.formatted(.dateTime.weekday(.wide).day())
        let time = next.formatted(date: .omitted, time: .shortened)
        return "La próxima suena el \(day) a las \(time). Cambia la hora solo esa vez."
    }

    private var noticeIsPresented: Binding<Bool> {
        Binding(
            get: { controller.notice != nil },
            set: { if !$0 { controller.notice = nil } })
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.state.settings.isEnabled },
            set: { controller.setEnabled($0) })
    }

    private var locksSettingsBinding: Binding<Bool> {
        Binding(
            get: { controller.state.settings.locksSettings },
            set: { controller.setLocksSettings($0) })
    }

    private var nextAlarmBinding: Binding<Bool> {
        Binding(
            get: { controller.dayOverride != nil },
            set: { controller.setNextAlarmOverride($0) })
    }

    private var dayOverrideTimeBinding: Binding<Date> {
        Binding(
            get: { controller.dayOverride ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                controller.setDayOverrideTime(AlarmTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0))
            })
    }

    private var sameTimeBinding: Binding<Bool> {
        Binding(
            get: { controller.state.settings.sameTimeEveryDay },
            set: { same in controller.updateSettings { $0.sameTimeEveryDay = same } })
    }

    /// The time of one weekday, or the time shared by every day when `weekday` is nil.
    private func timeBinding(for weekday: Int?) -> Binding<Date> {
        Binding(
            get: {
                let settings = controller.state.settings
                let time = weekday.map { settings.time(on: $0) } ?? settings.defaultTime
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let time = AlarmTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
                controller.updateSettings { settings in
                    if let weekday {
                        settings.dayTimes[weekday] = time
                    } else {
                        settings.hour = time.hour
                        settings.minute = time.minute
                    }
                }
            })
    }

    private var weekdaysBinding: Binding<Set<Int>> {
        Binding(
            get: { controller.state.settings.weekdays },
            set: { days in controller.updateSettings { $0.weekdays = days } })
    }

    private var difficultyBinding: Binding<ChallengeDifficulty> {
        Binding(
            get: { controller.state.settings.difficulty },
            set: { controller.setDifficulty($0) })
    }

    private var durationBinding: Binding<ChallengeDuration> {
        Binding(
            get: { controller.state.settings.challengeDuration },
            set: { controller.setChallengeDuration($0) })
    }
}

struct DurationPicker: View {
    @Binding var selection: ChallengeDuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // Twelve options don't fit in a segmented control, so a menu.
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $selection) {
                ForEach(ChallengeDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            } label: {
                Label("Duración del reto", systemImage: "timer")
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
            .pickerStyle(.menu)
            Text("Tiempo respondiendo bien: el reloj solo corre mientras aciertas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct DifficultyPicker: View {
    @Binding var selection: ChallengeDifficulty
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dificultad del reto", systemImage: "brain.head.profile")
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            Picker("Dificultad del reto", selection: $selection) {
                ForEach(ChallengeDifficulty.allCases) { difficulty in
                    Text(difficulty.title).tag(difficulty)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Operaciones como \(selection.example)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.isEnabled) private var isEnabled

    private static let letters = ["D", "L", "M", "M", "J", "V", "S"]
    static let names = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

    /// Calendar weekdays from Monday to Sunday.
    static let orderedDays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.orderedDays, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    var days = selection
                    if isOn {
                        if days.count > 1 { days.remove(day) }
                    } else {
                        days.insert(day)
                    }
                    selection = days
                } label: {
                    Text(Self.letters[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Circle().fill(isOn ? Color.orange : Color.secondary.opacity(0.15)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Self.names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .padding(.vertical, 4)
    }
}
