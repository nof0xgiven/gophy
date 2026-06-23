import Foundation

enum OpenRouterModelCatalog {
    static func fetchModels(baseURL: URL, apiKey: String) async throws -> [CloudModelDefinition] {
        let textAndVisionModels = try await fetchTextGenerationModels(baseURL: baseURL, apiKey: apiKey)
        let embeddingModels = (try? await fetchEmbeddingModels(baseURL: baseURL, apiKey: apiKey)) ?? []
        return textAndVisionModels + embeddingModels
    }

    private static func fetchTextGenerationModels(baseURL: URL, apiKey: String) async throws -> [CloudModelDefinition] {
        let url = baseURL.appendingPathComponent("models")
        let data = try await fetchData(url: url, apiKey: apiKey)
        return try decodeModels(from: data) + decodeVisionModels(from: data)
    }

    private static func fetchEmbeddingModels(baseURL: URL, apiKey: String) async throws -> [CloudModelDefinition] {
        let url = baseURL
            .appendingPathComponent("embeddings")
            .appendingPathComponent("models")
        let data = try await fetchData(url: url, apiKey: apiKey)
        return try decodeEmbeddingModels(from: data)
    }

    private static func fetchData(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterModelCatalogError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterModelCatalogError.httpError(httpResponse.statusCode, String(body.prefix(200)))
        }

        return data
    }

    static func decodeModels(from data: Data) throws -> [CloudModelDefinition] {
        let response = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

        return response.data
            .filter { model in
                guard let architecture = model.architecture else {
                    return true
                }
                return architecture.inputModalities.contains("text")
                    && architecture.outputModalities.contains("text")
            }
            .map { model in
                CloudModelDefinition(
                    id: model.id,
                    name: model.name,
                    capability: .textGeneration,
                    contextWindow: model.contextLength,
                    inputPricePer1MTokens: model.pricing?.prompt.flatMap(pricePerMillionTokens),
                    outputPricePer1MTokens: model.pricing?.completion.flatMap(pricePerMillionTokens)
                )
            }
    }

    static func decodeEmbeddingModels(from data: Data) throws -> [CloudModelDefinition] {
        let response = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

        return response.data
            .filter { model in
                guard let architecture = model.architecture else {
                    return true
                }
                return architecture.inputModalities.contains("text")
                    && architecture.outputModalities.contains("embeddings")
            }
            .map { model in
                CloudModelDefinition(
                    id: model.id,
                    name: model.name,
                    capability: .embedding,
                    contextWindow: model.contextLength,
                    inputPricePer1MTokens: model.pricing?.prompt.flatMap(pricePerMillionTokens),
                    outputPricePer1MTokens: nil
                )
            }
    }

    static func decodeVisionModels(from data: Data) throws -> [CloudModelDefinition] {
        let response = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

        return response.data
            .filter { model in
                guard let architecture = model.architecture else {
                    return false
                }
                return architecture.inputModalities.contains("image")
                    && architecture.outputModalities.contains("text")
            }
            .map { model in
                CloudModelDefinition(
                    id: model.id,
                    name: "\(model.name) (Vision)",
                    capability: .vision,
                    contextWindow: model.contextLength,
                    inputPricePer1MTokens: model.pricing?.prompt.flatMap(pricePerMillionTokens),
                    outputPricePer1MTokens: model.pricing?.completion.flatMap(pricePerMillionTokens)
                )
            }
    }

    private static func pricePerMillionTokens(_ pricePerToken: String) -> Double? {
        guard let value = Double(pricePerToken) else { return nil }
        return value * 1_000_000
    }
}

enum OpenRouterModelCatalogError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid OpenRouter models response"
        case .httpError(let status, let body):
            return "OpenRouter models request failed with HTTP \(status): \(body)"
        }
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable {
    let id: String
    let name: String
    let contextLength: Int?
    let architecture: OpenRouterArchitecture?
    let pricing: OpenRouterPricing?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case contextLength = "context_length"
        case architecture
        case pricing
    }
}

private struct OpenRouterArchitecture: Decodable {
    let inputModalities: [String]
    let outputModalities: [String]

    private enum CodingKeys: String, CodingKey {
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
    }
}

private struct OpenRouterPricing: Decodable {
    let prompt: String?
    let completion: String?
}
