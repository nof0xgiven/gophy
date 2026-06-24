import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "MenuBarVM")

@MainActor
@Observable
public final class MenuBarViewModel {
    var isRecording: Bool = false
    var recordingTitle: String = ""
    var recordingDuration: TimeInterval = 0
    var upcomingEvents: [UnifiedCalendarEvent] = []
    var lastMeetingTitle: String = ""
    var lastMeetingSummary: String = ""
    var lastMeetingDate: Date?

    private var calendarSyncService: CalendarSyncService?
    private var streamTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let appDependencies: AppDependencies

    init(appDependencies: AppDependencies = .shared) {
        self.appDependencies = appDependencies
    }

    func start() {
        if pollTask == nil {
            startPolling()
        }
        Task { await refresh() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        streamTask?.cancel()
        streamTask = nil
    }

    func refresh() async {
        await loadUpcomingEvents()
        await loadLastMeetingSummary()
    }

    var statusIcon: String {
        isRecording ? "record.circle.fill" : "phone.circle.fill"
    }

    var statusIconColor: Color {
        isRecording ? .red : .accentColor
    }

    var statusText: String {
        if isRecording {
            let title = recordingTitle.isEmpty ? "Recording" : recordingTitle
            return "\(title) \(formatDuration(recordingDuration))"
        }
        return "Not Recording"
    }

    func startInstantMeeting(navigationCoordinator: NavigationCoordinator) {
        navigationCoordinator.requestAutoStart(title: "Instant Meeting", calendarEventId: nil)
        activateApp()
    }

    func startMeetingForEvent(_ event: UnifiedCalendarEvent, navigationCoordinator: NavigationCoordinator) {
        navigationCoordinator.requestAutoStart(
            title: event.title,
            calendarEventId: event.googleEventId ?? event.id
        )
        activateApp()
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateRecordingState()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func updateRecordingState() async {
        let tracking = MeetingStateTracker.shared
        isRecording = tracking.status == .active || tracking.status == .paused
        recordingTitle = tracking.currentMeetingTitle
        recordingDuration = tracking.duration
    }

    private func loadUpcomingEvents() async {
        let config = GoogleCalendarConfig()
        guard config.isConfigured else {
            await loadEventKitEvents()
            return
        }

        let authService = GoogleAuthService(config: config)
        guard await authService.isSignedIn else {
            await loadEventKitEvents()
            return
        }

        do {
            let apiClient = GoogleCalendarAPIClient(authService: authService)
            let eventKit = EventKitService()
            let syncService = CalendarSyncService(apiClient: apiClient, eventKitService: eventKit)
            self.calendarSyncService = syncService
            let events = try await syncService.syncNow()
            filterUpcoming(events)
        } catch {
            logger.warning("Failed to load calendar events: \(error.localizedDescription, privacy: .public)")
            await loadEventKitEvents()
        }
    }

    private func loadEventKitEvents() async {
        let eventKit = EventKitService()
        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 3600)
        let localEvents = eventKit.fetchUpcomingEvents(from: now, to: tomorrow, calendars: nil)
        let events = localEvents.map { e in
            UnifiedCalendarEvent(
                id: e.identifier,
                title: e.title,
                startDate: e.startDate,
                endDate: e.endDate,
                location: e.location,
                isAllDay: e.isAllDay,
                meetingLink: e.url?.absoluteString,
                attendees: [],
                source: .eventKit,
                googleEventId: nil,
                calendarId: nil
            )
        }
        filterUpcoming(events)
    }

    private func filterUpcoming(_ events: [UnifiedCalendarEvent]) {
        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 3600)
        upcomingEvents = events
            .filter { !$0.isAllDay && $0.endDate > now && $0.startDate < tomorrow }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { $0 }
    }

    private func loadLastMeetingSummary() async {
        do {
            let db = try appDependencies.database()
            let meetingRepo = MeetingRepository(database: db)
            let chatRepo = ChatMessageRepository(database: db)
            let meetings = try await meetingRepo.listAll(limit: 1, offset: 0)
            guard let last = meetings.first else {
                clearLastMeeting()
                return
            }
            lastMeetingTitle = last.title
            lastMeetingDate = last.startedAt
            lastMeetingSummary = ""
            let messages = try await chatRepo.listForMeeting(meetingId: last.id)
            if let firstSuggestion = messages.first(where: { $0.role == "assistant" }) {
                lastMeetingSummary = firstSuggestion.content
            }
        } catch {
            logger.warning("Failed to load last meeting: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearLastMeeting() {
        lastMeetingTitle = ""
        lastMeetingSummary = ""
        lastMeetingDate = nil
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
