import AppKit
import SwiftUI
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

@Test @MainActor
func reducedMotionViewHostKeepsFiveInteractionOutcomesWithoutSpatialMotion() async throws {
    let model = MotionInteractionFixtureModel()
    let host = NSHostingView(
        rootView: MotionInteractionFixture(model: model)
            .environment(\.sumiReduceMotionOverride, true)
    )
    host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    await settle(host)

    model.pressAction()
    let pressed = try await snapshot(afterSettling: host, model: model)
    assertReducedPolicy(pressed)
    #expect(pressed.pressedScale == 1)
    #expect(pressed.pressedOpacity == 0.82)
    #expect(pressed.actionLabel == "ACTION PRESSED")

    model.insertPlanRow()
    let planned = try await snapshot(afterSettling: host, model: model)
    assertReducedPolicy(planned)
    #expect(planned.planRows == ["Write verifier evidence"])

    model.switchUsageCategory()
    let usage = try await snapshot(afterSettling: host, model: model)
    assertReducedPolicy(usage)
    #expect(usage.usageLabel == "WORK USAGE SELECTED")

    model.confirmEstimate()
    let estimate = try await snapshot(afterSettling: host, model: model)
    assertReducedPolicy(estimate)
    #expect(estimate.estimateLabel == "TIME ESTIMATE CONFIRMED: 45 MINUTES")

    model.reorderReminders()
    let reordered = try await snapshot(afterSettling: host, model: model)
    assertReducedPolicy(reordered)
    #expect(reordered.reminderOrder == ["Second reminder", "First reminder"])

    withExtendedLifetime(host) {}
}

@Test @MainActor
func standardMotionViewHostRetainsRepresentativePressedFeedbackAndMotion() async throws {
    let model = MotionInteractionFixtureModel()
    let host = NSHostingView(
        rootView: MotionInteractionFixture(model: model)
            .environment(\.sumiReduceMotionOverride, false)
    )
    host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    await settle(host)

    model.pressAction()
    let pressed = try await snapshot(afterSettling: host, model: model)

    #expect(pressed.policy.animatesStateChanges)
    #expect(pressed.policy.allowsSpatialMotion)
    #expect(pressed.policy.preservesImmediateFeedback)
    #expect(pressed.pressedScale == 0.98)
    #expect(pressed.pressedOpacity == 0.82)
    #expect(pressed.actionLabel == "ACTION PRESSED")

    withExtendedLifetime(host) {}
}

@Test @MainActor
func actionButtonWrapsConstrainedArabicWithoutHorizontalOverflow() async throws {
    let measurement = ActionButtonMeasurement()
    let host = NSHostingView(
        rootView: LocalizedActionButtonFixture(
            label: "تأكيد الخطة اليومية ومراجعة التفاصيل قبل المتابعة",
            width: 110,
            layoutDirection: .rightToLeft,
            measurement: measurement
        )
    )
    host.frame = NSRect(x: 0, y: 0, width: 110, height: 240)
    await settle(host)

    let size = try #require(measurement.size)
    #expect(size.width <= 110)
    #expect(size.height > 44)
    #expect(size.height < 240)

    withExtendedLifetime(host) {}
}

@Test @MainActor
func actionButtonWrapsConstrainedLongEnglishWithoutHorizontalOverflow() async throws {
    let measurement = ActionButtonMeasurement()
    let host = NSHostingView(
        rootView: LocalizedActionButtonFixture(
            label: "CONFIRM THE DAILY PLAN AND REVIEW DETAILS BEFORE CONTINUING",
            width: 180,
            layoutDirection: .leftToRight,
            measurement: measurement
        )
    )
    host.frame = NSRect(x: 0, y: 0, width: 180, height: 240)
    await settle(host)

    let size = try #require(measurement.size)
    #expect(size.width <= 180)
    #expect(size.height > 44)
    #expect(size.height < 240)

    withExtendedLifetime(host) {}
}

@Test @MainActor
func actionButtonKeepsShortEnglishAtMinimumTargetHeight() async throws {
    let measurement = ActionButtonMeasurement()
    let host = NSHostingView(
        rootView: LocalizedActionButtonFixture(
            label: "CONFIRM",
            width: 180,
            layoutDirection: .leftToRight,
            measurement: measurement
        )
    )
    host.frame = NSRect(x: 0, y: 0, width: 180, height: 120)
    await settle(host)

    let size = try #require(measurement.size)
    #expect(size.width <= 180)
    #expect(size.height == 44)

    withExtendedLifetime(host) {}
}

