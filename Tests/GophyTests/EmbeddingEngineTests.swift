import XCTest
import Foundation
@testable import Gophy

final class EmbeddingEngineTests: XCTestCase {
    var mockModelRegistry: EmbeddingMockModelRegistry!
    var engine: EmbeddingEngine!

    override func setUp() async throws {
        try await super.setUp()
        try Self.stageMLXMetalLibraryForXCTest()
        UserDefaults.standard.set("multilingual-e5-small", forKey: "selectedEmbeddingModelId")
        mockModelRegistry = EmbeddingMockModelRegistry()
        engine = EmbeddingEngine(modelRegistry: mockModelRegistry)
    }

    override func tearDown() async throws {
        engine = nil
        mockModelRegistry = nil
        UserDefaults.standard.removeObject(forKey: "selectedEmbeddingModelId")
        try await super.tearDown()
    }

    private static func stageMLXMetalLibraryForXCTest() throws {
        let fileManager = FileManager.default
        let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let sourceBundle = repositoryRoot
            .appendingPathComponent(".build/xcode/Build/Products/Debug/mlx-swift_Cmlx.bundle")

        guard fileManager.fileExists(atPath: sourceBundle.path) else {
            throw XCTSkip("MLX Metal library bundle not found. Run ./build.sh before MLX embedding engine tests.")
        }

        let testBundle = Bundle(for: EmbeddingEngineTests.self).bundleURL
        let resourcesDirectory = testBundle
            .appendingPathComponent("Contents/Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let destinationBundle = resourcesDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle")
        if fileManager.fileExists(atPath: destinationBundle.path) {
            try fileManager.removeItem(at: destinationBundle)
        }
        try fileManager.copyItem(at: sourceBundle, to: destinationBundle)

        let executableResources = testBundle
            .appendingPathComponent("Contents/MacOS/Resources", isDirectory: true)
        try fileManager.createDirectory(at: executableResources, withIntermediateDirectories: true)

        let sourceMetallib = sourceBundle
            .appendingPathComponent("Contents/Resources/default.metallib")
        let destinationMetallib = executableResources.appendingPathComponent("default.metallib")
        if fileManager.fileExists(atPath: destinationMetallib.path) {
            try fileManager.removeItem(at: destinationMetallib)
        }
        try fileManager.copyItem(at: sourceMetallib, to: destinationMetallib)
    }

    func testEmbeddingEngineCanBeInitialized() {
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isLoaded)
    }

    func testEmbeddingEngineLoadSetsIsLoadedToTrue() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    func testEmbedThrowsWhenModelNotLoaded() async {
        do {
            _ = try await engine.embed(text: "test text")
            XCTFail("Expected EmbeddingError.modelNotLoaded")
        } catch EmbeddingError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected EmbeddingError.modelNotLoaded but got \(error)")
        }
    }

    func testEmbedBatchThrowsWhenModelNotLoaded() async {
        do {
            _ = try await engine.embedBatch(texts: ["test1", "test2"])
            XCTFail("Expected EmbeddingError.modelNotLoaded")
        } catch EmbeddingError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected EmbeddingError.modelNotLoaded but got \(error)")
        }
    }

    func testEmbedReturnsFloatArray() async throws {
        try await engine.load()

        let embedding = try await engine.embed(text: "Hello, world!")

        XCTAssertFalse(embedding.isEmpty)
        XCTAssertGreaterThan(embedding.count, 0)
    }

    func testEmbedBatchReturnsArrayOfFloatArrays() async throws {
        try await engine.load()

        let texts = ["Hello, world!", "How are you?"]
        let embeddings = try await engine.embedBatch(texts: texts)

        XCTAssertEqual(embeddings.count, texts.count)
        for embedding in embeddings {
            XCTAssertFalse(embedding.isEmpty)
            XCTAssertGreaterThan(embedding.count, 0)
        }
    }

    func testUnloadSetsIsLoadedToFalse() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)
    }

    func testUnloadAllowsReloading() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)

        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    func testEmbedConsistency() async throws {
        try await engine.load()

        let text = "This is a test sentence."
        let embedding1 = try await engine.embed(text: text)
        let embedding2 = try await engine.embed(text: text)

        XCTAssertEqual(embedding1.count, embedding2.count)
        for (val1, val2) in zip(embedding1, embedding2) {
            XCTAssertEqual(val1, val2, accuracy: 0.0001)
        }
    }
}

final class EmbeddingMockModelRegistry: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "multilingual-e5-small",
                name: "Multilingual E5 Small (Embeddings)",
                type: .embedding,
                huggingFaceID: "intfloat/multilingual-e5-small",
                approximateSizeGB: 0.47,
                memoryUsageGB: 0.5
            )
        ]
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        URL(fileURLWithPath: "/tmp/test-models/\(model.id)")
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return true
    }
}
