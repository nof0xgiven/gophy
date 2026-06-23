import Foundation
import Testing
@testable import Gophy

@Suite("ModelManagerViewModel Storage Tests")
@MainActor
struct ModelManagerViewModelStorageTests {
    @Test("Downloadable models with files but no loadable artifacts are reported as unavailable")
    func downloadableFilesPresentWithoutLoadableArtifactsAreReportedUnavailable() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyModelManagerViewModelStorageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageManager = StorageManager(baseDirectory: tempDirectory)
        let registry = DynamicModelRegistry(storageManager: storageManager)
        let model = try #require(
            registry.availableModels().first { $0.huggingFaceID == "BAAI/bge-large-en-v1.5" }
        )
        let modelDirectory = registry.downloadPath(for: model)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: modelDirectory.appendingPathComponent("pytorch_model.bin"))

        let viewModel = ModelManagerViewModel(
            registry: registry,
            downloadManager: ModelDownloadManager(registry: registry),
            storageManager: storageManager
        )

        #expect(viewModel.localStatus(for: model) == .unavailable)
    }

    @Test("Unsupported models with existing files are reported as unsupported")
    func unsupportedFilesPresentAreReportedUnsupported() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyModelManagerViewModelStorageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageManager = StorageManager(baseDirectory: tempDirectory)
        let registry = DynamicModelRegistry(storageManager: storageManager)
        let model = try #require(
            registry.availableModels().first { $0.huggingFaceID == "BAAI/bge-m3" }
        )
        let modelDirectory = registry.downloadPath(for: model)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: modelDirectory.appendingPathComponent("pytorch_model.bin"))

        let viewModel = ModelManagerViewModel(
            registry: registry,
            downloadManager: ModelDownloadManager(registry: registry),
            storageManager: storageManager
        )

        #expect(viewModel.localStatus(for: model) == .unsupported)
        #expect(viewModel.hasStoredFiles(for: model))
    }
}
