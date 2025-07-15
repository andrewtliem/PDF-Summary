import Foundation
import SwiftUI
import PDFKit

// MARK: - Codable Structs for Ollama API

struct OllamaRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
    }
}

struct OllamaVisionMessage: Codable {
    let role: String
    let content: String
    let images: [String]?
}

struct OllamaVisionRequest: Codable {
    let model: String
    let messages: [OllamaVisionMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
    }
}

struct OllamaResponse: Codable {
    let model: String
    let createdAt: String
    let message: Message
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case createdAt = "created_at"
    }
}

// MARK: - Error Enum

enum OllamaServiceError: Error, LocalizedError {
    case apiURLNotSet
    case requestFailed(Error)
    case noDataReceived
    case decodingFailed(Error)
    case noContent
    case responseParsingFailed
    case fileNotSupported
    case imageProcessingFailed

    var errorDescription: String? {
        switch self {
        case .apiURLNotSet:
            return "Ollama API URL is not set."
        case .requestFailed(let error):
            return "Ollama API request failed: \(error.localizedDescription)"
        case .noDataReceived:
            return "No data received from Ollama API."
        case .decodingFailed(let error):
            return "Failed to decode Ollama response: \(error.localizedDescription)"
        case .noContent:
            return "Could not find content in the Ollama response."
        case .responseParsingFailed:
            return "Failed to parse summary and keywords from the Ollama response."
        case .fileNotSupported:
            return "File type not supported for direct processing."
        case .imageProcessingFailed:
            return "Failed to process image for vision model."
        }
    }
}

// MARK: - OllamaService

class OllamaService: SummarizationService {
    @AppStorage("ollamaAPIURL") private var apiURLString: String = "http://localhost:11434/api/chat"
    
    
    private let commonWords = Set(["the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "who", "boy", "did", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see", "two", "who", "oil", "sit", "set", "run", "eat", "far", "sea", "eye", "big", "box", "got", "yet", "way", "too", "any", "may", "say", "she", "use", "her", "now", "find", "only", "come", "made", "over", "also", "back", "call", "came", "each", "good", "here", "just", "know", "last", "left", "life", "long", "look", "make", "most", "move", "must", "name", "need", "next", "open", "part", "play", "said", "same", "seem", "show", "side", "take", "tell", "turn", "want", "ways", "well", "went", "were", "what", "when", "will", "work", "year", "your", "being", "every", "great", "might", "shall", "still", "those", "under", "where", "after", "again", "before", "found", "going", "house", "never", "other", "right", "small", "sound", "still", "such", "these", "thing", "think", "three", "through", "time", "very", "water", "words", "world", "years", "young", "about", "above", "could", "first", "place", "right", "should", "their", "there", "these", "thing", "think", "three", "through", "time", "very", "water", "words", "world", "years", "young", "summary", "keywords", "document", "text", "analysis", "content", "file", "page", "section", "chapter", "paragraph", "sentence", "word", "information", "data", "example", "point", "points", "application", "questions", "discussion", "prayer", "lesson", "story", "people"])
    
    var supportsDirectFileProcessing: Bool {
        return true
    }
    
