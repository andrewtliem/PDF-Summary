import Foundation
import PDFKit
import Vision
import AppKit

enum ContentProcessorError: Error, LocalizedError {
    case failedToLoadPDF
    case failedToLoadImage
    case failedToCreateContext
    case failedToCreateImage
    case ocrFailed(Error)
    case noRecognizedText
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .failedToLoadPDF:
            return "Failed to load the PDF document."
        case .failedToLoadImage:
            return "Failed to load the image file."
        case .failedToCreateContext:
            return "Could not create a graphics context for rendering."
        case .failedToCreateImage:
            return "Could not create an image from the PDF page."
        case .ocrFailed(let error):
            return "OCR processing failed: \(error.localizedDescription)"
        case .noRecognizedText:
            return "No recognizable text was found in the content."
        case .unsupportedFileType:
            return "The selected file type is not supported."
        }
    }
}

class ContentProcessor {
    private let supportedExtensions = ["pdf", "png", "jpg", "jpeg", "tiff"]

    func extractText(from url: URL, language: String) async throws -> (String, URL) {
        let fileExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw ContentProcessorError.unsupportedFileType
        }

        let fullText: String
        if fileExtension == "pdf" {
            fullText = try await extractTextFromPDF(from: url, language: language)
        } else {
            fullText = try await extractTextFromImage(from: url, language: language)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("txt")
        
        try fullText.write(to: tempURL, atomically: true, encoding: .utf8)

        return (fullText, tempURL)
    }

    private func extractTextFromPDF(from url: URL, language: String) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ContentProcessorError.failedToLoadPDF
        }

        var fullText = ""
        for i in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }

            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText.append(text + "\n")
            } else {
                let ocrText = try await extractTextFromPDFPageAsImage(from: page, language: language)
                fullText.append(ocrText + "\n")
            }
        }
        return fullText
    }

    private func extractTextFromImage(from url: URL, language: String) async throws -> String {
        guard let nsImage = NSImage(contentsOf: url) else {
            throw ContentProcessorError.failedToLoadImage
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ContentProcessorError.failedToCreateImage
        }
        return try await performOCR(on: cgImage, language: language)
    }

    private func extractTextFromPDFPageAsImage(from page: PDFPage, language: String) async throws -> String {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ContentProcessorError.failedToCreateContext
        }

        context.interpolationQuality = .high
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        guard let pageImage = context.makeImage() else {
            throw ContentProcessorError.failedToCreateImage
        }

        return try await performOCR(on: pageImage, language: language)
    }

    private func performOCR(on image: CGImage, language: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { (request, error) in
                if let error = error {
                    continuation.resume(throwing: ContentProcessorError.ocrFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ContentProcessorError.noRecognizedText)
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            let languages = language.lowercased() == "indonesian" ? ["id-ID", "en-US"] : ["en-US", "id-ID"]
            request.recognitionLanguages = languages
            request.recognitionLevel = .accurate

            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(throwing: ContentProcessorError.ocrFailed(error))
            }
        }
    }
}