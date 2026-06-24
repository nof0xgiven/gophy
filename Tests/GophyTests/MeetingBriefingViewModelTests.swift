import XCTest
@testable import Gophy

@MainActor
final class MeetingBriefingViewModelTests: XCTestCase {
    private var tempDirectory: URL!
    private var storageManager: StorageManager!
    private var database: GophyDatabase!
    private var meetingRepository: MeetingRepository!
    private var documentRepository: DocumentRepository!
    private var chatMessageRepository: ChatMessageRepository!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyBriefingTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        meetingRepository = MeetingRepository(database: database)
        documentRepository = DocumentRepository(database: database)
        chatMessageRepository = ChatMessageRepository(database: database)
    }

    override func tearDown() async throws {
        database = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testEventKitEventDoesNotMatchManualMeetingsWithNilCalendarEventId() async throws {
        try await meetingRepository.create(makeMeeting(
            id: "manual-meeting",
            title: "Manual Capture",
            startedAt: Date().addingTimeInterval(-3600),
            calendarEventId: nil
        ))

        let viewModel = makeViewModel(event: UnifiedCalendarEvent(
            id: "eventkit-event",
            title: "Budget Review",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            location: nil,
            isAllDay: false,
            meetingLink: nil,
            attendees: [],
            source: .eventKit,
            googleEventId: nil,
            calendarId: nil
        ))

        await viewModel.loadBriefing()

        XCTAssertEqual(viewModel.pastMeetings.map(\.id), [])
    }

    func testBriefingKeepsNewestMeetingOrderWhenDeduplicatingMatches() async throws {
        let now = Date()
        try await meetingRepository.create(makeMeeting(
            id: "oldest",
            title: "Roadmap Sync",
            startedAt: now.addingTimeInterval(-4000),
            calendarEventId: "calendar-event"
        ))
        try await meetingRepository.create(makeMeeting(
            id: "newest",
            title: "Roadmap Sync",
            startedAt: now.addingTimeInterval(-1000),
            calendarEventId: "calendar-event"
        ))
        try await meetingRepository.create(makeMeeting(
            id: "middle",
            title: "Roadmap Sync",
            startedAt: now.addingTimeInterval(-2000),
            calendarEventId: nil
        ))
        try await meetingRepository.create(makeMeeting(
            id: "older",
            title: "Roadmap Sync",
            startedAt: now.addingTimeInterval(-3000),
            calendarEventId: nil
        ))

        let viewModel = makeViewModel(event: UnifiedCalendarEvent(
            id: "calendar-event",
            title: "Roadmap Sync",
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            location: nil,
            isAllDay: false,
            meetingLink: nil,
            attendees: [],
            source: .google,
            googleEventId: "calendar-event",
            calendarId: nil
        ))

        await viewModel.loadBriefing()

        XCTAssertEqual(viewModel.pastMeetings.map(\.id), ["newest", "middle", "older"])
    }

    private func makeViewModel(event: UnifiedCalendarEvent) -> MeetingBriefingViewModel {
        MeetingBriefingViewModel(
            event: event,
            meetingRepository: meetingRepository,
            documentRepository: documentRepository,
            chatMessageRepository: chatMessageRepository
        )
    }

    private func makeMeeting(
        id: String,
        title: String,
        startedAt: Date,
        calendarEventId: String?
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1800),
            mode: "meeting",
            status: "completed",
            createdAt: startedAt,
            calendarEventId: calendarEventId
        )
    }
}
