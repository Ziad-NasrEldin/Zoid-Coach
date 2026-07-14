import SwiftUI
import ZoidCoachCore

struct DailyReviewKeyboardCorrection: Equatable {
    let sessionID: String
    let classification: BehaviorClassification
}

enum DailyReviewKeyboardSelectionDirection: Equatable {
    case previous
    case next
}

struct DailyReviewKeyboardFlowState: Equatable {
    private(set) var sourceDay: String
    private(set) var sessions: [DailyReviewSession]
    private(set) var selectedSessionID: String?
    private(set) var selectedClassification: BehaviorClassification?
    private var baselineClassification: BehaviorClassification?
    private var hasAppliedCorrection = false

    init(sourceDay: String = "", sessions: [DailyReviewSession] = []) {
        self.sourceDay = sourceDay
        self.sessions = Self.ordered(sessions)
        selectedSessionID = self.sessions.first?.id
        selectedClassification = self.sessions.first?.classification
        baselineClassification = self.sessions.first?.classification
    }

    var selectedSession: DailyReviewSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var pendingCorrection: DailyReviewKeyboardCorrection? {
        guard let selectedSessionID,
              let selectedClassification,
              selectedClassification != baselineClassification
        else { return nil }
        return DailyReviewKeyboardCorrection(
            sessionID: selectedSessionID,
            classification: selectedClassification
        )
    }

    var canConfirm: Bool {
        hasAppliedCorrection && !sessions.isEmpty && pendingCorrection == nil
    }

    mutating func reconcile(sourceDay: String, sessions: [DailyReviewSession]) {
        let changedDay = sourceDay != self.sourceDay
        let hadDraft = pendingCorrection != nil
        let previousBaseline = baselineClassification
        self.sourceDay = sourceDay
        self.sessions = Self.ordered(sessions)

        if changedDay {
            hasAppliedCorrection = false
            select(sessionID: self.sessions.first?.id)
            return
        }

        guard let selectedSessionID,
              let refreshed = self.sessions.first(where: { $0.id == selectedSessionID })
        else {
            select(sessionID: self.sessions.first?.id)
            return
        }

        if !hadDraft || refreshed.classification != previousBaseline {
            baselineClassification = refreshed.classification
            selectedClassification = refreshed.classification
        }
    }

    mutating func moveSelection(_ direction: DailyReviewKeyboardSelectionDirection) {
        guard !sessions.isEmpty else {
            select(sessionID: nil)
            return
        }
        let currentIndex = selectedSessionID.flatMap { id in
            sessions.firstIndex { $0.id == id }
        } ?? 0
        let selectedIndex: Int
        switch direction {
        case .previous:
            selectedIndex = currentIndex == 0 ? sessions.count - 1 : currentIndex - 1
        case .next:
            selectedIndex = (currentIndex + 1) % sessions.count
        }
        select(sessionID: sessions[selectedIndex].id)
    }

    mutating func selectClassification(_ classification: BehaviorClassification) {
        guard selectedSession != nil else { return }
        selectedClassification = classification
    }

    @discardableResult
    mutating func recordAppliedCorrection() -> Bool {
        guard let correction = pendingCorrection else { return false }
        baselineClassification = correction.classification
        selectedClassification = correction.classification
        hasAppliedCorrection = true
        return true
    }

    private mutating func select(sessionID: String?) {
        selectedSessionID = sessionID
        let classification = sessions.first { $0.id == sessionID }?.classification
        selectedClassification = classification
        baselineClassification = classification
    }

    private static func ordered(_ sessions: [DailyReviewSession]) -> [DailyReviewSession] {
        sessions.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.application != $1.application {
                return $0.application.localizedCaseInsensitiveCompare($1.application) == .orderedAscending
            }
            return $0.id < $1.id
        }
    }
}

enum DailyReviewKeyboardShortcut: CaseIterable, Hashable {
    case openReviews
    case previousSession
    case nextSession
    case chooseWork
    case chooseGaming
    case chooseDistracting
    case chooseIdle
    case chooseUnknown
    case applyCorrection
    case confirmReview

