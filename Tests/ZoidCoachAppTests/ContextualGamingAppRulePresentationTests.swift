import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Suite("Context-sensitive gaming app rules")
struct ContextualGamingAppRulePresentationTests {
    @Test("Discord and Twitch remain reviewable even before observation")
    func builtInContextSensitiveAppsAreAlwaysAvailable() {
        #expect(ContextualGamingAppRulePresentation.builtInApplications == ["Discord", "Twitch"])
        #expect(ContextualGamingAppRulePresentation.isSupported(" discord "))
        #expect(ContextualGamingAppRulePresentation.isSupported("TWITCH"))
        #expect(!ContextualGamingAppRulePresentation.isSupported("Steam"))
    }

    @Test("Automatic and explicit choices explain their future behavior")
    func choicesUseTruthfulContextCopy() {
        let automatic = ContextualGamingAppRulePresentation(
            application: "Discord",
            selection: .automatic
        )
        let gaming = ContextualGamingAppRulePresentation(
            application: "Twitch",
            selection: .gaming
        )

        #expect(automatic.title == "AUTO BY CONTEXT")
        #expect(automatic.detail.contains("local window title or URL"))
        #expect(automatic.detail.contains("future sessions"))
        #expect(gaming.title == "ALWAYS GAMING")
        #expect(gaming.detail.contains("Every future Twitch session"))
    }

    @Test("Twitch uses local context rather than a permanent gaming label")
    func twitchClassificationFollowsLocalContext() {
        let classifier = ContextualAppClassification()

        #expect(classifier.classify(
            application: "Twitch",
            windowTitle: "Client project research stream",
            url: "https://twitch.tv/research"
        ) == .work)
        #expect(classifier.classify(
            application: "Twitch",
            windowTitle: "League of Legends gameplay",
            url: "https://twitch.tv/game"
        ) == .gaming)
        #expect(classifier.classify(
            application: "Twitch",
            windowTitle: "Following",
            url: ""
        ) == .unknown)
    }

    @Test("Explicit Discord and Twitch choices persist independently")
    func settingsChoicesPersistIndependently() {
        let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        var draft = SettingsPolicyDraft(policy: original)

        draft.setClassifications(.gaming, for: ["Discord"])
        draft.setClassifications(.work, for: ["Twitch"])
        let saved = draft.policy(preserving: original)
        let reopened = SettingsPolicyDraft(policy: saved)

        #expect(reopened.settingsClassification(for: "Discord") == .gaming)
        #expect(reopened.settingsClassification(for: "Twitch") == .work)

        var resetDiscord = reopened
        resetDiscord.setClassifications(.automatic, for: ["Discord"])
        #expect(resetDiscord.settingsClassification(for: "Discord") == .automatic)
        #expect(resetDiscord.settingsClassification(for: "Twitch") == .work)
    }
}
