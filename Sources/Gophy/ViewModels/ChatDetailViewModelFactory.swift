import Foundation

@MainActor
struct ChatDetailViewModelFactory {
    var makeEmbeddingEngine: @MainActor () -> any EmbeddingCapable = { EmbeddingEngine() }
    var makeTextGenerationEngine: @MainActor () -> any TextGenerationEngineProtocol = { TextGenerationEngine() }
    var makeTranscriptionEngine: @MainActor () -> any TranscriptionEngineProtocol = { TranscriptionEngine() }
    var makeOCREngine: @MainActor () -> any OCREngineActorProtocol = { OCREngine() }

    func make(chat: ChatRecord, database: GophyDatabase) async throws -> ChatDetailViewModel {
        let documentRepo = DocumentRepository(database: database)
        let meetingRepo = MeetingRepository(database: database)
        let chatMessageRepo = ChatMessageRepository(database: database)
        let chatRepo = ChatRepository(database: database)

        let embeddingEngine = makeEmbeddingEngine()
        let textGenEngine = makeTextGenerationEngine()
        let transcriptionEngine = makeTranscriptionEngine()
        let ocrEngine = makeOCREngine()

        let providerRegistry = ProviderRegistry(
            transcriptionEngine: transcriptionEngine,
            textGenerationEngine: textGenEngine,
            embeddingEngine: embeddingEngine,
            ocrEngine: ocrEngine
        )

        let vectorSearchService = VectorSearchService(database: database)

        let ragPipeline = RAGPipeline(
            embeddingEngine: embeddingEngine,
            vectorSearchService: vectorSearchService,
            providerRegistry: providerRegistry,
            meetingRepository: meetingRepo,
            documentRepository: documentRepo
        )

        let viewModel = ChatDetailViewModel(
            chat: chat,
            chatMessageRepository: chatMessageRepo,
            chatRepository: chatRepo,
            ragPipeline: ragPipeline,
            providerRegistry: providerRegistry
        )
        await viewModel.loadMessages()
        return viewModel
    }
}
