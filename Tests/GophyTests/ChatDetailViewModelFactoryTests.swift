import XCTest
@testable import Gophy

@MainActor
final class ChatDetailViewModelFactoryTests: XCTestCase {
    func testFactoryDoesNotEagerlyLoadLocalEmbeddingEngine() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gophy-chat-factory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storageManager = StorageManager(baseDirectory: temporaryDirectory)
        let database = try GophyDatabase(storageManager: storageManager)
        let chats = try await ChatRepository(database: database).listAll()
        let chat = try XCTUnwrap(chats.first)
        let embeddingEngine = ChatFactoryEmbeddingEngine()

        let factory = ChatDetailViewModelFactory(
            makeEmbeddingEngine: { embeddingEngine },
            makeTextGenerationEngine: { ChatFactoryTextGenerationEngine() },
            makeTranscriptionEngine: { ChatFactoryTranscriptionEngine() },
            makeOCREngine: { ChatFactoryOCREngine() }
        )

        let viewModel = try await factory.make(chat: chat, database: database)

        XCTAssertEqual(viewModel.chat.id, chat.id)
        XCTAssertFalse(embeddingEngine.loadCalled)
    }
}

final class ChatFactoryEmbeddingEngine: EmbeddingCapable, @unchecked Sendable {
    var isLoaded = false
    var embeddingDimension = 384
    var loadCalled = false

    func load() async throws {
        loadCalled = true
        throw EmbeddingError.noModelAvailable
    }

    func unload() {
        isLoaded = false
    }

    func embed(text: String, mode: EmbeddingMode) async throws -> [Float] {
        [Float](repeating: 0.1, count: embeddingDimension)
    }

    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]] {
        texts.map { _ in [Float](repeating: 0.1, count: embeddingDimension) }
    }
}

final class ChatFactoryTextGenerationEngine: TextGenerationEngineProtocol, @unchecked Sendable {
    var isLoaded = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

final class ChatFactoryTranscriptionEngine: TranscriptionEngineProtocol, @unchecked Sendable {
    var isLoaded = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

actor ChatFactoryOCREngine: OCREngineActorProtocol {
    private var loaded = false

    nonisolated var isLoaded: Bool {
        get async { await loaded }
    }

    func load() async throws {
        loaded = true
    }

    func unload() async {
        loaded = false
    }
}
