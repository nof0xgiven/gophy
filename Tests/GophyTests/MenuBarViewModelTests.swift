import XCTest
import Foundation
@testable import Gophy

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    private var tempDirectory: URL!
    private var storageManager: StorageManager!
    private var database: GophyDatabase!
    private var meetingRepository: MeetingRepository!
    private var chatMessageRepository: ChatMessageRepository!
    private var appDependencies: AppDependencies!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyMenuBarViewModelTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        meetingRepository = MeetingRepository(database: database)
        chatMessageRepository = ChatMessageRepository(database: database)
        appDependencies = AppDependencies(storageManager: storageManager)
    }

    override func tearDown() async throws {
        appDependencies = nil
        chatMessageRepository = nil
        meetingRepository = nil
        database = nil
        storageManager = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testRefreshClearsLastMeetingAfterMeetingIsDeleted() async throws {
        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Deleted Meeting",
            startedAt: Date(),
            endedAt: Date(),
            mode: "meeting",
            status: "completed",
            createdAt: Date()
        )
        try await meetingRepository.create(meeting)
        try await chatMessageRepository.create(ChatMessageRecord(
            id: UUID().uuidString,
            role: "assistant",
            content: "This summary should disappear.",
            meetingId: meetingId,
            createdAt: Date()
        ))

        let viewModel = MenuBarViewModel(appDependencies: appDependencies)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.lastMeetingTitle, "Deleted Meeting")
        XCTAssertEqual(viewModel.lastMeetingSummary, "This summary should disappear.")
        XCTAssertNotNil(viewModel.lastMeetingDate)

        try await meetingRepository.delete(id: meetingId)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.lastMeetingTitle, "")
        XCTAssertEqual(viewModel.lastMeetingSummary, "")
        XCTAssertNil(viewModel.lastMeetingDate)
    }
}
