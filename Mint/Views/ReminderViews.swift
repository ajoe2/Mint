//
//  ReminderViews.swift
//  Mint
//
//  Created by Andy Joe on 10/3/26.
//

import AppKit
import SwiftUI

/// The reminder settings stored in UserDefaults.
struct ReminderPreferences: DynamicProperty {
    @AppStorage(SettingsKey.dueDateReminders) var dueDates = ReminderSettings.standard.dueDates
    @AppStorage(SettingsKey.lowBalanceReminders) var lowBalance = ReminderSettings.standard.lowBalance
    @AppStorage(SettingsKey.lowBalanceLimit) var limitCents = ReminderSettings.standard.limitCents
    @AppStorage(SettingsKey.reminderDaysBefore) var daysBefore = ReminderSettings.standard.daysBefore
    @AppStorage(SettingsKey.reminderTime) var minuteOfDay = ReminderSettings.standard.minuteOfDay

    var settings: ReminderSettings {
        ReminderSettings(dueDates: dueDates, lowBalance: lowBalance, limitCents: limitCents, daysBefore: daysBefore, minuteOfDay: minuteOfDay)
    }
}

extension View {
    /// Keeps scheduled reminders in step with the entries and reminder settings.
    func schedulesReminders(for entries: [Entry], ledger: Ledger) -> some View {
        modifier(ReminderScheduling(entries: entries, ledger: ledger))
    }
}

private struct ReminderScheduling: ViewModifier {
    let entries: [Entry]
    let ledger: Ledger

    /// `nil` in tests and demo mode, which never send reminders.
    @Environment(ReminderCenter.self) private var center: ReminderCenter?
    private let preferences = ReminderPreferences()

    /// What the schedule depends on; a change reschedules.
    private struct Inputs: Equatable {
        var plan: [Reminder]
        var isTurnedOff: Bool
    }

    func body(content: Content) -> some View {
        let plan = center == nil ? [] : ReminderPlanner.plan(entries: entries, ledger: ledger, settings: preferences.settings)
        content
            // Also reruns when notifications are turned on or off in System Settings.
            .task(id: Inputs(plan: plan, isTurnedOff: center?.isTurnedOff == true)) {
                await center?.schedule(plan)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await center?.refreshAuthorization() }
            }
    }
}

/// The Reminders section of Settings.
struct ReminderSettingsSection: View {
    @Environment(ReminderCenter.self) private var center: ReminderCenter?
    private let preferences = ReminderPreferences()

    var body: some View {
        Section {
            Toggle(isOn: preferences.$dueDates) {
                Text("Due dates")
                Text("Before something unpaid is due, and again if it's overdue.")
            }
            Toggle(isOn: preferences.$lowBalance) {
                Text("Low balance")
                Text("Before your balance is expected to drop below the limit.")
            }
            LabeledContent {
                AmountSettingField(cents: preferences.$limitCents)
            } label: {
                Text("Limit")
                Text("The Overview warns you below this, too.")
            }
            LabeledContent("Remind me") {
                HStack(spacing: 8) {
                    Picker("Remind me", selection: preferences.$daysBefore) {
                        ForEach(ReminderSettings.leadTimes, id: \.self) { days in
                            Text(ReminderSettings.title(forDaysBefore: days)).tag(days)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("at")
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            .disabled(!preferences.dueDates && !preferences.lowBalance)
        } header: {
            Text("Reminders")
        } footer: {
            if center?.isTurnedOff == true && (preferences.dueDates || preferences.lowBalance) {
                Text("Notifications are turned off for Mint. To get reminders, turn them on in System Settings ▸ Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await center?.refreshAuthorization() }
        // Notifications may have just been turned on or off in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await center?.refreshAuthorization() }
        }
    }

    /// The reminder time as a date today, for the time picker.
    private var time: Binding<Date> {
        Binding {
            let minute = preferences.minuteOfDay
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            preferences.minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// An amount in Settings. Saves on Return or when you leave the field; anything that isn't an
/// amount reverts.
private struct AmountSettingField: View {
    @Binding var cents: Int
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Amount", text: $text, prompt: Text(Money.format(0)))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 110)
            .focused($isFocused)
            .onSubmit(save)
            .onChange(of: isFocused) {
                if !isFocused { save() }
            }
            .onChange(of: cents, initial: true) {
                if !isFocused { text = Money.format(cents) }
            }
            .onDisappear(perform: save)
    }

    private func save() {
        if let parsed = Money.parseCents(text) {
            cents = parsed
        }
        text = Money.format(cents)
    }
}