@Test @MainActor
func compactActionButtonWrapsLocalizedCopyAboveTheMinimumTargetHeight() async throws {
    let measurement = ActionButtonMeasurement()
    let host = NSHostingView(
        rootView: LocalizedActionButtonFixture(
            label: "فتح إعدادات الخصوصية ومراجعة الإذن",
            width: 70,
            layoutDirection: .rightToLeft,
            controlSize: .compact,
            measurement: measurement
        )
    )
    host.frame = NSRect(x: 0, y: 0, width: 70, height: 240)
    await settle(host)

    let size = try #require(measurement.size)
    #expect(size.width <= 70)
    #expect(size.height > 44)
    #expect(size.height < 240)

    withExtendedLifetime(host) {}
}

@Test @MainActor
func largeActionButtonWrapsLocalizedCopyAboveTheMinimumTargetHeight() async throws {
    let measurement = ActionButtonMeasurement()
    let host = NSHostingView(
        rootView: LocalizedActionButtonFixture(
            label: "مراجعة الخطة اليومية والمتابعة إلى شاشة اليوم",
            width: 110,
            layoutDirection: .rightToLeft,
            controlSize: .large,
            measurement: measurement
        )
    )
    host.frame = NSRect(x: 0, y: 0, width: 110, height: 240)
    await settle(host)

    let size = try #require(measurement.size)
    #expect(size.width <= 110)
    #expect(size.height > 44)
    #expect(size.height < 240)

    withExtendedLifetime(host) {}
}

@Test @MainActor
func localizedActionButtonsFitARepresentativeNarrowHorizontalStack() async throws {
    let first = ActionButtonMeasurement()
    let second = ActionButtonMeasurement()
    let host = NSHostingView(
        rootView: HStack(spacing: 8) {
            LocalizedActionButtonFixture(
                label: "فتح إعدادات النظام",
                width: 156,
                layoutDirection: .rightToLeft,
                controlSize: .standard,
                measurement: first
            )
            LocalizedActionButtonFixture(
                label: "المتابعة من دون إذن",
                width: 156,
                layoutDirection: .rightToLeft,
                controlSize: .standard,
                measurement: second
            )
        }
    )
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    await settle(host)

    let firstSize = try #require(first.size)
    let secondSize = try #require(second.size)
    #expect(firstSize.width + 8 + secondSize.width <= 320)
    #expect(firstSize.height >= 44)
    #expect(secondSize.height >= 44)
    #expect(max(firstSize.height, secondSize.height) < 240)

    withExtendedLifetime(host) {}
}

@Test @MainActor
func iconOnlyActionButtonKeepsTheSharedStepperAtExactly44Points() async throws {
    let measurement = ActionButtonMeasurement()
    let host = NSHostingView(rootView: IconActionButtonFixture(measurement: measurement))
    host.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
    await settle(host)

    let size = try #require(measurement.size)
    #expect(size == CGSize(width: 44, height: 44))

    withExtendedLifetime(host) {}
}

private func assertReducedPolicy(_ snapshot: MotionInteractionSnapshot) {
    #expect(!snapshot.policy.animatesStateChanges)
    #expect(!snapshot.policy.allowsSpatialMotion)
    #expect(snapshot.policy.preservesImmediateFeedback)
}

@MainActor
private func settle<Content: View>(_ host: NSHostingView<Content>) async {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
}

@MainActor
private func snapshot<Content: View>(
    afterSettling host: NSHostingView<Content>,
    model: MotionInteractionFixtureModel
) async throws -> MotionInteractionSnapshot {
    await settle(host)
    let snapshot = try #require(model.latestSnapshot)
    #expect(snapshot.revision == model.revision)
    return snapshot
}

private struct MotionInteractionSnapshot: Equatable {
    let revision: Int
    let policy: SumiMotionPolicy
    let pressedScale: CGFloat
    let pressedOpacity: Double
    let actionLabel: String
    let planRows: [String]
    let usageLabel: String
    let estimateLabel: String
    let reminderOrder: [String]
}

@MainActor
private final class ActionButtonMeasurement: ObservableObject {
    @Published var size: CGSize?
}

private struct ActionButtonSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct LocalizedActionButtonFixture: View {
    let label: String
    let width: CGFloat
    let layoutDirection: LayoutDirection
    let controlSize: SumiControlSize
    @ObservedObject var measurement: ActionButtonMeasurement

    init(
        label: String,
        width: CGFloat,
        layoutDirection: LayoutDirection,
        controlSize: SumiControlSize = .standard,
        measurement: ActionButtonMeasurement
    ) {
        self.label = label
        self.width = width
        self.layoutDirection = layoutDirection
        self.controlSize = controlSize
        self.measurement = measurement
    }

