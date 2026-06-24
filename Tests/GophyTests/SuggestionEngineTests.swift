import XCTest
@testable import Gophy

final class SuggestionEngineTests: XCTestCase {
    private var engine: SuggestionEngine!
    private var mockTextGen: MockTextGenerationForSuggestion!
    private var mockVectorSearch: MockVectorSearchForSuggestion!
    private var mockEmbedding: MockEmbeddingForSuggestion!
    private var mockMeetingRepo: MockMeetingRepoForSuggestion!
    private var mockDocumentRepo: MockDocumentRepoForSuggestion!
    private var mockChatRepo: MockChatMessageRepoForSuggestion!

    override func setUp() async throws {
        try await super.setUp()

        mockTextGen = MockTextGenerationForSuggestion()
        mockVectorSearch = MockVectorSearchForSuggestion()
        mockEmbedding = MockEmbeddingForSuggestion()
        mockMeetingRepo = MockMeetingRepoForSuggestion()
        mockDocumentRepo = MockDocumentRepoForSuggestion()
        mockChatRepo = MockChatMessageRepoForSuggestion()

        engine = SuggestionEngine(
            textGenerationEngine: mockTextGen,
            vectorSearchService: mockVectorSearch,
            embeddingEngine: mockEmbedding,
            meetingRepository: mockMeetingRepo,
            documentRepository: mockDocumentRepo,
            chatMessageRepository: mockChatRepo,
            autoTriggerInterval: 30.0
        )
    }

    func testSuggestionGeneratedFromTranscriptAndRAGContext() async throws {
        // Set up transcript
        let transcriptSegments = [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "We should discuss the quarterly results",
                speaker: "You",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        ]
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: transcriptSegments)

        // Set up RAG results
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([
            VectorSearchResult(id: "seg2", distance: 0.5),
            VectorSearchResult(id: "seg3", distance: 0.6)
        ])
        await mockMeetingRepo.setSegment(
            "seg2",
            TranscriptSegmentRecord(
                id: "seg2",
                meetingId: "meeting1",
                text: "Last quarter we achieved 20% growth",
                speaker: "Others",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        )
        await mockMeetingRepo.setSegment(
            "seg3",
            TranscriptSegmentRecord(
                id: "seg3",
                meetingId: "meeting1",
                text: "Focus on customer retention metrics",
                speaker: "You",
                startTime: 10.0,
                endTime: 15.0,
                createdAt: Date()
            )
        )

        // Set up text generation
        await mockTextGen.setTokens(["Based", " on", " past", " results", ",", " focus", " on", " growth", " metrics"])

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Based on past results, focus on growth metrics")
        let savedMessages = await mockChatRepo.savedMessages
        XCTAssertEqual(savedMessages.count, 1)
        let savedMessage = savedMessages.first!
        XCTAssertEqual(savedMessage.role, "assistant")
        XCTAssertEqual(savedMessage.content, "Based on past results, focus on growth metrics")
        XCTAssertEqual(savedMessage.meetingId, "meeting1")
    }

