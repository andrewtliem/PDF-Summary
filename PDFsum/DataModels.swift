import Foundation
import SwiftData

// MARK: - Persistent Document Summary Model
@Model
final class PersistentContentSummary {
    @Attribute(.unique) var id: UUID
    var filePath: String
    var fileName: String
    var summary: String?
    var keywords: [String]
    var textFileURL: String? // Store as string path
    var dateProcessed: Date
    var isProcessing: Bool
    var processingProgress: String
    
    init(
        id: UUID = UUID(),
        filePath: String,
        fileName: String,
        summary: String? = nil,
        keywords: [String] = [],
        textFileURL: String? = nil,
        dateProcessed: Date = Date(),
        isProcessing: Bool = false,
        processingProgress: String = ""
    ) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.summary = summary
        self.keywords = keywords
        self.textFileURL = textFileURL
        self.dateProcessed = dateProcessed
        self.isProcessing = isProcessing
        self.processingProgress = processingProgress
    }
    
    // Convert to ContentSummary for UI
    func toContentSummary() -> ContentSummary {
        let fileURL = URL(fileURLWithPath: filePath)
        let textURL = textFileURL.map { URL(fileURLWithPath: $0) }
        
        return ContentSummary(
            id: id,
            url: fileURL,
            summary: summary,
            keywords: keywords.isEmpty ? nil : keywords,
            textFileURL: textURL,
            isProcessing: isProcessing,
            processingProgress: processingProgress
        )
    }
    
    // Update from ContentSummary
    func update(from contentSummary: ContentSummary) {
        self.filePath = contentSummary.url.path
        self.fileName = contentSummary.url.lastPathComponent
        self.summary = contentSummary.summary
        self.keywords = contentSummary.keywords ?? []
        self.textFileURL = contentSummary.textFileURL?.path
        self.isProcessing = contentSummary.isProcessing
        self.processingProgress = contentSummary.processingProgress
        self.dateProcessed = Date()
    }
}

// MARK: - Persistent App Settings Model
@Model
final class AppSettings {
    @Attribute(.unique) var id: String = "main"
    var monitoredFolderPaths: [String]
    var useOllama: Bool
    var openAIAPIKey: String
    var openAIModel: String
    var ollamaModel: String
    var ollamaAPIURL: String
    var ollamaProcessingMode: String
    var customPrompt: String
    var ocrLanguage: String
    var lastUpdated: Date
    
    init(
        monitoredFolderPaths: [String] = [],
        useOllama: Bool = true,
        openAIAPIKey: String = "",
        openAIModel: String = "gpt-4-turbo",
        ollamaModel: String = "llama3.1:8b",
        ollamaAPIURL: String = "http://localhost:11434/api/chat",
        ollamaProcessingMode: String = "vision",
        customPrompt: String = "",
        ocrLanguage: String = "en",
        lastUpdated: Date = Date()
    ) {
        self.monitoredFolderPaths = monitoredFolderPaths
        self.useOllama = useOllama
        self.openAIAPIKey = openAIAPIKey
        self.openAIModel = openAIModel
        self.ollamaModel = ollamaModel
        self.ollamaAPIURL = ollamaAPIURL
        self.ollamaProcessingMode = ollamaProcessingMode
        self.customPrompt = customPrompt
        self.ocrLanguage = ocrLanguage
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Extension for ContentSummary to create PersistentContentSummary
extension ContentSummary {
    func toPersistentModel() -> PersistentContentSummary {
        return PersistentContentSummary(
            id: id,
            filePath: url.path,
            fileName: url.lastPathComponent,
            summary: summary,
            keywords: keywords ?? [],
            textFileURL: textFileURL?.path,
            dateProcessed: Date(),
            isProcessing: isProcessing,
            processingProgress: processingProgress
        )
    }
} 