    var body: some View {
        Button(label) {}
            .buttonStyle(SumiActionButtonStyle(role: .primary, size: controlSize))
            .frame(width: width)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ActionButtonSizePreferenceKey.self,
                        value: geometry.size
                    )
                }
            }
            .onPreferenceChange(ActionButtonSizePreferenceKey.self) { measurement.size = $0 }
            .environment(\.layoutDirection, layoutDirection)
    }
}

private struct IconActionButtonFixture: View {
    @ObservedObject var measurement: ActionButtonMeasurement

    var body: some View {
        Button {} label: {
            Image(systemName: "plus")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(SumiActionButtonStyle(
            role: .text,
            size: .compact,
            usesContentPadding: false
        ))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ActionButtonSizePreferenceKey.self,
                    value: geometry.size
                )
            }
        }
        .onPreferenceChange(ActionButtonSizePreferenceKey.self) { measurement.size = $0 }
    }
}

@MainActor
private final class MotionInteractionFixtureModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var isPressed = false
    @Published private(set) var planRows: [String] = []
    @Published private(set) var showsWorkUsage = false
    @Published private(set) var confirmedEstimateMinutes: Int?
    @Published private(set) var reminderOrder = ["First reminder", "Second reminder"]
    var latestSnapshot: MotionInteractionSnapshot?

    func pressAction() {
        isPressed = true
        revision += 1
    }

    func insertPlanRow() {
        planRows.append("Write verifier evidence")
        revision += 1
    }

    func switchUsageCategory() {
        showsWorkUsage = true
        revision += 1
    }

    func confirmEstimate() {
        confirmedEstimateMinutes = 45
        revision += 1
    }

    func reorderReminders() {
        reminderOrder.swapAt(0, 1)
        revision += 1
    }
}

private struct MotionInteractionFixture: View {
    @SumiReduceMotion private var reduceMotion
    @ObservedObject var model: MotionInteractionFixtureModel

    var body: some View {
        let policy = SumiMotionPolicy.resolve(reduceMotion: reduceMotion)
        let pressedScale = SumiMotion.scale(
            reduceMotion: reduceMotion,
            isActive: model.isPressed,
            activeScale: 0.98
        )
        let pressedOpacity = model.isPressed ? 0.82 : 1
        let actionLabel = model.isPressed ? "ACTION PRESSED" : "ACTION READY"
        let usageLabel = model.showsWorkUsage ? "WORK USAGE SELECTED" : "ALL USAGE SELECTED"
        let estimateLabel = model.confirmedEstimateMinutes.map {
            "TIME ESTIMATE CONFIRMED: \($0) MINUTES"
        } ?? "TIME ESTIMATE NOT CONFIRMED"
        let snapshot = MotionInteractionSnapshot(
            revision: model.revision,
            policy: policy,
            pressedScale: pressedScale,
            pressedOpacity: pressedOpacity,
            actionLabel: actionLabel,
            planRows: model.planRows,
            usageLabel: usageLabel,
            estimateLabel: estimateLabel,
            reminderOrder: model.reminderOrder
        )

        VStack(alignment: .leading, spacing: 8) {
            Text(actionLabel)
                .opacity(pressedOpacity)
                .scaleEffect(pressedScale)
                .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.15), value: model.isPressed)

            ForEach(model.planRows, id: \.self) { row in
                Text(row)
                    .transition(SumiMotion.transition(
                        reduceMotion: reduceMotion,
                        normal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    ))
            }
            .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.22), value: model.planRows)

            Text(usageLabel)
                .transition(SumiMotion.transition(
                    reduceMotion: reduceMotion,
                    normal: .opacity.combined(with: .offset(x: 7))
                ))
                .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: model.showsWorkUsage)

            Text(estimateLabel)
                .transition(SumiMotion.transition(
                    reduceMotion: reduceMotion,
                    normal: .scale(scale: 0.9).combined(with: .opacity)
                ))
                .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: model.confirmedEstimateMinutes)

            ForEach(model.reminderOrder, id: \.self) { reminder in
                Text(reminder)
            }
            .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: model.reminderOrder)
        }
        .background(MotionSnapshotProbe(snapshot: snapshot, model: model))
    }
}

private struct MotionSnapshotProbe: NSViewRepresentable {
    let snapshot: MotionInteractionSnapshot
    let model: MotionInteractionFixtureModel

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        model.latestSnapshot = snapshot
    }
}