    func testSuggestionRAGExcludesOtherMeetingsAndUnallowedDocuments() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Discuss the launch plan",
                speaker: "You",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        ])

        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([
            VectorSearchResult(id: "other-meeting-segment", distance: 0.1),
            VectorSearchResult(id: "unallowed-document-chunk", distance: 0.2)
        ])
        await mockMeetingRepo.setSegment(
            "other-meeting-segment",
            TranscriptSegmentRecord(
                id: "other-meeting-segment",
                meetingId: "meeting0",
                text: "Confidential acquisition discussion",
                speaker: "Others",
                startTime: 0.0,
                endTime: 4.0,
                createdAt: Date()
            )
        )
        await mockDocumentRepo.setChunk(
            "unallowed-document-chunk",
            DocumentChunkRecord(
                id: "unallowed-document-chunk",
                documentId: "doc-private",
                content: "Private board memo",
                chunkIndex: 0,
                pageNumber: 1,
                createdAt: Date()
            )
        )
        await mockTextGen.setTokens(["Scoped", " suggestion"])

        _ = try await engine.generateSuggestion(meetingId: "meeting1")

        let prompt = await mockTextGen.lastPrompt
        XCTAssertNotNil(prompt)
        XCTAssertFalse(prompt?.contains("Confidential acquisition discussion") ?? true)
        XCTAssertFalse(prompt?.contains("Private board memo") ?? true)
        XCTAssertTrue(prompt?.contains("Discuss the launch plan") ?? false)
    }

    func testManualTriggerOnDemand() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Manual", " suggestion"])

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Manual suggestion")
    }

    func testSuggestionsStoredAsChatMessages() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Test transcript",
                speaker: "You",
                startTime: 0.0,
                endTime: 1.0,
                createdAt: Date()
            )
        ])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Stored", " message"])

        _ = try await engine.generateSuggestion(meetingId: "meeting1")

        let savedMessages = await mockChatRepo.savedMessages
        XCTAssertEqual(savedMessages.count, 1)
        XCTAssertEqual(savedMessages.first?.role, "assistant")
        XCTAssertEqual(savedMessages.first?.content, "Stored message")
    }

    func testAutomaticTriggerEvery30SecondsOfTranscript() async throws {
        // Set up test data
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Auto", " suggestion"])

        // Create transcript stream with segments totaling 30+ seconds
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptSegment.self)

        let expectation = expectation(description: "Auto-trigger fires after 30 seconds")
        let localEngine = engine!

        Task { @Sendable in
            var suggestionCount = 0
            for await _ in localEngine.startAutoSuggestions(meetingId: "meeting1", transcriptStream: stream) {
                suggestionCount += 1
                if suggestionCount == 1 {
                    expectation.fulfill()
                }
            }
        }

        // Yield segments totaling 35 seconds (should trigger once)
        continuation.yield(TranscriptSegment(text: "First", startTime: 0, endTime: 15, speaker: "You"))
        try await Task.sleep(nanoseconds: 50_000_000)
        continuation.yield(TranscriptSegment(text: "Second", startTime: 15, endTime: 35, speaker: "You"))
        try await Task.sleep(nanoseconds: 50_000_000)
        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testStreamingSuggestionYieldsTokens() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Test",
                speaker: "You",
                startTime: 0.0,
                endTime: 1.0,
                createdAt: Date()
            )
        ])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Token", " 1", " Token", " 2"])

        var tokens: [String] = []
        for await token in engine.generateSuggestionStream(meetingId: "meeting1") {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Token", " 1", " Token", " 2"])
    }

    func testEmptySuggestionStreamIsNotStoredAsChatMessage() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens([])

        var tokens: [String] = []
        for await token in engine.generateSuggestionStream(meetingId: "meeting1") {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, [])
        let savedMessages = await mockChatRepo.savedMessages
        XCTAssertEqual(savedMessages.count, 0)
    }

    func testRAGContextIncludesExplicitlyAllowedDocumentChunks() async throws {
        // Set up transcript
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Discuss the product roadmap",
                speaker: "You",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        ])

        // Set up RAG results: one segment, one document chunk
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([
            VectorSearchResult(id: "seg2", distance: 0.5),
            VectorSearchResult(id: "chunk1", distance: 0.6)
        ])
        await mockMeetingRepo.setSegment(
            "seg2",
            TranscriptSegmentRecord(
                id: "seg2",
                meetingId: "meeting0",
                text: "Previous roadmap discussion",
                speaker: "Others",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        )
        await mockDocumentRepo.setChunk(
            "chunk1",
            DocumentChunkRecord(
                id: "chunk1",
                documentId: "doc1",
                content: "Q3 product features include AI integration",
                chunkIndex: 0,
                pageNumber: 1,
                createdAt: Date()
            )
        )

        await mockTextGen.setTokens(["Combined", " context"])
        engine = SuggestionEngine(
            textGenerationEngine: mockTextGen,
            vectorSearchService: mockVectorSearch,
            embeddingEngine: mockEmbedding,
            meetingRepository: mockMeetingRepo,
            documentRepository: mockDocumentRepo,
            chatMessageRepository: mockChatRepo,
            allowedDocumentIds: ["doc1"],
            autoTriggerInterval: 30.0
        )

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Combined context")
        let prompt = await mockTextGen.lastPrompt
        XCTAssertTrue(prompt?.contains("Q3 product features include AI integration") ?? false)
    }

    func testCloudEmbeddingProviderUsedForSuggestionRetrievalWhenSelected() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "The client asked about the migration timeline",
                speaker: "Client",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        ])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])

        let cloudEmbedding = MockSuggestionCloudEmbeddingProvider(embedding: [0.7, 0.8, 0.9])
        let cloudText = MockSuggestionTextGenerationProvider(tokens: ["Cloud", " suggestion"])
        let providerResolver = MockSuggestionProviderResolver(
            embeddingProvider: cloudEmbedding,
            textGenerationProvider: cloudText,
            embeddingProviderId: "openrouter"
        )

        let engine = SuggestionEngine(
            providerRegistry: providerResolver,
            vectorSearchService: mockVectorSearch,
            embeddingEngine: mockEmbedding,
            meetingRepository: mockMeetingRepo,
            documentRepository: mockDocumentRepo,
            chatMessageRepository: mockChatRepo,
            autoTriggerInterval: 30.0
        )

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Cloud suggestion")
        let cloudEmbedCallCount = await cloudEmbedding.embedCallCount
        let cloudLastEmbeddedText = await cloudEmbedding.lastEmbeddedText
        let localEmbedCallCount = await mockEmbedding.embedCallCount
        let lastSearchQuery = await mockVectorSearch.lastQuery
        XCTAssertEqual(cloudEmbedCallCount, 1)
        XCTAssertEqual(cloudLastEmbeddedText, "The client asked about the migration timeline")
        XCTAssertEqual(localEmbedCallCount, 0)
        XCTAssertEqual(lastSearchQuery, [0.7, 0.8, 0.9])
    }
}

