import SwiftUI

@MainActor
final class SumiModalCoordinator: ObservableObject {
    @Published private(set) var confirmation: SumiConfirmationRequest?

    func present(
        eyebrow: String,
        title: String,
        message: String,
        confirmTitle: String,
        confirmRole: SumiActionRole,
        confirm: @escaping () -> Void,
        cancel: @escaping () -> Void = {}
    ) {
        confirmation = SumiConfirmationRequest(
            eyebrow: eyebrow,
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            confirmRole: confirmRole,
            confirm: { [weak self] in
                self?.confirmation = nil
                confirm()
            },
            cancel: { [weak self] in
                self?.confirmation = nil
                cancel()
            }
        )
    }

    func dismiss() {
        let cancel = confirmation?.cancel
        confirmation = nil
        cancel?()
    }
}

struct SumiConfirmationRequest: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: String
    let message: String
    let confirmTitle: String
    let confirmRole: SumiActionRole
    let confirm: () -> Void
    let cancel: () -> Void
}

enum Sumi {
    static let ink = Color(red: 13 / 255, green: 10 / 255, blue: 10 / 255)
    static let paper = Color.white
    static let softPaper = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let mist = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let rule = Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255)
    static let paleRule = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
    static let muted = Color(red: 84 / 255, green: 85 / 255, blue: 84 / 255)
    static let wash = Color(red: 247 / 255, green: 245 / 255, blue: 244 / 255)
    static let seal = Color(red: 194 / 255, green: 58 / 255, blue: 46 / 255)
    static let sealDeep = Color(red: 143 / 255, green: 33 / 255, blue: 26 / 255)
    static let sealWash = Color(red: 245 / 255, green: 229 / 255, blue: 227 / 255)
    static let okay = Color(red: 47 / 255, green: 58 / 255, blue: 47 / 255)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}

enum SumiActionRole {
    case primary
    case accent
    case quiet
    case destructive
    case text
}

enum SumiControlSize {
    case compact
    case standard
    case large

    var height: CGFloat {
        switch self {
        case .compact: 28
        case .standard: 36
        case .large: 44
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 9
        case .standard: 12
        case .large: 14
        }
    }

    var labelSize: CGFloat {
        switch self {
        case .compact: 8
        case .standard: 9
        case .large: 9
        }
    }
}

struct SumiActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let role: SumiActionRole
    let size: SumiControlSize

    init(role: SumiActionRole = .primary, size: SumiControlSize = .standard) {
        self.role = role
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sumi.label(size.labelSize))
            .sumiLabelTracking()
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.height)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .overlay { Rectangle().stroke(borderColor, lineWidth: 1) }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return Sumi.muted }
        return switch role {
        case .primary, .accent: Sumi.paper
        case .quiet, .text: Sumi.ink
        case .destructive: isHovering ? Sumi.paper : Sumi.sealDeep
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return Sumi.mist }
        return switch role {
        case .primary: isHovering || isPressed ? Sumi.seal : Sumi.ink
        case .accent: isHovering || isPressed ? Sumi.sealDeep : Sumi.seal
        case .quiet: isHovering || isPressed ? Sumi.softPaper : Sumi.paper
        case .destructive: isHovering || isPressed ? Sumi.seal : Sumi.sealWash
        case .text: Color.clear
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return Sumi.rule }
        return switch role {
        case .primary: isHovering ? Sumi.seal : Sumi.ink
        case .accent: isHovering ? Sumi.sealDeep : Sumi.seal
        case .quiet: isHovering ? Sumi.ink : Sumi.rule
        case .destructive: Sumi.seal
        case .text: Color.clear
        }
    }
}

struct SumiPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SumiToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .font(Sumi.body(13))
                    .foregroundStyle(isEnabled ? Sumi.ink : Sumi.muted)
                Spacer(minLength: 12)
                Text(configuration.isOn ? "ON" : "OFF")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(configuration.isOn && isEnabled ? Sumi.paper : Sumi.muted)
                    .frame(width: 42, height: 26)
                    .background(configuration.isOn && isEnabled ? Sumi.ink : Sumi.mist)
                    .overlay { Rectangle().stroke(configuration.isOn && isEnabled ? Sumi.ink : Sumi.rule, lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct SumiTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    init(_ label: String, placeholder: String? = nil, text: Binding<String>) {
        self.label = label
        self.placeholder = placeholder ?? label
        _text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.ink)
                .tint(Sumi.seal)
                .focused($isFocused)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Sumi.paper)
                .overlay { Rectangle().stroke(isFocused ? Sumi.seal : Sumi.rule, lineWidth: 1) }
        }
    }
}

