import Foundation

public struct NormalizedBoundingBox: Equatable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct OCRTextBlock: Equatable, Codable, Sendable {
    public let text: String
    public let confidence: Double
    public let boundingBox: NormalizedBoundingBox
    public let localeHint: String?

    public init(text: String, confidence: Double, boundingBox: NormalizedBoundingBox, localeHint: String?) {
        self.text = text
        self.confidence = min(max(confidence, 0), 1)
        self.boundingBox = boundingBox
        self.localeHint = localeHint
    }
}

public struct ScreenshotOCRResult: Equatable, Codable, Sendable {
    public let blocks: [OCRTextBlock]
    public let recognizerVersion: Int

    public init(blocks: [OCRTextBlock], recognizerVersion: Int = 1) {
        self.blocks = blocks
        self.recognizerVersion = recognizerVersion
    }

    public var text: String { blocks.map(\.text).joined(separator: "\n") }
    public var averageConfidence: Double {
        guard !blocks.isEmpty else { return 0 }
        return blocks.map(\.confidence).reduce(0, +) / Double(blocks.count)
    }
}
