import XCTest
@testable import ZoidCoachApp

final class ScreenwatchRepairActionPresentationTests: XCTestCase {
    func testFirstSelectionExplainsThePickerAndPrivacyBoundary() {
        let presentation = ScreenwatchRepairActionPresentation(status: nil)

        XCTAssertEqual(presentation.state, .firstSelection)
        XCTAssertEqual(presentation.primaryTitle, "CHOOSE FOLDER")
        XCTAssertTrue(presentation.accessibilityHint.contains("direct Screenwatch days folder"))
        XCTAssertTrue(presentation.explanation.contains("first connection"))
        assertPrivacyBoundary(in: presentation)
    }

    func testExpiredBookmarkOffersReauthorizationOfTheSameFolder() {
        let presentation = ScreenwatchRepairActionPresentation(
            status: status(
                source: .alternateFolder,
                health: .bookmarkUnavailable,
                repair: .reauthorizeFolder
            )
        )

        XCTAssertEqual(presentation.state, .expiredAccess)
        XCTAssertEqual(presentation.primaryTitle, "REAUTHORIZE FOLDER")
        XCTAssertTrue(presentation.accessibilityHint.contains("renew access"))
        XCTAssertTrue(presentation.explanation.contains("access expired"))
        XCTAssertTrue(presentation.explanation.contains("same direct days folder"))
        assertPrivacyBoundary(in: presentation)
    }

    func testUnavailableFolderOffersAReplacementFolder() {
        let presentation = ScreenwatchRepairActionPresentation(
            status: status(
                source: .alternateFolder,
                health: .accessUnavailable,
                repair: .chooseFolder
            )
        )

        XCTAssertEqual(presentation.state, .unavailableFolder)
        XCTAssertEqual(presentation.primaryTitle, "CHOOSE AVAILABLE FOLDER")
        XCTAssertTrue(presentation.accessibilityHint.contains("replace the unavailable"))
        XCTAssertTrue(presentation.explanation.contains("restore local access"))
        assertPrivacyBoundary(in: presentation)
    }

    func testHealthyAlternateFolderMakesReplacementOptional() {
        let presentation = ScreenwatchRepairActionPresentation(
            status: status(
                source: .alternateFolder,
                health: .healthy,
                repair: .none
            )
        )

        XCTAssertEqual(presentation.state, .connectedFolder)
        XCTAssertEqual(presentation.primaryTitle, "CHANGE FOLDER")
        XCTAssertTrue(presentation.accessibilityHint.contains("replace the connected"))
        XCTAssertTrue(presentation.explanation.contains("access is working"))
        XCTAssertTrue(presentation.explanation.contains("only if Screenwatch moved"))
        assertPrivacyBoundary(in: presentation)
    }

    func testPresentationNeverUsesPrivateStatusEvidence() {
        let privateValue = "PRIVATE-CAPTURE-TITLE https://private.example /Users/person/secret"
        let presentation = ScreenwatchRepairActionPresentation(
            status: ScreenwatchSetupStatus(
                source: .alternateFolder,
                health: .bookmarkUnavailable,
                continuation: .unavailable,
                repair: .reauthorizeFolder,
                summary: privateValue,
                evidence: privateValue,
                validRecordCount: 0,
                sourcePath: privateValue
            )
        )
        let visibleText = [
            presentation.primaryTitle,
            presentation.accessibilityHint,
            presentation.explanation,
        ].joined(separator: " ")

        XCTAssertFalse(visibleText.contains(privateValue))
        XCTAssertFalse(visibleText.contains("private.example"))
        XCTAssertFalse(visibleText.contains("/Users/person/secret"))
    }

    private func status(
        source: ScreenwatchSetupSource,
        health: ScreenwatchSetupHealth,
        repair: ScreenwatchSetupRepair
    ) -> ScreenwatchSetupStatus {
        ScreenwatchSetupStatus(
            source: source,
            health: health,
            continuation: health == .healthy ? .ready : .unavailable,
            repair: repair,
            summary: "Summary",
            evidence: "Evidence",
            validRecordCount: 0,
            sourcePath: nil
        )
    }

    private func assertPrivacyBoundary(
        in presentation: ScreenwatchRepairActionPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = presentation.explanation
        XCTAssertTrue(text.contains("titles"), file: file, line: line)
        XCTAssertTrue(text.contains("URLs"), file: file, line: line)
        XCTAssertTrue(text.contains("screenshots"), file: file, line: line)
        XCTAssertTrue(text.contains("record contents"), file: file, line: line)
    }
}
