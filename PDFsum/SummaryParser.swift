import Foundation

class SummaryParser {
    static func parseSummaryAndKeywords(from content: String) -> (summary: String?, keywords: [String]?) {
        if let jsonString = findJSONString(in: content) {
            if let result = tryParseJSON(from: jsonString) {
                return result
            }
        }
        
        print("Failed to parse content as JSON, falling back to plain text parsing.")
        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedContent.isEmpty {
            return (cleanedContent, extractKeywordsFromText(cleanedContent))
        }
        
        return (nil, nil)
    }
    
    private static func findJSONString(in content: String) -> String? {
        guard let startRange = content.range(of: "{"), let endRange = content.range(of: "}", options: .backwards) else {
            return nil
        }
        guard startRange.lowerBound < endRange.upperBound else {
            return nil
        }
        return String(content[startRange.lowerBound...endRange.lowerBound])
    }

    private static func tryParseJSON(from content: String) -> (summary: String?, keywords: [String]?)? {
        guard let data = content.data(using: .utf8) else { return nil }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                var allStrings: [String] = []
                var keywords: [String] = []
                
                extractAllStringsAndKeywords(in: json, allStrings: &allStrings, keywords: &keywords)
                
                // Find the longest string and assume it's the summary
                let longestString = allStrings.max(by: { $1.count > $0.count }) ?? ""
                
                if !longestString.isEmpty {
                    // If no keywords were explicitly found, generate them
                    if keywords.isEmpty {
                        keywords = extractKeywordsFromText(longestString)
                    }
                    return (longestString, keywords)
                }
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
        
        return nil
    }
    
    private static func extractAllStringsAndKeywords(in json: Any, allStrings: inout [String], keywords: inout [String]) {
        if let dict = json as? [String: Any] {
            for (key, value) in dict {
                if key.lowercased() == "keywords", let stringArray = value as? [String] {
                    keywords.append(contentsOf: stringArray)
                } else if let stringValue = value as? String {
                    allStrings.append(stringValue)
                } else {
                    extractAllStringsAndKeywords(in: value, allStrings: &allStrings, keywords: &keywords)
                }
            }
        } else if let array = json as? [Any] {
            for item in array {
                extractAllStringsAndKeywords(in: item, allStrings: &allStrings, keywords: &keywords)
            }
        }
    }
    
    private static func extractKeywordsFromText(_ text: String) -> [String] {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
        let commonWords = Set(["the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "who", "summary", "keywords", "document", "text", "content", "lesson", "this", "with", "from", "what", "that", "into", "their", "these", "they", "were", "his", "her", "and", "the", "was", "for", "are", "with", "as", "his", "on", "at", "by", "an", "to", "in", "is", "it", "of", "that", "this", "was", "were", "will", "with"])
        let filteredWords = words.filter { !commonWords.contains($0) }
        let wordCount = NSCountedSet(array: filteredWords)
        let sortedWords = wordCount.allObjects
            .compactMap { $0 as? String }
            .sorted { wordCount.count(for: $0) > wordCount.count(for: $1) }
        return Array(sortedWords.prefix(4))
    }
}