import SwiftUI
import ZoidCoachCore

struct VoiceMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: VoiceConversationModel
    @State private var apiKey = ""
    @State private var keyMessage = ""
    @State private var textCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ZOID VOICE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                    Text(model.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(model.state.rawValue)
            }

            if !model.liveCaption.isEmpty {
                Text(model.liveCaption)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Button(model.state == .idle || model.state == .disconnected ? "TALK" : "STOP") {
                    model.toggleSession()
                }
                .buttonStyle(.borderedProminent)

                Button(model.isMuted ? "UNMUTE" : "MUTE") {
                    model.setMuted(!model.isMuted)
                }
                .buttonStyle(.bordered)
                .disabled(model.state == .idle)
            }


            if let approval = model.pendingApproval {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONFIRM EXTERNAL ACTION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(approval.reason)
                        .font(.system(size: 12))
                    HStack {
                        Button("APPROVE") { model.resolvePendingApproval(approved: true) }
                            .buttonStyle(.borderedProminent)
                        Button("DENY") { model.resolvePendingApproval(approved: false) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                TextField("Type a command", text: $textCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendText)
                Button("SEND", action: sendText)
                    .disabled(textCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Toggle("Listen locally for Hey Zoid", isOn: $model.wakeWordEnabled)
                .font(.system(size: 12))
            Picker("Shortcut", selection: $model.hotKeyPreset) {
                ForEach(VoiceHotKeyPreset.allCases) { preset in Text(preset.label).tag(preset) }
            }
            .font(.system(size: 12))
            Text(model.wakeWord.availabilityMessage)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if let usage = model.usage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("GEMINI MONTHLY CAP")
                        Spacer()
                        Text(usageLabel(usage))
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    ProgressView(value: Double(usage.consumedUSDMicros), total: Double(VoiceUsageLedger.hardMonthlyLimitUSDMicros))
                }
            }

            Divider()

            DisclosureGroup(model.hasAPIKey ? "Gemini key stored in Keychain" : "Add Gemini API key") {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("Gemini API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("SAVE") {
                            do {
                                try model.configureAPIKey(apiKey)
                                apiKey = ""
                                keyMessage = "Saved securely in Keychain."
                            } catch { keyMessage = error.localizedDescription }
                        }
                        Button("REMOVE") {
                            do {
                                try model.removeAPIKey()
                                keyMessage = "Gemini key removed."
                            } catch { keyMessage = error.localizedDescription }
                        }
                        .disabled(!model.hasAPIKey)
                    }
                    if !keyMessage.isEmpty {
                        Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11))

            if !model.transcript.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(model.transcript.suffix(8)) { turn in
                            Text("\(turn.role == .user ? "YOU" : "ZOID")  \(turn.text)")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Divider()
            HStack {
                Button("AGENT HEALTH") {
                    openWindow(id: "agent-lifecycle")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityIdentifier("voice-menu.agent-health")
                Text(model.hotKeyPreset.label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("QUIT") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .padding(16)
        .frame(width: 360)
        .task { model.startAlwaysAvailable() }
    }

    private var statusColor: Color {
        switch model.state {
        case .listening: .green
        case .speaking: .red
        case .thinking, .activating: .orange
        case .localFallback: .blue
        case .idle, .disconnected: .secondary
        }
    }

    private func sendText() {
        let value = textCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if model.state == .idle || model.state == .disconnected {
            model.toggleSession(source: .text)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                model.sendText(value)
            }
        } else {
            model.sendText(value)
        }
        textCommand = ""
    }

    private func usageLabel(_ usage: VoiceUsageLedger) -> String {
        let dollars = Double(usage.consumedUSDMicros) / 1_000_000
        return String(format: "$%.2f / $20.00", dollars)
    }
}
