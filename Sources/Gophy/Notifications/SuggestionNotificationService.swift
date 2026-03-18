import Foundation
import UserNotifications
import AppKit
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "SuggestionNotifications")
private let suggestionCategoryId = "MEETING_SUGGESTION"

@MainActor
final class SuggestionNotificationService: NSObject, @unchecked Sendable {
    static let shared = SuggestionNotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func setup() {
        notificationCenter.delegate = self
    }

    func requestPermission() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self?.notificationCenter.requestAuthorization(options: [.alert]) { granted, error in
                if let error = error {
                    logger.warning("Notification permission error: \(error.localizedDescription, privacy: .public)")
                }
                logger.info("Notification permission granted: \(granted)")
            }
        }
    }

    func sendSuggestion(_ text: String, meetingTitle: String) {
        guard !NSApplication.shared.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = meetingTitle
        content.body = text.count > 200 ? String(text.prefix(197)) + "..." : text
        content.categoryIdentifier = suggestionCategoryId

        let request = UNNotificationRequest(
            identifier: "suggestion-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error = error {
                logger.warning("Failed to send suggestion notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension SuggestionNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let categoryId = notification.request.content.categoryIdentifier

        // Suppress suggestion notifications when app is in foreground (they show in-panel)
        if categoryId == suggestionCategoryId {
            return []
        }

        // Allow auto-start notifications through
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Bring app to foreground when user taps notification
        await MainActor.run {
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
