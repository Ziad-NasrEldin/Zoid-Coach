import Foundation
import Vision
import ZoidCoachCore

public protocol ScreenshotTextRecognizing: Sendable {
    func recognize(in imageURL: URL) async throws -> ScreenshotOCRResult
}

public struct ScreenshotTextRecognizer: ScreenshotTextRecognizing, Sendable {
    public init() {}

    public func recognize(in imageURL: URL) async throws -> ScreenshotOCRResult {
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "ar"]
            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            try handler.perform([request])
            let blocks = (request.results ?? []).compactMap { observation -> OCRTextBlock? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                let localeHint = candidate.string.range(of: "[\\p{Arabic}]", options: .regularExpression) == nil ? "en" : "ar"
                return OCRTextBlock(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    boundingBox: NormalizedBoundingBox(x: box.origin.x, y: box.origin.y, width: box.size.width, height: box.size.height),
                    localeHint: localeHint
                )
            }
            return ScreenshotOCRResult(blocks: blocks)
        }.value
    }

    public func recognizeText(in imageURL: URL) async throws -> String {
        try await recognize(in: imageURL).text
    }
}
