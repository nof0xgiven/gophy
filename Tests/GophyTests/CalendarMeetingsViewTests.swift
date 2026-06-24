import XCTest
@testable import Gophy

@MainActor
final class CalendarMeetingsViewTests: XCTestCase {
    func testPendingAutoStartCanPresentBeforeCalendarViewModelLoads() {
        let request = AutoStartRequest(title: "Instant Meeting", calendarEventId: nil)

        let destination = CalendarMeetingsView.initialSheetDestination(for: request)

        XCTAssertEqual(destination?.id, "new-event")
    }
}
