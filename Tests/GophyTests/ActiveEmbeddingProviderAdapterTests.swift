import XCTest
@testable import Gophy

final class ActiveEmbeddingProviderAdapterTests: XCTestCase {
    func testCloudSelectionUsesCloudEmbeddingProviderAndDoesNotLoadLocalEngine() async throws {
        let localEngine = AdapterLocalEmbeddingEngine()
        let cloudProvider = AdapterCloudEmbeddingProvider(embedding: [1, 2, 3])
        let textProvider = AdapterTextGenerationProvider()
        let resolver = AdapterProviderResolver(
            selectedEmbeddingProviderId: "openrouter",
            embeddingProvider: cloudProvider,
            textGenerationProvider: textProvider
        )

        let adapter = ActiveEmbeddingProviderAdapter(
            providerResolver: resolver,
            localEmbeddingEngine: localEngine
        )

        let embedding = try await adapter.embed(text: "hello", mode: .query)
        let cloudEmbedCallCount = await cloudProvider.embedCallCount

        XCTAssertEqual(embedding, [1, 2, 3])
        XCTAssertEqual(cloudEmbedCallCount, 1)
        XCTAssertFalse(localEngine.loadCalled)
    }

    func testLocalSelectionLoadsAndUsesLocalEmbeddingEngine() async throws {
        let localEngine = AdapterLocalEmbeddingEngine()
        let cloudProvider = AdapterCloudEmbeddingProvider(embedding: [1, 2, 3])
        let textProvider = AdapterTextGenerationProvider()
        let resolver = AdapterProviderResolver(
            selectedEmbeddingProviderId: "local",
            embeddingProvider: cloudProvider,
            textGenerationProvider: textProvider
        )

        let adapter = ActiveEmbeddingProviderAdapter(
            providerResolver: resolver,
            localEmbeddingEngine: localEngine
        )

        let embedding = try await adapter.embed(text: "hello", mode: .query)
        let cloudEmbedCallCount = await cloudProvider.embedCallCount

        XCTAssertEqual(embedding, [0.4, 0.5])
        XCTAssertTrue(localEngine.loadCalled)
        XCTAssertEqual(cloudEmbedCallCount, 0)
    }
}

final class AdapterLocalEmbeddingEngine: EmbeddingCapable, @unchecked Sendable {
    var isLoaded = false
    var embeddingDimension = 2
    var loadCalled = false

    func load() async throws {
        loadCalled = true
        isLoaded = true
    }

    func unload() {
        isLoaded = false
    }

    func embed(text: String, mode: EmbeddingMode) async throws -> [Float] {
        [0.4, 0.5]
    }

    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]] {
        texts.map { _ in [0.4, 0.5] }
    }
}

actor AdapterCloudEmbeddingProvider: EmbeddingProvider {
    private let embedding: [Float]
    private(set) var embedCallCount = 0
    nonisolated let dimensions: Int

    init(embedding: [Float]) {
        self.embedding = embedding
        self.dimensions = embedding.count
    }

    func embed(text: String) async throws -> [Float] {
        embedCallCount += 1
        return embedding
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in embedding }
    }
}

final class AdapterTextGenerationProvider: TextGenerationProvider, @unchecked Sendable {
    func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

final class AdapterProviderResolver: RAGProviderResolving, @unchecked Sendable {
    private let selectedEmbeddingProviderId: String
    private let embeddingProvider: any EmbeddingProvider
    private let textGenerationProvider: any TextGenerationProvider

    init(
        selectedEmbeddingProviderId: String,
        embeddingProvider: any EmbeddingProvider,
        textGenerationProvider: any TextGenerationProvider
    ) {
        self.selectedEmbeddingProviderId = selectedEmbeddingProviderId
        self.embeddingProvider = embeddingProvider
        self.textGenerationProvider = textGenerationProvider
    }

    func activeTextGenProvider() -> any TextGenerationProvider {
        textGenerationProvider
    }

    func activeEmbeddingProvider() -> any EmbeddingProvider {
        embeddingProvider
    }

    func selectedProviderId(for capability: ProviderCapability) -> String {
        capability == .embedding ? selectedEmbeddingProviderId : "local"
    }
}
