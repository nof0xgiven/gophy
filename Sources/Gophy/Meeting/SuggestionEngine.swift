import Foundation

// MARK: - Protocols for Dependencies

public protocol TextGenerationForSuggestion: Sendable {
    var isLoaded: Bool { get }
    func load() async throws
    func unload()
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String>
}

extension TextGenerationEngine: TextGenerationForSuggestion {}

public protocol VectorSearchForSuggestion: Sendable {
    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult]
    func insert(id: String, embedding: [Float]) async throws
    func delete(id: String) async throws
    func count() async throws -> Int
}

extension VectorSearchService: VectorSearchForSuggestion {}

public protocol ChatMessageRepoForSuggestion: Sendable {
    func create(_ message: ChatMessageRecord) async throws
    func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord]
    func delete(id: String) async throws
}

public protocol DocumentRepositoryForSuggestion: Sendable {
    func get(id: String) async throws -> DocumentRecord?
    func getChunk(id: String) async throws -> DocumentChunkRecord?
    func getChunks(documentId: String) async throws -> [DocumentChunkRecord]
}

extension DocumentRepository: DocumentRepositoryForSuggestion {}

/// Adapter that wraps TextGenerationForSuggestion as a TextGenerationProvider
private final class TextGenProviderAdapter: TextGenerationProvider, @unchecked Sendable {
    private let engine: any TextGenerationForSuggestion

    init(engine: any TextGenerationForSuggestion) {
        self.engine = engine
    }

