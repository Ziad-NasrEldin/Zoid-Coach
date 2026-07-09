import Testing
@testable import ZoidCoachApp

@Test
@MainActor
func atollDisabledExtensionsErrorHasActionableDiagnosis() {
    let health = AtollService.failureHealth(for: .remote("Extensions are disabled"))
    #expect(health.state == .attention)
    #expect(health.detail == "Atoll third-party extensions are disabled")
    #expect(health.evidence.contains("enable third-party extensions"))
}
