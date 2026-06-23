import Testing
import Foundation
@testable import Gophy

@Suite("SettingsViewModel Model Selection Tests")
@MainActor
struct SettingsViewModelModelSelectionTests {

    @Test("Updating text gen model persists to UserDefaults")
    func testUpdateTextGenModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-textgen-model"
        viewModel.updateSelectedTextGenModel(testModelId)

        let saved = defaults.string(forKey: "selectedTextGenModelId")
        #expect(saved == testModelId, "Text gen model should be persisted")
        #expect(viewModel.selectedTextGenModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedTextGenModelId")
    }

    @Test("Updating STT model persists to UserDefaults")
    func testUpdateSTTModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-stt-model"
        viewModel.updateSelectedSTTModel(testModelId)

        let saved = defaults.string(forKey: "selectedSTTModelId")
        #expect(saved == testModelId, "STT model should be persisted")
        #expect(viewModel.selectedSTTModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedSTTModelId")
    }

    @Test("Updating OCR model persists to UserDefaults")
    func testUpdateOCRModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-ocr-model"
        viewModel.updateSelectedOCRModel(testModelId)

        let saved = defaults.string(forKey: "selectedOCRModelId")
        #expect(saved == testModelId, "OCR model should be persisted")
        #expect(viewModel.selectedOCRModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedOCRModelId")
    }

    @Test("Updating embedding model persists to UserDefaults")
    func testUpdateEmbeddingModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-embedding-model"
        viewModel.updateSelectedEmbeddingModel(testModelId)

        let saved = defaults.string(forKey: "selectedEmbeddingModelId")
        #expect(saved == testModelId, "Embedding model should be persisted")
        #expect(viewModel.selectedEmbeddingModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedEmbeddingModelId")
    }

    @Test("availableSTTModels returns only STT models")
    func testAvailableSTTModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let sttModels = viewModel.availableSTTModels
        #expect(!sttModels.isEmpty, "Should have STT models")

        for model in sttModels {
            #expect(model.type == .stt, "All models should be STT type")
        }
    }

    @Test("availableTextGenModels returns only textGen models")
    func testAvailableTextGenModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let textGenModels = viewModel.availableTextGenModels
        #expect(!textGenModels.isEmpty, "Should have text gen models")

        for model in textGenModels {
            #expect(model.type == .textGen, "All models should be textGen type")
        }
    }

    @Test("availableOCRModels returns only OCR models")
    func testAvailableOCRModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let ocrModels = viewModel.availableOCRModels
        #expect(!ocrModels.isEmpty, "Should have OCR models")

        for model in ocrModels {
            #expect(model.type == .ocr, "All models should be OCR type")
        }
    }

    @Test("availableEmbeddingModels returns only embedding models")
    func testAvailableEmbeddingModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let embeddingModels = viewModel.availableEmbeddingModels
        #expect(!embeddingModels.isEmpty, "Should have embedding models")

        for model in embeddingModels {
            #expect(model.type == .embedding, "All models should be embedding type")
        }
    }

    @Test("OpenRouter is selectable for embeddings when configured")
    func testOpenRouterSelectableForEmbeddingsWhenConfigured() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()
        let keychain = SettingsViewModelTestKeychain()
        try keychain.save(apiKey: "sk-test", for: "openrouter")

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry,
            keychainService: keychain
        )

        let embeddingProviders = viewModel.configuredProviderConfigs(for: .embedding)
        #expect(embeddingProviders.contains { $0.id == "openrouter" })

        let defaultModelId = viewModel.availableCloudModels(for: .embedding, providerId: "openrouter").first?.id ?? ""
        viewModel.selectCloudProvider(for: .embedding, providerId: "openrouter", modelId: defaultModelId)

        #expect(viewModel.selectedProviderIdFor(.embedding) == "openrouter")
        #expect(viewModel.selectedModelIdFor(.embedding).contains("embedding"))
    }

    @Test("OpenRouter is selectable for vision when configured")
    func testOpenRouterSelectableForVisionWhenConfigured() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()
        let keychain = SettingsViewModelTestKeychain()
        try keychain.save(apiKey: "sk-test", for: "openrouter")

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry,
            keychainService: keychain
        )

        let visionProviders = viewModel.configuredProviderConfigs(for: .vision)
        #expect(visionProviders.contains { $0.id == "openrouter" })

        let defaultModelId = viewModel.availableCloudModels(for: .vision, providerId: "openrouter").first?.id ?? ""
        viewModel.selectCloudProvider(for: .vision, providerId: "openrouter", modelId: defaultModelId)

        #expect(viewModel.selectedProviderIdFor(.vision) == "openrouter")
        #expect(!viewModel.selectedModelIdFor(.vision).isEmpty)
    }

    @Test("System audio defaults to enabled for new users")
    func testSystemAudioDefaultsToEnabled() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "systemAudioEnabled")

        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        #expect(viewModel.systemAudioEnabled == true, "System audio should default to enabled when unset")

        defaults.removeObject(forKey: "systemAudioEnabled")
    }

    @Test("Setting system audio persists explicit value")
    func testSetSystemAudioEnabledPersistsExplicitValue() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "systemAudioEnabled")

        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        viewModel.setSystemAudioEnabled(false)
        #expect(viewModel.systemAudioEnabled == false, "ViewModel should reflect disabled system audio")
        #expect(defaults.object(forKey: "systemAudioEnabled") as? Bool == false, "System audio setting should persist false")

        viewModel.setSystemAudioEnabled(true)
        #expect(viewModel.systemAudioEnabled == true, "ViewModel should reflect enabled system audio")
        #expect(defaults.object(forKey: "systemAudioEnabled") as? Bool == true, "System audio setting should persist true")

        defaults.removeObject(forKey: "systemAudioEnabled")
    }
}

private final class SettingsViewModelTestKeychain: KeychainServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(apiKey: String, for providerId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[providerId] = apiKey
    }

    func retrieve(for providerId: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[providerId]
    }

    func delete(for providerId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: providerId)
    }

    func listProviderIds() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(values.keys)
    }
}
