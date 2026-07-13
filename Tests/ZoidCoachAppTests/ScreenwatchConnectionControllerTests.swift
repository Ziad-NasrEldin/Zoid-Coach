import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func screenwatchRecordEvidenceShowsExactFolderAndLocalizedAbsoluteTime() throws {
    let status = ScreenwatchSetupStatus(
        source: .alternateFolder,
        health: .healthy,
        continuation: .ready,
        repair: .none,
        summary: "Current local records are available",
        evidence: "Schema-valid local records were found.",
        validRecordCount: 12,
        sourcePath: "/Users/test/Library/Application Support/Screenwatch/days",
        lastValidRecordAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let evidence = try #require(ScreenwatchRecordEvidence(
        status: status,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: utc
    ))

    #expect(evidence.sourcePath == "/Users/test/Library/Application Support/Screenwatch/days")
    #expect(evidence.lastValidRecordText == "Jan 15, 2027 at 8:00:00\u{202F}AM")
    #expect(evidence.accessibilitySummary.contains("Last valid record: Jan 15, 2027 at 8:00:00\u{202F}AM"))
}

@Test
func screenwatchRecordEvidenceNamesMissingRecordWithoutInventingTime() throws {
    let status = ScreenwatchSetupStatus(
        source: .defaultLocation,
        health: .missing,
        continuation: .degraded,
        repair: .recheck,
        summary: "No log exists for today",
        evidence: "The folder is available.",
        validRecordCount: 0,
        sourcePath: "/Users/test/.screenwatch/days"
    )

    let evidence = try #require(ScreenwatchRecordEvidence(status: status))

    #expect(evidence.lastValidRecordText == nil)
    #expect(evidence.accessibilitySummary == "Screenwatch folder: /Users/test/.screenwatch/days. No valid record is available yet.")
}

@MainActor
@Test
func screenwatchConnectionMovesFromInvalidDefaultToHealthyAlternateAndBack() async {
    let service = StubScreenwatchSetupService(status: screenwatchStatus(
        source: .defaultLocation,
        health: .malformed,
        repair: .chooseFolder,
        summary: "The expected source is invalid"
    ))
    let controller = ScreenwatchConnectionController(service: service)

    await controller.inspect()
    #expect(controller.status?.health == .malformed)
    #expect(controller.status?.repair == .chooseFolder)

    await controller.selectDirectory(URL(fileURLWithPath: "/private/qa/Screenwatch/days"))
    #expect(controller.status?.source == .alternateFolder)
    #expect(controller.status?.health == .healthy)
    #expect(controller.errorMessage == nil)

    await controller.useExpectedDirectory()
    #expect(controller.status?.source == .defaultLocation)
    #expect(controller.status?.health == .missing)
    #expect(await service.selectionCount() == 1)
    #expect(await service.defaultCount() == 1)
}

@MainActor
@Test
func screenwatchConnectionForegroundRefreshesRepairStateWithoutASecondSelection() async {
    let service = StubScreenwatchSetupService(status: screenwatchStatus(
        source: .alternateFolder,
        health: .bookmarkUnavailable,
        repair: .reauthorizeFolder,
        summary: "Saved access expired"
    ))
    await service.setRecheckStatus(screenwatchStatus(
        source: .alternateFolder,
        health: .healthy,
        repair: .none,
        summary: "Current local records are available"
    ))
    let controller = ScreenwatchConnectionController(service: service)

    await controller.inspect()
    await controller.applicationDidBecomeActive()

    #expect(controller.status?.health == .healthy)
    #expect(await service.recheckCount() == 1)
    #expect(await service.selectionCount() == 0)
}

@MainActor
@Test
func screenwatchConnectionSelectionFailurePreservesConfirmedStateAndRedactsPath() async {
    let service = StubScreenwatchSetupService(status: screenwatchStatus(
        source: .defaultLocation,
        health: .missing,
        repair: .chooseFolder,
        summary: "No source yet"
    ))
    await service.rejectSelection(with: ScreenwatchSetupServiceError.unsafePath)
    let controller = ScreenwatchConnectionController(service: service)

    await controller.inspect()
    await controller.selectDirectory(URL(fileURLWithPath: "/Users/person/private/screens"))

    #expect(controller.status?.health == .missing)
    #expect(controller.errorMessage == "The selected Screenwatch folder is not safe to use.")
    #expect(controller.errorMessage?.contains("/Users/person") == false)
}

private actor StubScreenwatchSetupService: ScreenwatchSetupServicing {
    private var current: ScreenwatchSetupStatus
    private var nextRecheck: ScreenwatchSetupStatus?
    private var selectionError: ScreenwatchSetupServiceError?
    private var selections = 0
    private var defaults = 0
    private var rechecks = 0

    init(status: ScreenwatchSetupStatus) {
        current = status
    }

    func inspect(now _: Date) -> ScreenwatchSetupStatus { current }

    func recheck(now _: Date) -> ScreenwatchSetupStatus {
        rechecks += 1
        if let nextRecheck {
            current = nextRecheck
            self.nextRecheck = nil
        }
        return current
    }

    func selectAlternateDaysDirectory(_ url: URL, now _: Date) throws -> ScreenwatchSetupStatus {
        _ = url
        selections += 1
        if let selectionError { throw selectionError }
        current = screenwatchStatus(
            source: .alternateFolder,
            health: .healthy,
            repair: .none,
            summary: "Current local records are available"
        )
        return current
    }

    func useDefaultLocation(now _: Date) -> ScreenwatchSetupStatus {
        defaults += 1
        current = screenwatchStatus(
            source: .defaultLocation,
            health: .missing,
            repair: .recheck,
            summary: "No log exists for today"
        )
        return current
    }

    func setRecheckStatus(_ status: ScreenwatchSetupStatus) {
        nextRecheck = status
    }

    func rejectSelection(with error: ScreenwatchSetupServiceError) {
        selectionError = error
    }

    func selectionCount() -> Int { selections }
    func defaultCount() -> Int { defaults }
    func recheckCount() -> Int { rechecks }
}

private func screenwatchStatus(
    source: ScreenwatchSetupSource,
    health: ScreenwatchSetupHealth,
    repair: ScreenwatchSetupRepair,
    summary: String
) -> ScreenwatchSetupStatus {
    ScreenwatchSetupStatus(
        source: source,
        health: health,
        continuation: health == .healthy ? .ready : .degraded,
        repair: repair,
        summary: summary,
        evidence: "No captured titles, URLs, screenshots, or file locations were displayed.",
        validRecordCount: health == .healthy ? 12 : 0
    )
}
