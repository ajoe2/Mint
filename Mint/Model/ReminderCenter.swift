//
//  ReminderCenter.swift
//  Mint
//
//  Created by Andy Joe on 10/3/26.
//

import AppKit
import os
import SwiftData
import UserNotifications

/// Sends reminders as notifications. Clicking one opens its entry; its button marks the entry paid.
@Observable
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorization = UNAuthorizationStatus.notDetermined

    /// True when notifications for Mint are turned off in System Settings.
    var isTurnedOff: Bool { authorization == .denied }

    private let container: ModelContainer
    private let app: AppModel
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.ajoe.Mint", category: "Reminders")

    /// Stays under the system's limit of 64 scheduled notifications per app.
    private static let maximumScheduled = 60
    private nonisolated static let completeAction = "complete"
    private nonisolated static let entryKey = "entry"

    /// Create before the app finishes launching, so a notification that launched it gets handled.
    init(container: ModelContainer, app: AppModel) {
        self.container = container
        self.app = app
        super.init()
        center.delegate = self
        center.setNotificationCategories(Set(EntryKind.allCases.map { kind in
            UNNotificationCategory(
                identifier: Self.category(for: kind),
                actions: [UNNotificationAction(identifier: Self.completeAction, title: "Mark \(kind.completedLabel)", options: [])],
                intentIdentifiers: []
            )
        }))
    }

    /// Replaces all scheduled reminders with the future ones in `plan`, and clears delivered ones
    /// no longer in it (e.g. for a bill since paid). Asks for permission the first time there's
    /// something to schedule.
    func schedule(_ plan: [Reminder]) async {
        let planned = Set(plan.map(\.id))
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { !planned.contains($0) })
        center.removeAllPendingNotificationRequests()

        let now = Date.now
        let upcoming = plan.filter { $0.date > now }.prefix(Self.maximumScheduled)
        guard !upcoming.isEmpty, await isAllowed(), !Task.isCancelled else { return }
        for reminder in upcoming {
            do {
                try await center.add(request(for: reminder))
            } catch {
                logger.error("Couldn't schedule a reminder: \(error.localizedDescription)")
            }
            // Stop if a newer plan has replaced this one.
            if Task.isCancelled { return }
        }
        logger.debug("Scheduled \(upcoming.count) reminders")
    }

    func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        if status != authorization { authorization = status }
    }

    /// Whether notifications are allowed, asking the first time.
    private func isAllowed() async -> Bool {
        await refreshAuthorization()
        if authorization == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.error("Couldn't ask to send notifications: \(error.localizedDescription)")
            }
            await refreshAuthorization()
        }
        return authorization == .authorized || authorization == .provisional
    }

    private func request(for reminder: Reminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        if let key = reminder.entryKey, let kind = reminder.kind {
            content.userInfo = [Self.entryKey: key]
            content.categoryIdentifier = Self.category(for: kind)
            content.threadIdentifier = "due"
        } else {
            content.threadIdentifier = "balance"
        }
        let time = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        return UNNotificationRequest(
            identifier: reminder.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: false)
        )
    }

    /// One category per kind, so the button can say Mark Paid, Mark Received, or Mark Invested.
    private static func category(for kind: EntryKind) -> String {
        "entry.\(kind.rawValue)"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows reminders even while Mint is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let key = response.notification.request.content.userInfo[Self.entryKey] as? String
        await respond(to: response.actionIdentifier, entryKey: key)
    }

    private func respond(to action: String, entryKey: String?) {
        let entry = entryKey.flatMap(entry(forKey:))
        switch action {
        case Self.completeAction:
            // Skip if it was paid in the app after the notification arrived.
            guard let entry, entry.date == nil else { return }
            entry.date = Calendar.current.startOfDay(for: .now)
            container.mainContext.undoManager?.setActionName(EntryActions.completeTitle(for: entry.kind))
            container.mainContext.saveNow()
        case UNNotificationDefaultActionIdentifier:
            NSApp.activate()
            guard app.isBrowsing else { return }
            if let entry {
                app.editor = .edit(entry)
            } else {
                app.selection = .overview
            }
        default:
            break
        }
    }

    /// The entry a reminder points to, or `nil` if it's since been deleted.
    private func entry(forKey key: String) -> Entry? {
        guard let id = Reminder.entryID(forKey: key) else { return nil }
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }
}
