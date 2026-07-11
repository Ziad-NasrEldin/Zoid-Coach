import Foundation
import Testing
@testable import ZoidCoachCore

private struct WhatsAppEvaluationCorpus: Decodable {
    struct Thresholds: Decodable {
        let minimumPrecision: Double
        let minimumRecall: Double
    }

    struct Fixture: Decodable {
        let id: String
        let appearance: String
        let language: String
        let conversation: String
        let messageShape: String
        let text: String
        let expectsCandidate: Bool
        let expectsClarification: Bool
    }

    let thresholds: Thresholds
    let cases: [Fixture]
}

@Test
func sanitizedWhatsAppFixtureMatrixMeetsAgreedPrecisionAndRecallThresholds() throws {
    let corpus = try loadWhatsAppEvaluationCorpus()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let observedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9)))
    let extractor = MeetingCandidateExtractor(calendar: calendar)

    var truePositives = 0
    var falsePositives = 0
    var falseNegatives = 0

    for fixture in corpus.cases {
        let candidate = extractor.extract(from: fixture.text, observedAt: observedAt)
        switch (fixture.expectsCandidate, candidate != nil) {
        case (true, true): truePositives += 1
        case (false, true): falsePositives += 1
        case (true, false): falseNegatives += 1
        case (false, false): break
        }
        if fixture.expectsCandidate, let candidate {
            #expect(
                candidate.requiresClarification == fixture.expectsClarification,
                "Fixture \(fixture.id) routed to the wrong confidence path"
            )
        }
    }

    let precision = Double(truePositives) / Double(max(1, truePositives + falsePositives))
    let recall = Double(truePositives) / Double(max(1, truePositives + falseNegatives))

    #expect(
        precision >= corpus.thresholds.minimumPrecision,
        "Measured precision \(precision) is below the agreed threshold \(corpus.thresholds.minimumPrecision)"
    )
    #expect(
        recall >= corpus.thresholds.minimumRecall,
        "Measured recall \(recall) is below the agreed threshold \(corpus.thresholds.minimumRecall)"
    )
}

@Test
func sanitizedWhatsAppFixtureMatrixCoversEveryRequiredPresentationVariant() throws {
    let fixtures = try loadWhatsAppEvaluationCorpus().cases

    #expect(Set(fixtures.map(\.appearance)) == ["light", "dark"])
    #expect(Set(fixtures.map(\.language)) == ["english", "arabic"])
    #expect(fixtures.contains { $0.conversation == "group" })
    #expect(fixtures.contains { $0.messageShape == "quoted" })
    #expect(fixtures.contains { $0.messageShape == "ambiguousDate" })
    #expect(fixtures.contains { !$0.expectsCandidate })
}

private func loadWhatsAppEvaluationCorpus() throws -> WhatsAppEvaluationCorpus {
    return try JSONDecoder().decode(
        WhatsAppEvaluationCorpus.self,
        from: Data(sanitizedWhatsAppMeetingEvaluationJSON.utf8)
    )
}