// MARK: - Mock Text Generation Engine

actor MockTextGenerationForSuggestion: TextGenerationForSuggestion {
    nonisolated var isLoaded: Bool { true }
    private var tokensToGenerate: [String] = []
    private(set) var lastPrompt: String?

    func load() async throws {
        // No-op
    }

    nonisolated func unload() {
        // No-op
    }

    nonisolated func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        let capturedSelf = self
        return AsyncStream { continuation in
            Task { @Sendable in
                await capturedSelf.setLastPrompt(prompt)
                let tokens = await capturedSelf.getTokens()
                for token in tokens {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }

    func setTokens(_ tokens: [String]) {
        tokensToGenerate = tokens
    }

    private func getTokens() -> [String] {
        tokensToGenerate
    }

    private func setLastPrompt(_ prompt: String) {
        lastPrompt = prompt
    }
}

// MARK: - Mock Vector Search

actor MockVectorSearchForSuggestion: VectorSearchForSuggestion {
    private var resultsToReturn: [VectorSearchResult] = []
    private(set) var lastQuery: [Float] = []

    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult] {
        lastQuery = query
        return resultsToReturn
    }

    func insert(id: String, embedding: [Float]) async throws {
        // No-op
    }

    func delete(id: String) async throws {
        // No-op
    }

    func count() async throws -> Int {
        0
    }

    func setResults(_ results: [VectorSearchResult]) {
        resultsToReturn = results
    }
}

// MARK: - Mock Embedding Engine

actor MockEmbeddingForSuggestion: EmbeddingProviding {
    private var embeddingToReturn: [Float] = []
    private(set) var embedCallCount = 0

    func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        embedCallCount += 1
        return embeddingToReturn
    }

    func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        texts.map { _ in embeddingToReturn }
    }

    func setEmbedding(_ embedding: [Float]) {
        embeddingToReturn = embedding
    }
}

// MARK: - Mock Cloud Providers

