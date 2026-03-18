import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "CalendarAutoStartCoordinator")

@MainActor
final class CalendarAutoStartCoordinator {
    private var calendarSyncService: CalendarSyncService?
    private var autoStartService: MeetingAutoStartService?
    private var feedTask: Task<Void, Never>?

    func start(navigationCoordinator: NavigationCoordinator) async {
        let settings = UserDefaultsAutoStartSettings()
        guard settings.autoStartEnabled else {
            logger.info("Calendar auto-start is disabled")
            return
        }

        let config = GoogleCalendarConfig()
        guard config.isConfigured else {
            logger.info("Google Calendar not configured, skipping auto-start")
            return
        }

        let authService = GoogleAuthService(config: config)
        guard await authService.isSignedIn else {
            logger.info("Not signed into Google, skipping auto-start")
            return
        }

        let apiClient = GoogleCalendarAPIClient(authService: authService)
        let eventKitService = EventKitService()
        let syncService = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService
        )
        self.calendarSyncService = syncService

        let bridge = MeetingStarterBridge(navigationCoordinator: navigationCoordinator)
        let notifier = UserNotificationAutoStartNotifier()
        let autoStartService = MeetingAutoStartService(
            meetingStarter: bridge,
            notifier: notifier,
            settings: settings
        )
        self.autoStartService = autoStartService

        let stream = await syncService.eventStream()
        await syncService.start()

        feedTask = Task {
            for await events in stream {
                await autoStartService.evaluateEvents(events)
            }
        }

        logger.info("Calendar auto-start coordinator started")
    }

    func stop() {
        feedTask?.cancel()
        feedTask = nil
        Task {
            await calendarSyncService?.stop()
            await autoStartService?.cancelAll()
        }
    }
}
