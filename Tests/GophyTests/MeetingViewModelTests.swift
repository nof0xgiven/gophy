import XCTest
@testable import Gophy

@MainActor
final class MeetingViewModelTests: XCTestCase {
    private var tempDirectory: URL!
    private var storageManager: StorageManager!
    private var database: GophyDatabase!
    private var chatMessageRepository: ChatMessageRepository!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyMeetingViewModelTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        chatMessageRepository = ChatMessageRepository(database: database)
    }

    override func tearDown() async throws {
        database = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testDismissSuggestionPersistsToRepository() async throws {
        let message = try await seedSuggestion(id: "suggestion-1")
        let (viewModel, _) = makeViewModel()
        viewModel.suggestions = [SuggestionDisplayItem(from: message)]

        await viewModel.dismissSuggestion(id: message.id)

        let messages = try await chatMessageRepository.listForMeeting(meetingId: "meeting-1")
        XCTAssertEqual(messages.first?.dismissed, true)
        XCTAssertEqual(viewModel.suggestions.first?.dismissed, true)
    }

    func testSetSuggestionFeedbackPersistsToRepository() async throws {
        let message = try await seedSuggestion(id: "suggestion-1")
        let (viewModel, _) = makeViewModel()
        viewModel.suggestions = [SuggestionDisplayItem(from: message)]

        await viewModel.setSuggestionFeedback(id: message.id, feedback: "helpful")

        let messages = try await chatMessageRepository.listForMeeting(meetingId: "meeting-1")
        XCTAssertEqual(messages.first?.feedback, "helpful")
        XCTAssertEqual(viewModel.suggestions.first?.feedback, "helpful")
    }

    func testRefreshSuggestionsRemovesEmptyStreamPlaceholder() async throws {
        let (viewModel, controller) = makeViewModel()
        controller.currentMeetingId = "meeting-1"
        viewModel.status = .active

        await viewModel.refreshSuggestions()

        XCTAssertTrue(viewModel.suggestions.isEmpty)
    }

    func testCancellationErrorDoesNotCreateUserVisibleError() {
        XCTAssertNil(MeetingViewModel.userVisibleErrorMessage(for: CancellationError()))
    }

    private func seedSuggestion(id: String) async throws -> ChatMessageRecord {
        let meeting = MeetingRecord(
            id: "meeting-1",
            title: "Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "meeting",
            status: "active",
            createdAt: Date()
        )
        try await MeetingRepository(database: database).create(meeting)

        let message = ChatMessageRecord(
            id: id,
            role: "assistant",
            content: "Follow up on the launch risk.",
            meetingId: meeting.id,
            createdAt: Date()
        )
        try await chatMessageRepository.create(message)
        return message
    }

    private func makeViewModel() -> (MeetingViewModel, MeetingSessionController) {
        let meetingRepo = MockMeetingRepoForSuggestion()
        let textGen = MockTextGenerationForSuggestion()
        let vectorSearch = MockVectorSearchForSuggestion()
        let embedding = MockEmbeddingForSuggestion()
        let documentRepo = MockDocumentRepoForSuggestion()
        let suggestionChatRepo = MockChatMessageRepoForSuggestion()
        let suggestionEngine = SuggestionEngine(
            textGenerationEngine: textGen,
            vectorSearchService: vectorSearch,
            embeddingEngine: embedding,
            meetingRepository: meetingRepo,
            documentRepository: documentRepo,
            chatMessageRepository: suggestionChatRepo
        )

        let controller = MeetingSessionController(
            modeController: MockModeController(),
            transcriptionPipeline: MockTranscriptionPipeline(),
            meetingRepository: MockMeetingRepository(),
            embeddingPipeline: MockEmbeddingPipeline(),
            microphoneCapture: MockMicrophoneCaptureForMeeting(),
            systemAudioCapture: MockSystemAudioCaptureForMeeting()
        )

        let viewModel = MeetingViewModel(
            sessionController: controller,
            suggestionEngine: suggestionEngine,
            chatMessageRepository: chatMessageRepository
        )
        return (viewModel, controller)
    }
}