struct SumiControlLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(Sumi.muted)
    }
}

enum SumiSelectorSize {
    case compact
    case standard

    var height: CGFloat { self == .compact ? 28 : 40 }
    var horizontalPadding: CGFloat { self == .compact ? 9 : 10 }
    var fontSize: CGFloat { self == .compact ? 8 : 13 }
}

struct SumiSelectorLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let systemImage: String?
    let size: SumiSelectorSize
    let showsChevron: Bool
    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String? = nil,
        size: SumiSelectorSize = .standard,
        showsChevron: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 9) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovering ? Sumi.seal : Sumi.muted)
            }
            Text(title)
                .font(size == .compact ? Sumi.label(size.fontSize) : Sumi.body(size.fontSize))
                .tracking(size == .compact ? 1.1 : 0)
                .foregroundStyle(Sumi.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: showsChevron ? 8 : 0)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHovering ? Sumi.seal : Sumi.muted)
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .frame(maxWidth: size == .standard ? .infinity : nil, minHeight: size.height, alignment: .leading)
        .background(isHovering ? Sumi.softPaper : Sumi.paper)
        .overlay { Rectangle().stroke(isHovering ? Sumi.seal : Sumi.rule, lineWidth: 1) }
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// A shared, fully Sumi-styled dropdown surface.
///
/// Native macOS `Menu` and `.menu` pickers ignore the app's visual language,
/// so every selection menu should be composed from this primitive instead.
struct SumiDropdown<Label: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let minimumMenuWidth: CGFloat
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: (_ dismiss: @escaping () -> Void) -> Content

    @State private var isExpanded = false

    init(
        minimumMenuWidth: CGFloat = 216,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping (_ dismiss: @escaping () -> Void) -> Content
    ) {
        self.minimumMenuWidth = minimumMenuWidth
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 4 : 0) {
            Button {
                isExpanded.toggle()
            } label: {
                label()
                    .overlay {
                        if isExpanded {
                            Rectangle().stroke(Sumi.ink, lineWidth: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])
            .accessibilityHint(isExpanded ? "Dismiss options" : "Show options")

            if isExpanded {
                VStack(spacing: 0) {
                    content { isExpanded = false }
                }
                .frame(minWidth: minimumMenuWidth, alignment: .leading)
                .background(Sumi.paper)
                .overlay { Rectangle().stroke(Sumi.ink, lineWidth: 1) }
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isExpanded)
    }
}

struct SumiDropdownOption: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let isDestructive: Bool
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 14)
                }
                Text(title)
                    .font(Sumi.body(12))
                    .lineLimit(1)
                Spacer(minLength: 16)
                Text(isSelected ? "SELECTED" : "")
                    .font(Sumi.label(7))
                    .sumiLabelTracking()
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var foregroundColor: Color {
        if isSelected { return Sumi.paper }
        if isDestructive { return Sumi.sealDeep }
        return Sumi.ink
    }

    private var backgroundColor: Color {
        if isSelected { return Sumi.ink }
        if isHovering { return isDestructive ? Sumi.sealWash : Sumi.softPaper }
        return Sumi.paper
    }
}

struct SumiDropdownDivider: View {
    var body: some View {
        Rectangle().fill(Sumi.rule).frame(height: 1)
    }
}

struct SumiDateField: View {
    let label: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents

    init(_ label: String, selection: Binding<Date>, displayedComponents: DatePickerComponents) {
        self.label = label
        _selection = selection
        self.displayedComponents = displayedComponents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            DatePicker(label, selection: $selection, displayedComponents: displayedComponents)
                .labelsHidden()
                .datePickerStyle(.field)
                .font(Sumi.body(13))
                .tint(Sumi.seal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Sumi.paper)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
        }
    }
}

struct SumiStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueLabel: (Int) -> String

    init(
        _ label: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        valueLabel: @escaping (Int) -> String = { String($0) }
    ) {
        self.label = label
        _value = value
        self.range = range
        self.step = step
        self.valueLabel = valueLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            HStack(spacing: 0) {
                adjustmentButton(symbol: "minus", adjustment: -step, disabled: value <= range.lowerBound)
                Text(valueLabel(value))
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(label), \(valueLabel(value))")
                adjustmentButton(symbol: "plus", adjustment: step, disabled: value >= range.upperBound)
            }
            .frame(height: 40)
            .background(Sumi.paper)
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
        }
    }

    private func adjustmentButton(symbol: String, adjustment: Int, disabled: Bool) -> some View {
        Button {
            value = min(range.upperBound, max(range.lowerBound, value + adjustment))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
        .disabled(disabled)
        .accessibilityLabel(adjustment > 0 ? "Increase \(label)" : "Decrease \(label)")
    }
}

