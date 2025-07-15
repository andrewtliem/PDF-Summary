import Foundation
import SwiftUI

// MARK: - Codable Structs for OpenAI API

struct OpenAIRequest: Codable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

struct OpenAIResponse: Codable {
    struct Choice: Codable {
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Error Enum

enum OpenAIServiceError: Error, LocalizedError {
    case apiKeyNotSet
    case requestFailed(Error)
    case noDataReceived
    case decodingFailed(Error)
    case noContent
    case responseParsingFailed

    var errorDescription: String? {
        switch self {
        case .apiKeyNotSet:
            return "OpenAI API Key is not set."
        case .requestFailed(let error):
            return "API request failed: \(error.localizedDescription)"
        case .noDataReceived:
            return "No data received from API."
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noContent:
            return "Could not find content in the API response."
        case .responseParsingFailed:
            return "Failed to parse summary and keywords from the response."
        }
    }
}

// MARK: - OpenAIService

class OpenAIService: SummarizationService {
    @AppStorage("openAIKey") private var apiKey: String = ""
    private let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    
    var supportsDirectFileProcessing: Bool {
        return false // OpenAI uses OCR workflow
    }
    
    func summarizeAndTag(fileURL: URL, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String]) {
        throw OpenAIServiceError.requestFailed(NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Direct file processing not supported. Use text-based processing instead."]))
    }

    func summarizeAndTag(text: String, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String]) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIServiceError.apiKeyNotSet
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let truncatedText = truncateText(text)
        var finalPrompt = customPrompt
        if !finalPrompt.lowercased().contains("json") {
            finalPrompt += "\n\nIMPORTANT: Your entire response must be a valid JSON object."
        }
        finalPrompt += "\n\nText to process:\n\(truncatedText)"
        
        let payload = OpenAIRequest(
            model: model,
            messages: [Message(role: "user", content: finalPrompt)],
            maxTokens: 1500,
            responseFormat: ResponseFormat(type: "json_object")
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
            if let raw = String(data: data, encoding: .utf8) {
                print("OpenAI raw response: \(raw)")
            }
        } catch {
            throw OpenAIServiceError.requestFailed(error)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            if message.contains("response_format is not valid") {
                 throw OpenAIServiceError.requestFailed(NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "The selected model does not support JSON mode. Please select a compatible model like gpt-4-turbo or gpt-3.5-turbo-0125."]))
            }
            throw OpenAIServiceError.requestFailed(NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        let openAIResponse: OpenAIResponse
        do {
            openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingFailed(error)
        }

        guard let content = openAIResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noContent
        }

        let (summary, keywords) = SummaryParser.parseSummaryAndKeywords(from: content)

        guard let finalSummary = summary, let finalKeywords = keywords else {
            print("Failed to parse the JSON content returned by OpenAI: \(content)")
            throw OpenAIServiceError.responseParsingFailed
        }

        return (finalSummary, finalKeywords)
    }
    
    private func truncateText(_ text: String, maxLength: Int = 8000) -> String {
        if text.count <= maxLength {
            return text
        }
        
        let halfLength = maxLength / 2
        let prefix = text.prefix(halfLength)
        let suffix = text.suffix(halfLength)
        
        return "\(prefix)...\(suffix)"
    }
}