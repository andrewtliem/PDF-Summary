import Foundation

protocol SummarizationService {
    func summarizeAndTag(text: String, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String])
    func summarizeAndTag(fileURL: URL, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String])
    var supportsDirectFileProcessing: Bool { get }
}