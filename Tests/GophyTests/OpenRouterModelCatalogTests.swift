import Foundation
import Testing
@testable import Gophy

@Suite("OpenRouter Model Catalog Tests")
struct OpenRouterModelCatalogTests {
    @Test("Decodes OpenRouter models response into text generation cloud models")
    func decodesOpenRouterModelsResponse() throws {
        let json = """
        {
          "data": [
            {
              "id": "openai/gpt-4",
              "name": "GPT-4",
              "context_length": 8192,
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["text"]
              },
              "pricing": {
                "prompt": "0.00003",
                "completion": "0.00006"
              }
            },
            {
              "id": "image/model",
              "name": "Image Model",
              "context_length": 4096,
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["image"]
              },
              "pricing": {
                "prompt": "0.00001",
                "completion": "0"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try OpenRouterModelCatalog.decodeModels(from: json)

        #expect(models.count == 1)
        #expect(models.first?.id == "openai/gpt-4")
        #expect(models.first?.name == "GPT-4")
        #expect(models.first?.capability == .textGeneration)
        #expect(models.first?.contextWindow == 8192)
        #expect(models.first?.inputPricePer1MTokens == 30)
        #expect(models.first?.outputPricePer1MTokens == 60)
    }

    @Test("Decodes OpenRouter embeddings models response into embedding cloud models")
    func decodesOpenRouterEmbeddingModelsResponse() throws {
        let json = """
        {
          "data": [
            {
              "id": "openai/text-embedding-3-small",
              "name": "Text Embedding 3 Small",
              "context_length": 8192,
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["embeddings"]
              },
              "pricing": {
                "prompt": "0.00000002",
                "completion": "0"
              }
            },
            {
              "id": "openai/gpt-4",
              "name": "GPT-4",
              "context_length": 8192,
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["text"]
              },
              "pricing": {
                "prompt": "0.00003",
                "completion": "0.00006"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try OpenRouterModelCatalog.decodeEmbeddingModels(from: json)

        #expect(models.count == 1)
        #expect(models.first?.id == "openai/text-embedding-3-small")
        #expect(models.first?.capability == .embedding)
        #expect(models.first?.contextWindow == 8192)
        #expect(models.first?.inputPricePer1MTokens == 0.02)
        #expect(models.first?.outputPricePer1MTokens == nil)
    }

    @Test("Decodes OpenRouter image input models into vision cloud models")
    func decodesOpenRouterVisionModelsResponse() throws {
        let json = """
        {
          "data": [
            {
              "id": "openai/gpt-4o",
              "name": "GPT-4o",
              "context_length": 128000,
              "architecture": {
                "input_modalities": ["text", "image"],
                "output_modalities": ["text"]
              },
              "pricing": {
                "prompt": "0.0000025",
                "completion": "0.00001"
              }
            },
            {
              "id": "text-only/model",
              "name": "Text Only",
              "context_length": 8192,
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["text"]
              },
              "pricing": {
                "prompt": "0.000001",
                "completion": "0.000002"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try OpenRouterModelCatalog.decodeVisionModels(from: json)

        #expect(models.count == 1)
        #expect(models.first?.id == "openai/gpt-4o")
        #expect(models.first?.name == "GPT-4o (Vision)")
        #expect(models.first?.capability == .vision)
        #expect(models.first?.contextWindow == 128000)
    }
}
