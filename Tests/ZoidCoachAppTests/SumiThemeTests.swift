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

@Test
func sumiMotionPolicyRemovesAnimationAndSpatialMovementWhenReduced() {
    let reduced = SumiMotionPolicy.resolve(reduceMotion: true)

    #expect(!reduced.animatesStateChanges)
    #expect(!reduced.allowsSpatialMotion)
    #expect(reduced.preservesImmediateFeedback)
    #expect(SumiMotion.animation(reduceMotion: true, duration: 0.2) == nil)
    #expect(SumiMotion.scale(reduceMotion: true, isActive: true, activeScale: 0.8) == 1)
}

@Test
func sumiMotionPolicyKeepsRestrainedMotionInStandardMode() {
    let standard = SumiMotionPolicy.resolve(reduceMotion: false)

    #expect(standard.animatesStateChanges)
    #expect(standard.allowsSpatialMotion)
    #expect(standard.preservesImmediateFeedback)
    #expect(SumiMotion.animation(reduceMotion: false, duration: 0.2) != nil)
    #expect(SumiMotion.scale(reduceMotion: false, isActive: true, activeScale: 0.8) == 0.8)
    #expect(SumiMotion.scale(reduceMotion: false, isActive: false, activeScale: 0.8) == 1)
}
