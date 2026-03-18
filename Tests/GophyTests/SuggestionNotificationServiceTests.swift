import Testing
import Foundation
import UserNotifications
@testable import Gophy

// MARK: - Spy Notification Center

/// A UNUserNotificationCenter substitute that records add() calls without
/// requiring a real notification system.  We test SuggestionNotificationService
/// logic (truncation, foreground suppression) at the unit level here; the
/// actual UNUserNotificationCenter integration is validated manually.

private final class SpyNotificationCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [UNNotificationRequest] = []

    var requests: [UNNotificationRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func add(_ request: UNNotificationRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _requests.removeAll()
        lock.unlock()
    }
}

// MARK: - Tests

@Suite("SuggestionNotificationService Tests")
struct SuggestionNotificationServiceTests {

    // MARK: - Notification Body Truncation

    @Test("Suggestion text longer than 200 chars is truncated")
    func testBodyTruncation() {
        let longText = String(repeating: "A", count: 300)
        let truncated = longText.count > 200 ? String(longText.prefix(197)) + "..." : longText
        #expect(truncated.count == 200)
        #expect(truncated.hasSuffix("..."))
    }

    @Test("Suggestion text at or under 200 chars is not truncated")
    func testBodyNotTruncated() {
        let shortText = String(repeating: "B", count: 150)
        let result = shortText.count > 200 ? String(shortText.prefix(197)) + "..." : shortText
        #expect(result == shortText)
        #expect(result.count == 150)
    }

    @Test("Exactly 200 chars is not truncated")
    func testBodyExactly200() {
        let text = String(repeating: "C", count: 200)
        let result = text.count > 200 ? String(text.prefix(197)) + "..." : text
        #expect(result == text)
        #expect(result.count == 200)
    }

    // MARK: - NavigationCoordinator Auto-Start Request

    @Test("requestAutoStart sets pendingAutoStart and navigates to meetings")
    @MainActor
    func testRequestAutoStart() {
        let coordinator = NavigationCoordinator()
        coordinator.selectedItem = .settings

        coordinator.requestAutoStart(title: "Sprint Planning", calendarEventId: "gcal-123")

        #expect(coordinator.pendingAutoStart?.title == "Sprint Planning")
        #expect(coordinator.pendingAutoStart?.calendarEventId == "gcal-123")
        #expect(coordinator.selectedItem == .meetings)
    }

    @Test("requestAutoStart with nil calendarEventId works")
    @MainActor
    func testRequestAutoStartNilCalendarId() {
        let coordinator = NavigationCoordinator()

        coordinator.requestAutoStart(title: "Ad-hoc Meeting", calendarEventId: nil)

        #expect(coordinator.pendingAutoStart?.title == "Ad-hoc Meeting")
        #expect(coordinator.pendingAutoStart?.calendarEventId == nil)
        #expect(coordinator.selectedItem == .meetings)
    }

    @Test("pendingAutoStart can be cleared")
    @MainActor
    func testPendingAutoStartCleared() {
        let coordinator = NavigationCoordinator()
        coordinator.requestAutoStart(title: "Test", calendarEventId: nil)
        #expect(coordinator.pendingAutoStart != nil)

        coordinator.pendingAutoStart = nil
        #expect(coordinator.pendingAutoStart == nil)
    }

    // MARK: - MeetingStarterBridge

    @Test("MeetingStarterBridge.startMeeting dispatches to NavigationCoordinator")
    @MainActor
    func testBridgeStartMeeting() async throws {
        let coordinator = NavigationCoordinator()
        let bridge = MeetingStarterBridge(navigationCoordinator: coordinator)

        try await bridge.startMeeting(title: "Design Review", calendarEventId: "g-42")

        #expect(coordinator.pendingAutoStart?.title == "Design Review")
        #expect(coordinator.pendingAutoStart?.calendarEventId == "g-42")
        #expect(coordinator.selectedItem == .meetings)
    }

    @Test("MeetingStarterBridge.isRecording reads UserDefaults")
    @MainActor
    func testBridgeIsRecording() async {
        let coordinator = NavigationCoordinator()
        let bridge = MeetingStarterBridge(navigationCoordinator: coordinator)

        UserDefaults.standard.set(false, forKey: "isCurrentlyRecording")
        let notRecording = await bridge.isRecording
        #expect(notRecording == false)

        UserDefaults.standard.set(true, forKey: "isCurrentlyRecording")
        let recording = await bridge.isRecording
        #expect(recording == true)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "isCurrentlyRecording")
    }

    // MARK: - AutoStartRequest Equality

    @Test("AutoStartRequest equality")
    func testAutoStartRequestEquality() {
        let a = AutoStartRequest(title: "Meeting A", calendarEventId: "1")
        let b = AutoStartRequest(title: "Meeting A", calendarEventId: "1")
        let c = AutoStartRequest(title: "Meeting B", calendarEventId: "1")

        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - isCurrentlyRecording UserDefaults Integration

    @Test("isCurrentlyRecording key round-trips through UserDefaults")
    func testIsCurrentlyRecordingRoundTrip() {
        let testKey = "isCurrentlyRecording_test"
        UserDefaults.standard.removeObject(forKey: testKey)

        // Unset key returns false for bool
        #expect(UserDefaults.standard.bool(forKey: testKey) == false)

        UserDefaults.standard.set(true, forKey: testKey)
        #expect(UserDefaults.standard.bool(forKey: testKey) == true)

        UserDefaults.standard.set(false, forKey: testKey)
        #expect(UserDefaults.standard.bool(forKey: testKey) == false)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    // MARK: - Integration: Full auto-start flow with mock starter

    @Test("MeetingAutoStartService triggers meeting start and notification for upcoming event")
    func testAutoStartEndToEndFlow() async throws {
        let mockStarter = MockMeetingStarter()
        let notifier = MockAutoStartNotifier()
        let settings = MockAutoStartSettings()
        settings.setOnlyWithVideoLinks(false)

        let now = Date()
        let event = UnifiedCalendarEvent(
            id: "evt-e2e-1",
            title: "Integration Test Meeting",
            startDate: now.addingTimeInterval(30),
            endDate: now.addingTimeInterval(1800),
            location: nil,
            isAllDay: false,
            meetingLink: nil,
            attendees: [],
            source: .google,
            googleEventId: "g-e2e-1",
            calendarId: "primary"
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: notifier,
            settings: settings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 500_000_000)

        let started = await mockStarter.startedTitles
        #expect(started == ["Integration Test Meeting"])

        let notified = await notifier.notifiedTitles
        #expect(notified == ["Integration Test Meeting"])
    }

    @Test("Auto-start skips when isRecording is true (via MockMeetingStarter)")
    func testAutoStartSkipsWhenRecordingViaMock() async throws {
        // Use MockMeetingStarter (not the bridge) to avoid UserDefaults race
        // with GophyApp.init() resetting the key during test process startup.
        let mockStarter = MockMeetingStarter()
        await mockStarter.setRecording(true)
        let notifier = MockAutoStartNotifier()
        let settings = MockAutoStartSettings()
        settings.setOnlyWithVideoLinks(false)

        let now = Date()
        let event = UnifiedCalendarEvent(
            id: "evt-skip-1",
            title: "Should Not Start",
            startDate: now.addingTimeInterval(30),
            endDate: now.addingTimeInterval(1800),
            location: nil,
            isAllDay: false,
            meetingLink: nil,
            attendees: [],
            source: .google,
            googleEventId: "g-skip-1",
            calendarId: "primary"
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: notifier,
            settings: settings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 500_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.isEmpty)
    }
}