    func generate(prompt: String, systemPrompt: String, maxTokens: Int, temperature: Double) -> AsyncThrowingStream<String, Error> {
        let stream = engine.generate(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        return AsyncThrowingStream { continuation in
            Task {
                for await token in stream {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - SuggestionEngine

public actor SuggestionEngine {
    private let textGenProvider: (any TextGenerationProvider)?
    private let providerRegistry: ProviderRegistry?
    private let vectorSearchService: any VectorSearchForSuggestion
    private let embeddingEngine: any EmbeddingProviding
    private let meetingRepository: any MeetingRepositoryProtocol
    private let documentRepository: any DocumentRepositoryForSuggestion
    private let chatMessageRepository: any ChatMessageRepoForSuggestion
    private let autoTriggerInterval: TimeInterval

    private let systemPrompt = """
        You are a silent meeting research assistant. Surface useful facts — never give conversation advice.

        Format (strict):
        1. ONE sentence: the key fact, detail, or context the user needs right now.
        2. IF a specific topic/term/function/decision is referenced that the user may not recall, \
           add 2-3 short bullet points (- dash format) explaining what it is. Skip bullets if the \
           topic is obvious.

        Rules:
        - Never say "consider asking", "you might want to", or "it would be helpful to".
        - Never repeat what was just said. Only add new information.
        - Be direct. Write like a sticky note, not a paragraph.
        """

    /// Resolve the active text generation provider
    private var activeTextGenProvider: any TextGenerationProvider {
        if let registry = providerRegistry {
            return registry.activeTextGenProvider()
        }
        return textGenProvider!
    }

    /// Initialize with a ProviderRegistry (preferred — enables dynamic provider switching)
    public init(
        providerRegistry: ProviderRegistry,
        vectorSearchService: any VectorSearchForSuggestion,
        embeddingEngine: any EmbeddingProviding,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryForSuggestion,
        chatMessageRepository: any ChatMessageRepoForSuggestion,
        autoTriggerInterval: TimeInterval = 30.0
    ) {
        self.providerRegistry = providerRegistry
        self.textGenProvider = nil
        self.vectorSearchService = vectorSearchService
        self.embeddingEngine = embeddingEngine
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.chatMessageRepository = chatMessageRepository
        self.autoTriggerInterval = autoTriggerInterval
    }

    /// Initialize with a TextGenerationProvider directly
    public init(
        textGenProvider: any TextGenerationProvider,
        vectorSearchService: any VectorSearchForSuggestion,
        embeddingEngine: any EmbeddingProviding,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryForSuggestion,
        chatMessageRepository: any ChatMessageRepoForSuggestion,
        autoTriggerInterval: TimeInterval = 30.0
    ) {
        self.textGenProvider = textGenProvider
        self.providerRegistry = nil
        self.vectorSearchService = vectorSearchService
        self.embeddingEngine = embeddingEngine
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.chatMessageRepository = chatMessageRepository
        self.autoTriggerInterval = autoTriggerInterval
    }

    /// Initialize with the legacy TextGenerationForSuggestion protocol (backwards compatible)
    public init(
        textGenerationEngine: any TextGenerationForSuggestion,
        vectorSearchService: any VectorSearchForSuggestion,
        embeddingEngine: any EmbeddingProviding,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryForSuggestion,
        chatMessageRepository: any ChatMessageRepoForSuggestion,
        autoTriggerInterval: TimeInterval = 30.0
    ) {
        self.textGenProvider = TextGenProviderAdapter(engine: textGenerationEngine)
        self.providerRegistry = nil
        self.vectorSearchService = vectorSearchService
        self.embeddingEngine = embeddingEngine
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.chatMessageRepository = chatMessageRepository
        self.autoTriggerInterval = autoTriggerInterval
    }

    /// Generate a suggestion manually on demand
    /// - Parameter meetingId: The meeting to generate a suggestion for
    /// - Returns: The complete generated suggestion text
    public func generateSuggestion(meetingId: String) async throws -> String {
        var fullSuggestion = ""

        for await token in generateSuggestionStream(meetingId: meetingId) {
            fullSuggestion += token
        }

        return fullSuggestion
    }

    /// Start automatic suggestions triggered every N seconds of transcript
    /// - Parameters:
    ///   - meetingId: The meeting to generate suggestions for
    ///   - transcriptStream: Stream of incoming transcript segments
    /// - Returns: AsyncStream of complete suggestions (not tokens)
    public nonisolated func startAutoSuggestions(
        meetingId: String,
        transcriptStream: AsyncStream<TranscriptSegment>
    ) -> AsyncStream<String> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                var accumulatedDuration: TimeInterval = 0.0

                for await segment in transcriptStream {
                    let segmentDuration = segment.endTime - segment.startTime
                    accumulatedDuration += segmentDuration

                    if accumulatedDuration >= self.autoTriggerInterval {
                        do {
                            let suggestion = try await self.generateSuggestion(meetingId: meetingId)
                            continuation.yield(suggestion)
                            accumulatedDuration = 0.0
                        } catch {
                            print("Error auto-generating suggestion: \(error)")
                            accumulatedDuration = 0.0
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Generate a suggestion with streaming tokens
    /// - Parameter meetingId: The meeting to generate a suggestion for
    /// - Returns: AsyncStream of generated tokens
    /// - Throws: Errors are not thrown directly; they terminate the stream
    public nonisolated func generateSuggestionStream(meetingId: String) -> AsyncStream<String> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    // Get last 60 seconds of transcript
                    let transcript = try await self.getRecentTranscript(meetingId: meetingId, lastSeconds: 60.0)

                    // Get RAG context
                    let ragContext = try await self.getRAGContext(for: transcript)

                    // Build prompt
                    let prompt = await self.buildPrompt(transcript: transcript, ragContext: ragContext)

                    // Generate suggestion (resolve provider inside actor context)
                    let provider = await self.activeTextGenProvider
                    var fullSuggestion = ""
                    let stream = provider.generate(
                        prompt: prompt,
                        systemPrompt: self.systemPrompt,
                        maxTokens: 150,
                        temperature: 0.7
                    )

                    for try await token in stream {
                        fullSuggestion += token
                        continuation.yield(token)
                    }

                    // Store suggestion as chat message
                    do {
                        try await self.storeSuggestion(fullSuggestion, meetingId: meetingId)
                    } catch {
                        // Log storage error but don't fail the entire suggestion
                        print("Error storing suggestion: \(error)")
                    }

                    continuation.finish()
                } catch {
                    print("Error generating suggestion: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Private Methods

    private func getRecentTranscript(meetingId: String, lastSeconds: TimeInterval) async throws -> [TranscriptSegmentRecord] {
        let allSegments = try await meetingRepository.getTranscript(meetingId: meetingId)

        guard !allSegments.isEmpty else {
            return []
        }

        // Get segments from the last N seconds
        let latestTime = allSegments.map { $0.endTime }.max() ?? 0
        let cutoffTime = latestTime - lastSeconds

        return allSegments.filter { $0.endTime >= cutoffTime }
    }

    private enum RAGContextItem {
        case transcriptSegment(TranscriptSegmentRecord)
        case documentChunk(DocumentChunkRecord)
    }

    private func getRAGContext(for transcript: [TranscriptSegmentRecord]) async throws -> [RAGContextItem] {
        guard !transcript.isEmpty else {
            return []
        }

        // Combine transcript text for embedding
        let combinedText = transcript.map { $0.text }.joined(separator: " ")

        // Embed query
        let queryEmbedding = try await embeddingEngine.embed(text: combinedText, mode: .query)

        // Search for similar segments and chunks
        let searchResults = try await vectorSearchService.search(query: queryEmbedding, limit: 5)

        // Fetch full segments or chunks
        var contextItems: [RAGContextItem] = []
        for result in searchResults {
            // Try as transcript segment first
            if let segment = try await meetingRepository.getSegment(id: result.id) {
                contextItems.append(.transcriptSegment(segment))
            } else if let chunk = try await documentRepository.getChunk(id: result.id) {
                // Try as document chunk
                contextItems.append(.documentChunk(chunk))
            }
        }

        return contextItems
    }

    private func buildPrompt(transcript: [TranscriptSegmentRecord], ragContext: [RAGContextItem]) -> String {
        var prompt = "Current conversation:\n"

        for segment in transcript {
            prompt += "[\(segment.speaker)] \(segment.text)\n"
        }

        if !ragContext.isEmpty {
            prompt += "\nRelevant context:\n"
            for item in ragContext {
                switch item {
                case .transcriptSegment(let segment):
                    prompt += "[Past conversation - \(segment.speaker)] \(segment.text)\n"
                case .documentChunk(let chunk):
                    prompt += "[Document - page \(chunk.pageNumber)] \(chunk.content)\n"
                }
            }
        }

        prompt += "\nSuggestion:"

        return prompt
    }

    private func storeSuggestion(_ suggestion: String, meetingId: String) async throws {
        let message = ChatMessageRecord(
            id: UUID().uuidString,
            role: "assistant",
            content: suggestion,
            meetingId: meetingId,
            createdAt: Date()
        )

        try await chatMessageRepository.create(message)
    }
}
