import Foundation

public final class ActiveEmbeddingProviderAdapter: EmbeddingProviding, @unchecked Sendable {
    private let providerResolver: any RAGProviderResolving
    private let localEmbeddingEngine: any EmbeddingCapable

    public init(
        providerResolver: any RAGProviderResolving,
        localEmbeddingEngine: any EmbeddingCapable
    ) {
        self.providerResolver = providerResolver
        self.localEmbeddingEngine = localEmbeddingEngine
    }

    public func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        if providerResolver.selectedProviderId(for: .embedding) != "local" {
            return try await providerResolver.activeEmbeddingProvider().embed(text: text)
        }

        if !localEmbeddingEngine.isLoaded {
            try await localEmbeddingEngine.load()
        }
        return try await localEmbeddingEngine.embed(text: text, mode: mode)
    }

    public func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        if providerResolver.selectedProviderId(for: .embedding) != "local" {
            return try await providerResolver.activeEmbeddingProvider().embedBatch(texts: texts)
        }

        if !localEmbeddingEngine.isLoaded {
            try await localEmbeddingEngine.load()
        }
        return try await localEmbeddingEngine.embedBatch(texts: texts, mode: mode)
    }
}