    static func classification(_ classification: BehaviorClassification) -> Self {
        switch classification {
        case .work: .chooseWork
        case .gaming: .chooseGaming
        case .distracting: .chooseDistracting
        case .idle: .chooseIdle
        case .unknown: .chooseUnknown
        }
    }

    var descriptor: DailyReviewKeyboardShortcutDescriptor {
        switch self {
        case .openReviews:
            .init(key: .character("r"), modifiers: [.command, .option])
        case .previousSession:
            .init(key: .character("["), modifiers: [.command, .shift])
        case .nextSession:
            .init(key: .character("]"), modifiers: [.command, .shift])
        case .chooseWork:
            .init(key: .character("1"), modifiers: [.command, .shift])
        case .chooseGaming:
            .init(key: .character("2"), modifiers: [.command, .shift])
        case .chooseDistracting:
            .init(key: .character("3"), modifiers: [.command, .shift])
        case .chooseIdle:
            .init(key: .character("4"), modifiers: [.command, .shift])
        case .chooseUnknown:
            .init(key: .character("5"), modifiers: [.command, .shift])
        case .applyCorrection:
            .init(key: .character("a"), modifiers: [.command, .shift])
        case .confirmReview:
            .init(key: .returnKey, modifiers: [.command, .shift])
        }
    }
}

extension AppSection {
    var dailyReviewKeyboardShortcut: DailyReviewKeyboardShortcut? {
        self == .reviews ? .openReviews : nil
    }
}

struct DailyReviewNavigationCommandState: Equatable {
    let isAvailable: Bool

    var destination: AppSection? {
        isAvailable ? .reviews : nil
    }
}

@MainActor
struct DailyReviewNavigationCommands: Commands {
    @ObservedObject var model: AppModel
    let isAvailable: Bool

    var body: some Commands {
        let state = DailyReviewNavigationCommandState(isAvailable: isAvailable)
        let shortcut = DailyReviewKeyboardShortcut.openReviews.descriptor
        CommandMenu("Navigate") {
            Button("Open Reviews") {
                guard let destination = state.destination else { return }
                model.selectedSection = destination
            }
            .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
            .disabled(state.destination == nil)
        }
    }
}

struct DailyReviewKeyboardShortcutDescriptor: Equatable {
    let key: DailyReviewKeyboardShortcutKey
    let modifiers: Set<DailyReviewKeyboardShortcutModifier>

    var signature: String {
        let modifierSignature = modifiers.map(\.rawValue).sorted().joined(separator: "+")
        return "\(modifierSignature)+\(key.signature)"
    }

    var visibleLegend: String {
        let names = DailyReviewKeyboardShortcutModifier.visibleOrder
            .filter(modifiers.contains)
            .map(\.rawValue)
        return (names + [key.visibleName]).joined(separator: "-")
    }

    var glyphLegend: String {
        let modifierGlyphs = DailyReviewKeyboardShortcutModifier.visibleOrder
            .filter(modifiers.contains)
            .map(\.glyph)
            .joined()
        return modifierGlyphs + key.glyph
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case let .character(character): KeyEquivalent(character)
        case .returnKey: .return
        }
    }

    var eventModifiers: EventModifiers {
        modifiers.reduce(into: EventModifiers()) { result, modifier in
            switch modifier {
            case .control: result.insert(.control)
            case .option: result.insert(.option)
            case .command: result.insert(.command)
            case .shift: result.insert(.shift)
            }
        }
    }
}

enum DailyReviewKeyboardShortcutKey: Equatable {
    case character(Character)
    case returnKey

    var signature: String {
        switch self {
        case let .character(character): String(character)
        case .returnKey: "return"
        }
    }

    var visibleName: String { signature }

    var glyph: String {
        switch self {
        case let .character(character): String(character)
        case .returnKey: "↩"
        }
    }
}

enum DailyReviewKeyboardShortcutModifier: String, Equatable, Hashable {
    case control
    case option
    case command
    case shift

    static let visibleOrder: [Self] = [.control, .option, .command, .shift]

    var glyph: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        case .shift: "⇧"
        }
    }
}
