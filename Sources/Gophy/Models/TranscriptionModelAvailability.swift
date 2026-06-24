import Foundation

enum TranscriptionModelAvailability {
    static func usesLocalSTT(defaults: UserDefaults = .standard) -> Bool {
        (defaults.string(forKey: "selectedSTTProvider") ?? "local") == "local"
    }

    static func downloadedLocalSTTModel(
        registry: any ModelRegistryProtocol = ModelRegistry.shared,
        defaults: UserDefaults = .standard
    ) -> ModelDefinition? {
        let selectedId = defaults.string(forKey: "selectedSTTModelId") ?? "whisperkit-large-v3-turbo"
        let models = registry.availableModels().filter { $0.type == .stt && $0.isDownloadable }

        if let selected = models.first(where: { $0.id == selectedId }),
           registry.isDownloaded(selected) {
            return selected
        }

        return models.first { registry.isDownloaded($0) }
    }
}