    func summarizeAndTag(fileURL: URL, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String]) {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        if ["png", "jpg", "jpeg", "tiff"].contains(fileExtension) {
            return try await summarizeAndTagVision(fileURL: fileURL, model: model, customPrompt: customPrompt)
        } else if fileExtension == "pdf" {
            // For PDF, we'll extract text and process it as text
            guard let pdfDocument = PDFDocument(url: fileURL) else {
                throw OllamaServiceError.fileNotSupported
            }
            let fullText = pdfDocument.string ?? ""
            return try await summarizeAndTag(text: fullText, model: model, customPrompt: customPrompt)
        } else {
            throw OllamaServiceError.fileNotSupported
        }
    }
    
    func summarizeAndTagVision(fileURL: URL, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String]) {
        guard let apiURL = URL(string: apiURLString) else {
            throw OllamaServiceError.apiURLNotSet
        }
        
        try await testOllamaConnection(apiURL: apiURL)
        
        let visionPrompt = customPrompt.isEmpty ? "Summarize this image and provide 4 keywords." : customPrompt
        
        let base64Image = try await convertToBase64(fileURL: fileURL)
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0
        
        let payload = OllamaVisionRequest(
            model: model,
            messages: [OllamaVisionMessage(role: "user", content: visionPrompt, images: [base64Image])],
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(payload)
        
        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch {
            throw OllamaServiceError.requestFailed(error)
        }
        
        let ollamaResponse: OllamaResponse
        do {
            ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        } catch {
            throw OllamaServiceError.decodingFailed(error)
        }
        
        let content = ollamaResponse.message.content
        let (summary, keywords) = parseOllamaResponse(content)
        
        guard let finalSummary = summary, !keywords.isEmpty else {
            throw OllamaServiceError.responseParsingFailed
        }
        
        return (finalSummary, keywords)
    }
    
    private func testOllamaConnection(apiURL: URL) async throws {
        let baseURL = URL(string: "http://localhost:11434")!
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ Ollama service is running")
            } else {
                print("⚠️ Ollama service returned non-200 status")
            }
        } catch {
            throw OllamaServiceError.requestFailed(NSError(domain: "OllamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to Ollama. Make sure Ollama is running with: 'ollama serve'"]))
        }
    }
    
    func summarizeAndTag(text: String, model: String, customPrompt: String) async throws -> (summary: String, keywords: [String]) {
        guard let apiURL = URL(string: apiURLString) else {
            throw OllamaServiceError.apiURLNotSet
        }

        let truncatedText = truncateText(text)
        // Use a dedicated, clear prompt for Ollama
        let textPrompt = """
You are an expert text analyzer. Read the following text carefully. Provide a clear, concise, and well-structured summary in 3–4 short paragraphs, highlighting the main ideas and important details without repeating phrases or filler words. Your response must be a very details. 

Text to analyze:
\(truncatedText)
"""

        let result = try await processTextRequest(apiURL: apiURL, model: model, prompt: textPrompt)
        return result
    }

    private func processTextRequest(apiURL: URL, model: String, prompt: String) async throws -> (summary: String, keywords: [String]) {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0
        
        let payload = OllamaRequest(
            model: model,
            messages: [Message(role: "user", content: prompt)],
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch {
            throw OllamaServiceError.requestFailed(error)
        }

        let ollamaResponse: OllamaResponse
        do {
            ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        } catch {
            throw OllamaServiceError.decodingFailed(error)
        }

        let content = ollamaResponse.message.content
        let (summary, keywords) = parseOllamaResponse(content)

        guard let finalSummary = summary, !keywords.isEmpty else {
            throw OllamaServiceError.responseParsingFailed
        }

        return (finalSummary, keywords)
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
    
    private func convertToBase64(fileURL: URL) async throws -> String {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        if fileExtension == "pdf" {
            return try await convertPDFToBase64(fileURL: fileURL)
        } else {
            return try convertImageToBase64(fileURL: fileURL)
        }
    }
    
    private func convertImageToBase64(fileURL: URL) throws -> String {
        guard let nsImage = NSImage(contentsOf: fileURL) else {
            throw OllamaServiceError.imageProcessingFailed
        }
        
        let resizedImage = resizeImage(nsImage, maxSize: 1024)
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw OllamaServiceError.imageProcessingFailed
        }
        
        return jpegData.base64EncodedString()
    }
    
    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let originalSize = image.size
        let aspectRatio = originalSize.width / originalSize.height
        
        var newSize: NSSize
        if originalSize.width > originalSize.height {
            newSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }
        
        if originalSize.width <= maxSize && originalSize.height <= maxSize {
            return image
        }
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        
        return newImage
    }
    
    private func convertPDFToBase64(fileURL: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: fileURL),
              let firstPage = pdfDocument.page(at: 0) else {
            throw OllamaServiceError.imageProcessingFailed
        }
        
        let pageRect = firstPage.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)
        
        let maxDimension = 1024
        let finalWidth = min(width, maxDimension)
        let finalHeight = min(height, maxDimension)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: nil, width: finalWidth, height: finalHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OllamaServiceError.imageProcessingFailed
        }
        
        context.interpolationQuality = .high
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(finalHeight))
        context.scaleBy(x: CGFloat(finalWidth) / pageRect.width, y: -CGFloat(finalHeight) / pageRect.height)
        firstPage.draw(with: .mediaBox, to: context)
        context.restoreGState()
        
        guard let pageImage = context.makeImage() else {
            throw OllamaServiceError.imageProcessingFailed
        }
        
        let nsImage = NSImage(cgImage: pageImage, size: NSSize(width: finalWidth, height: finalHeight))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw OllamaServiceError.imageProcessingFailed
        }
        
        return jpegData.base64EncodedString()
    }
    
    private func parseOllamaResponse(_ content: String) -> (summary: String?, keywords: [String]) {
        var summary: String?
        var keywords: [String] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            
            if lowercased.starts(with: "summary:") {
                var summaryText = trimmed.replacingOccurrences(of: "summary:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !summaryText.isEmpty {
                    summary = summaryText
                    
                    for nextIndex in (index + 1)..<lines.count {
                        let nextLine = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                        if nextLine.lowercased().starts(with: "keywords:") || nextLine.isEmpty {
                            break
                        }
                        summary! += " " + nextLine
                    }
                }
            }
            
            if lowercased.starts(with: "keywords:") {
                let keywordText = trimmed.replacingOccurrences(of: "keywords:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                
                keywords = keywordText.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .map { $0.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "") }
                    .map { $0.replacingOccurrences(of: "\"", with: "") }
                    .filter { !$0.isEmpty }
                    .prefix(4)
                    .map { String($0) }
            }
        }
        
        if summary == nil {
            let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanContent.isEmpty {
                summary = cleanContent
            }
            keywords = extractEnhancedKeywords(from: content)
        }
        
        if keywords.isEmpty {
            keywords = extractEnhancedKeywords(from: content)
        }
        
        return (summary, keywords)
    }
    
    private func extractEnhancedKeywords(from content: String) -> [String] {
        let text = content.lowercased()
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
            .filter { !commonWords.contains($0) }
        
        let wordCount = NSCountedSet(array: words)
        let sortedWords = wordCount.allObjects.compactMap { $0 as? String }
            .sorted { wordCount.count(for: $0) > wordCount.count(for: $1) }
        
        return Array(sortedWords.prefix(4))
    }
}
