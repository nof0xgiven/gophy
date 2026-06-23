import Foundation
import os

private let registryLogger = Logger(subsystem: "com.gophy.app", category: "ModelRegistry")

public protocol ModelRegistryProtocol: Sendable {
    func availableModels() -> [ModelDefinition]
    func isDownloaded(_ model: ModelDefinition) -> Bool
    func downloadPath(for model: ModelDefinition) -> URL
}

public final class ModelRegistry: ModelRegistryProtocol, Sendable {
    public static let shared: ModelRegistryProtocol = DynamicModelRegistry()

    private let storageManager: StorageManager

    public init(storageManager: StorageManager = .shared) {
        self.storageManager = storageManager
    }

    public func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "whisperkit-large-v3-turbo",
                name: "WhisperKit large-v3-turbo",
                type: .stt,
                huggingFaceID: "argmaxinc/whisperkit-coreml-large-v3-turbo",
                approximateSizeGB: 1.5,
                memoryUsageGB: 1.5
            ),
            ModelDefinition(
                id: "qwen2.5-7b-instruct-4bit",
                name: "Qwen2.5 7B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                approximateSizeGB: 4.0,
                memoryUsageGB: 4.0
            ),
            ModelDefinition(
                id: "qwen3-8b-instruct-4bit",
                name: "Qwen3 8B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen3-8B-4bit",
                approximateSizeGB: 4.5,
                memoryUsageGB: 4.5
            ),
            ModelDefinition(
                id: "qwen2.5-vl-7b-instruct-4bit",
                name: "Qwen2.5-VL 7B Instruct 4-bit",
                type: .ocr,
                huggingFaceID: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                approximateSizeGB: 5.3,
                memoryUsageGB: 5.5
            ),
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

    public func isDownloaded(_ model: ModelDefinition) -> Bool {
        for path in ModelStorageLocator.candidatePaths(for: model, storageManager: storageManager) {
            registryLogger.info("isDownloaded(\(model.id, privacy: .public)): checking \(path.path, privacy: .public)")
            if isModelAt(path) {
                registryLogger.info("isDownloaded(\(model.id, privacy: .public)): found at \(path.path, privacy: .public)")
                return true
            }
        }

        registryLogger.warning("isDownloaded(\(model.id, privacy: .public)): NOT FOUND at any path")
        return false
    }

    private func isModelAt(_ path: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path.path) else {
            registryLogger.info("isModelAt: directory does not exist: \(path.path, privacy: .public)")
            return false
        }

        let hasArtifact = ModelFileDetector.containsUsableModelArtifact(at: path)
        if hasArtifact {
            registryLogger.info("isModelAt: found usable model artifact under \(path.lastPathComponent, privacy: .public)")
        } else {
            registryLogger.info("isModelAt: no usable model artifact found at \(path.lastPathComponent, privacy: .public)")
        }
        return hasArtifact
    }

    public func downloadPath(for model: ModelDefinition) -> URL {
        if let usablePath = ModelStorageLocator.usableModelPath(for: model, storageManager: storageManager) {
            return usablePath
        }
        return storageManager.modelsDirectory.appendingPathComponent(model.id)
    }
}
