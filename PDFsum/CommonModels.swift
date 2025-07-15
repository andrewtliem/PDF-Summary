import Foundation

struct Message: Codable {
    let role: String
    let content: String
}

struct SummaryResponse: Codable {
    let summary: String
    let keywords: [String]
}

struct ResponseFormat: Codable {
    let type: String
}