struct SumiChoiceRail<Option: Hashable>: View {
    @State private var hoveredOption: Option?

    let label: String
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let help: (Option) -> String?
    let isOptionEnabled: (Option) -> Bool

    init(
        _ label: String,
        options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String,
        help: @escaping (Option) -> String? = { _ in nil },
        isOptionEnabled: @escaping (Option) -> Bool = { _ in true }
    ) {
        self.label = label
        self.options = options
        _selection = selection
        self.title = title
        self.help = help
        self.isOptionEnabled = isOptionEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    let choice = Button {
                        selection = option
                    } label: {
                        Text(title(option))
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(optionForeground(option))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(optionBackground(option))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOptionEnabled(option))
                    .accessibilityValue(selection == option ? "Selected" : "Not selected")

                    if let helpText = help(option) {
                        choice
                            .accessibilityHint(Text(helpText))
                            .onHover { isHovering in
                                if isHovering {
                                    hoveredOption = option
                                } else if hoveredOption == option {
                                    hoveredOption = nil
                                }
                            }
                    } else {
                        choice
                    }

                    if index < options.count - 1 {
                        Rectangle().fill(Sumi.rule).frame(width: 1, height: 40)
                    }
                }
            }
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }

            if let hoveredOption, let helpText = help(hoveredOption) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(hoveredOption))
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.ink)
                    Text(helpText)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Sumi.mist)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                .accessibilityHidden(true)
            }
        }
    }

    private func optionForeground(_ option: Option) -> Color {
        guard isOptionEnabled(option) else { return Sumi.muted }
        return selection == option ? Sumi.paper : Sumi.ink
    }

    private func optionBackground(_ option: Option) -> Color {
        guard isOptionEnabled(option) else { return Sumi.mist }
        return selection == option ? Sumi.ink : Sumi.paper
    }
}

struct SumiChoiceList<Option: Hashable>: View {
    let label: String
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let isOptionEnabled: (Option) -> Bool

    init(
        _ label: String,
        options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String,
        isOptionEnabled: @escaping (Option) -> Bool = { _ in true }
    ) {
        self.label = label
        self.options = options
        _selection = selection
        self.title = title
        self.isOptionEnabled = isOptionEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    Button {
                        selection = option
                    } label: {
                        HStack(spacing: 12) {
                            Text(title(option))
                                .font(Sumi.label(8))
                                .sumiLabelTracking()
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(optionForeground(option))
                            Spacer(minLength: 12)
                            Text(optionState(option))
                                .font(Sumi.label(7))
                                .sumiLabelTracking()
                                .foregroundStyle(optionForeground(option))
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(optionBackground(option))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOptionEnabled(option))
                    .accessibilityValue(optionState(option))

                    if index < options.count - 1 {
                        Rectangle().fill(Sumi.rule).frame(height: 1)
                    }
                }
            }
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
        }
    }

    private func optionState(_ option: Option) -> String {
        if !isOptionEnabled(option) { return "UNAVAILABLE" }
        return selection == option ? "SELECTED" : "AVAILABLE"
    }

    private func optionForeground(_ option: Option) -> Color {
        guard isOptionEnabled(option) else { return Sumi.muted }
        return selection == option ? Sumi.paper : Sumi.ink
    }

    private func optionBackground(_ option: Option) -> Color {
        guard isOptionEnabled(option) else { return Sumi.mist }
        return selection == option ? Sumi.ink : Sumi.paper
    }
}

struct SumiConfirmationSheet: View {
    let eyebrow: String
    let title: String
    let message: String
    let confirmTitle: String
    let confirmRole: SumiActionRole
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(title)
                    .font(Sumi.display(26))
                    .foregroundStyle(Sumi.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Sumi.mist)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            Text(message)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)

            HStack(spacing: 12) {
                Button("CANCEL", action: cancel)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button(action: confirm) {
                    Text(confirmTitle).frame(maxWidth: .infinity)
                }
                    .buttonStyle(SumiActionButtonStyle(role: confirmRole, size: .large))
            }
            .padding(24)
            .background(Sumi.softPaper)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        }
        .frame(width: 460)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.ink, lineWidth: 1) }
    }
}

struct SumiModalOverlay<Content: View>: View {
    let dismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Sumi.ink.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            content
                .accessibilityElement(children: .contain)
        }
        .transition(.opacity)
        .zIndex(1_000)
    }
}

extension View {
    func sumiLabelTracking() -> some View {
        tracking(1.5)
            .textCase(.uppercase)
    }

}
