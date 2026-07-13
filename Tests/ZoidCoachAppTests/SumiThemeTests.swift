import Testing
@testable import ZoidCoachApp

@Test
func sumiAppearancePalettesMeetTextContrastRequirements() {
    for palette in [SumiAppearancePalette.light, .dark] {
        #expect(palette.ink.contrastRatio(with: palette.paper) >= 7)
        #expect(palette.ink.contrastRatio(with: palette.softPaper) >= 7)
        #expect(palette.ink.contrastRatio(with: palette.mist) >= 7)
        #expect(palette.muted.contrastRatio(with: palette.paper) >= 4.5)
        #expect(palette.paper.contrastRatio(with: palette.ink) >= 7)
        #expect(palette.paper.contrastRatio(with: palette.seal) >= 4.5)
        #expect(palette.sealDeep.contrastRatio(with: palette.sealWash) >= 4.5)
    }
}

@Test
func sumiAppearancePalettesKeepControlBoundariesVisible() {
    for palette in [SumiAppearancePalette.light, .dark] {
        #expect(palette.rule.contrastRatio(with: palette.paper) >= 3)
        #expect(palette.seal.contrastRatio(with: palette.paper) >= 4.5)
        #expect(palette.okay.contrastRatio(with: palette.paper) >= 4.5)
    }
}