actor MockSuggestionCloudEmbeddingProvider: EmbeddingProvider {
    private let embedding: [Float]
    private(set) var embedCallCount = 0
    private(set) var lastEmbeddedText: String?

    nonisolated let dimensions: Int

    init(embedding: [Float]) {
        self.embedding = embedding
        self.dimensions = embedding.count
    }

    func embed(text: String) async throws -> [Float] {
        embedCallCount += 1
        lastEmbeddedText = text
        return embedding
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in embedding }
    }
}

final class MockSuggestionTextGenerationProvider: TextGenerationProvider, @unchecked Sendable {
    private let tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let tokens = self.tokens
        return AsyncThrowingStream { continuation in
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}

final class MockSuggestionProviderResolver: RAGProviderResolving, @unchecked Sendable {
    private let embeddingProvider: any EmbeddingProvider
    private let textGenerationProvider: any TextGenerationProvider
    private let embeddingProviderId: String

    init(
        embeddingProvider: any EmbeddingProvider,
        textGenerationProvider: any TextGenerationProvider,
        embeddingProviderId: String
    ) {
        self.embeddingProvider = embeddingProvider
        self.textGenerationProvider = textGenerationProvider
        self.embeddingProviderId = embeddingProviderId
    }

    func activeTextGenProvider() -> any TextGenerationProvider {
        textGenerationProvider
    }

    func activeEmbeddingProvider() -> any EmbeddingProvider {
        embeddingProvider
    }

    func selectedProviderId(for capability: ProviderCapability) -> String {
        switch capability {
        case .embedding:
            return embeddingProviderId
        case .textGeneration:
            return "openrouter"
        case .speechToText, .vision, .textToSpeech:
            return "local"
        }
    }
}

// MARK: - Mock Meeting Repository

actor MockMeetingRepoForSuggestion: MeetingRepositoryProtocol {
    private var transcripts: [String: [TranscriptSegmentRecord]] = [:]
    private var segmentsById: [String: TranscriptSegmentRecord] = [:]

    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        transcripts[meetingId] ?? []
    }

    func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        segmentsById[id]
    }

    func create(_ meeting: MeetingRecord) async throws {
        // No-op
    }

    func update(_ meeting: MeetingRecord) async throws {
        // No-op
    }

    func get(id: String) async throws -> MeetingRecord? {
        nil
    }

    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord] {
        []
    }

    func delete(id: String) async throws {
        // No-op
    }

    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {
        // No-op
    }

    func search(query: String) async throws -> [MeetingRecord] {
        []
    }

    func findOrphaned() async throws -> [MeetingRecord] {
        []
    }

    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord] {
        []
    }

    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws {
        // No-op
    }

    func setTranscript(for meetingId: String, segments: [TranscriptSegmentRecord]) {
        transcripts[meetingId] = segments
    }

    func setSegment(_ id: String, _ segment: TranscriptSegmentRecord) {
        segmentsById[id] = segment
    }
}

// MARK: - Mock Document Repository

actor MockDocumentRepoForSuggestion: DocumentRepositoryForSuggestion {
    private var chunksById: [String: DocumentChunkRecord] = [:]

    func get(id: String) async throws -> DocumentRecord? {
        nil
    }

    func getChunk(id: String) async throws -> DocumentChunkRecord? {
        chunksById[id]
    }

    func getChunks(documentId: String) async throws -> [DocumentChunkRecord] {
        []
    }

    func setChunk(_ id: String, _ chunk: DocumentChunkRecord) {
        chunksById[id] = chunk
    }
}

// MARK: - Mock Chat Message Repository

actor MockChatMessageRepoForSuggestion: ChatMessageRepoForSuggestion {
    private(set) var savedMessages: [ChatMessageRecord] = []

    func create(_ message: ChatMessageRecord) async throws {
        savedMessages.append(message)
    }

    func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord] {
        savedMessages.filter { $0.meetingId == meetingId }
    }

    func delete(id: String) async throws {
        // No-op
    }
}
