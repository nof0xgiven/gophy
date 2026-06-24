import XCTest
@testable import Gophy

@MainActor
final class MeetingStateTrackerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set(false, forKey: "autoShowOverlay")
        await resetTracker()
    }

    override func tearDown() async throws {
        await resetTracker()
        UserDefaults.standard.removeObject(forKey: "autoShowOverlay")
        try await super.tearDown()
    }

    func testTrackerRestartsDurationTimerWhenMeetingResumes() async throws {
        let tracker = MeetingStateTracker.shared
        tracker.startTracking()

        await MeetingEventBroadcaster.shared.broadcast(.statusChange(.active))
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let activeDuration = tracker.duration

        await MeetingEventBroadcaster.shared.broadcast(.statusChange(.paused))
        try await Task.sleep(nanoseconds: 200_000_000)

        await MeetingEventBroadcaster.shared.broadcast(.statusChange(.active))
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertGreaterThan(tracker.duration, activeDuration)
    }

    func testCompactOverlaySeedsCurrentTrackerStateOnStart() async throws {
        let tracker = MeetingStateTracker.shared
        tracker.setMeetingTitle("Design Review")
        tracker.status = .active
        tracker.duration = 42

        let viewModel = CompactOverlayViewModel()
        viewModel.start()

        XCTAssertEqual(viewModel.status, .active)
        XCTAssertEqual(viewModel.meetingTitle, "Design Review")
        XCTAssertEqual(viewModel.duration, 42)

        viewModel.stop()
    }

    private func resetTracker() async {
        let tracker = MeetingStateTracker.shared
        tracker.startTracking()
        await MeetingEventBroadcaster.shared.broadcast(.statusChange(.completed))
        try? await Task.sleep(nanoseconds: 100_000_000)
        tracker.setMeetingTitle("")
        tracker.setMeetingId(nil)
        tracker.status = .idle
        tracker.duration = 0
        tracker.stopTracking()
    }
}
