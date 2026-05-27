import SwiftUI

// MARK: - DancingMouseApp
//
// SwiftUI entry point. The whole UI lives in a `MenuBarExtra` — there's no
// main window, no Dock icon (see `LSUIElement` in `Info.plist`).
//
// Responsibilities at this layer are deliberately tiny:
//   1. Construct the long-lived `DanceOrchestrator` (the brain) and
//      `HotkeyManager` (global ⌘⇧1-4 + Esc).
//   2. Ensure the process is hidden from the Dock even when launched via
//      `swift run` (where `Info.plist` isn't available).
//   3. Run the Accessibility-permission prompt on first launch.
//   4. Wire SwiftUI bindings → orchestrator state, so every slider, toggle
//      and picker in the menu mutates a single observable model.

@main
struct DancingMouseApp: App {
    @State private var orchestrator = DanceOrchestrator()
    private let hotkeyManager = HotkeyManager()

    init() {
        // When running outside a .app bundle (e.g. `swift run`), LSUIElement from
        // Info.plist isn't available, so hide from Dock programmatically.
        if Bundle.main.bundleIdentifier == nil {
            NSApplication.shared.setActivationPolicy(.accessory)
        }

        // Check accessibility on launch.
        AccessibilityGuard.ensureAccessibility()

        // Wire hotkey manager.
        hotkeyManager.orchestrator = orchestrator
        hotkeyManager.start()
    }

    var body: some Scene {
        MenuBarExtra {
            DanceMenuView(orchestrator: orchestrator)
        } label: {
            Image(systemName: "cursor.rays")
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating.speed(0.5), isActive: orchestrator.state == .dancing)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Main Menu View

struct DanceMenuView: View {
    @Bindable var orchestrator: DanceOrchestrator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            patternSection
            Divider()
            controlsSection
            Divider()
            trailSection
            Divider()
            idleTriggerSection
            Divider()
            footerSection
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            DancingHeaderIcon()
            Text("Dancing Mouse")
                .font(.headline)
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(orchestrator.state == .dancing ? "Dancing" : "Idle")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(orchestrator.state == .dancing ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2))
            )
    }

    // MARK: - Pattern Selection

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pattern")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Pattern", selection: $orchestrator.selectedPattern) {
                ForEach(DancePattern.allCases) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if orchestrator.selectedPattern == .handwriting {
                TextField("Text to write...", text: $orchestrator.handwritingText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Controls")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Speed")
                Slider(value: $orchestrator.speedMultiplier, in: 0.25...3.0, step: 0.25)
                Text(String(format: "%.1fx", orchestrator.speedMultiplier))
                    .monospacedDigit()
                    .frame(width: 35)
            }

            Picker("Easing", selection: $orchestrator.easingPreset) {
                ForEach(EasingPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }

            Toggle("Repeat", isOn: $orchestrator.shouldRepeat)
            Toggle("Restore cursor position", isOn: $orchestrator.restoreCursor)

            startStopButton
        }
    }

    private var startStopButton: some View {
        Button(action: { orchestrator.toggle() }) {
            HStack {
                Image(systemName: orchestrator.state == .dancing ? "stop.fill" : "play.fill")
                Text(orchestrator.state == .dancing ? "Stop" : "Start Dance")
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])
    }

    // MARK: - Trail Settings

    private var trailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cursor Trail")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Bindable(orchestrator.trailConfig).enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if orchestrator.trailConfig.enabled {
                HStack {
                    Text("Length")
                    Slider(
                        value: Binding(
                            get: { Double(orchestrator.trailConfig.length) },
                            set: { orchestrator.trailConfig.length = Int($0) }
                        ),
                        in: 5...50,
                        step: 1
                    )
                    Text("\(orchestrator.trailConfig.length)")
                        .monospacedDigit()
                        .frame(width: 25)
                }

                HStack {
                    Text("Size")
                    Slider(value: Bindable(orchestrator.trailConfig).dotSize, in: 2...20, step: 1)
                    Text(String(format: "%.0f", orchestrator.trailConfig.dotSize))
                        .monospacedDigit()
                        .frame(width: 25)
                }

                Picker("Color", selection: Bindable(orchestrator.trailConfig).colorPreset) {
                    ForEach(TrailColorPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }

                Picker("Fade", selection: Bindable(orchestrator.trailConfig).fadeStyle) {
                    ForEach(TrailFadeStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }
        }
    }

    // MARK: - Idle Trigger

    private var idleTriggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Idle Trigger")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $orchestrator.idleTriggerEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if orchestrator.idleTriggerEnabled {
                HStack {
                    Text("Delay")
                    Slider(
                        value: $orchestrator.idleDelay,
                        in: 3...120,
                        step: 1
                    )
                    Text("\(Int(orchestrator.idleDelay))s")
                        .monospacedDigit()
                        .frame(width: 35)
                }

                Picker("Pattern", selection: $orchestrator.idlePattern) {
                    ForEach(DancePattern.allCases) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }

                if orchestrator.idlePattern == .handwriting {
                    TextField("Text to write...", text: $orchestrator.handwritingText)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Starts at cursor position after \(Int(orchestrator.idleDelay))s of no movement")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hotkeys")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Group {
                HotkeyLabel(keys: "⌘⇧1", action: "Circle")
                HotkeyLabel(keys: "⌘⇧2", action: "Window Outline")
                HotkeyLabel(keys: "⌘⇧3", action: "Scribble")
                HotkeyLabel(keys: "⌘⇧4", action: "Handwriting")
                HotkeyLabel(keys: "Esc", action: "Stop / Any input stops")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

// MARK: - Hotkey Label

private struct HotkeyLabel: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(keys)
                .fontDesign(.monospaced)
                .frame(width: 50, alignment: .leading)
            Text(action)
        }
    }
}

// MARK: - Animated Header Icon

/// Continuously animated cursor icon for the window header.
private struct DancingHeaderIcon: View {
    @State private var phase = false

    var body: some View {
        Image(systemName: "cursor.rays")
            .font(.title2)
            .foregroundStyle(.purple)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating.speed(0.5), isActive: true)
            .rotationEffect(.degrees(phase ? 10 : -10))
            .scaleEffect(phase ? 1.1 : 0.95)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: phase
            )
            .onAppear { phase = true }
    }
}
