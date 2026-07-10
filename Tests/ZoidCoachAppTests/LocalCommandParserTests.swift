import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func localFallbackParsesOnlyTheBoundedChiefOfStaffGrammar() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let open = try #require(LocalCommandParser.invocation(from: "Open Xcode", sessionID: "local", now: date))
    let search = try #require(LocalCommandParser.invocation(from: "Search for Gemini pricing", sessionID: "local", now: date))
    let brief = try #require(LocalCommandParser.invocation(from: "أعمل ايه دلوقتي", sessionID: "local", now: date))
    let file = try #require(LocalCommandParser.invocation(from: "Open file /tmp/brief.txt", sessionID: "local", now: date))

    #expect(open.toolName == "open_application")
    #expect(open.argumentsJSON == #"{"name":"Xcode"}"#)
    #expect(search.toolName == "search_web")
    #expect(brief.toolName == "get_daily_brief")
    #expect(file.toolName == "open_file")
    #expect(LocalCommandParser.invocation(from: "Run rm -rf", sessionID: "local", now: date) == nil)
}
