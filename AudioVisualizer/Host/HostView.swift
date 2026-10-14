import SwiftUI

struct HostView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SceneStageView()
            chrome
            if model.permissionDenied {
                permissionOverlay
            }
        }
        .task {
            await model.startIfNeeded()
        }
        .onDisappear {
            model.stop()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.bumpChrome()
        }
        #if os(macOS)
        .onHover { hovering in
            if hovering { model.bumpChrome() }
        }
        #endif
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            footer
        }
        .opacity(model.chromeVisible || model.permissionDenied ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: model.chromeVisible)
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("VIS")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.registry.all) { scene in
                        sceneChip(scene)
                    }
                }
            }
            inputMenu
            statusDot
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55))
        .overlay(Rectangle().stroke(accent.opacity(0.35), lineWidth: 1))
    }

    private var inputMenu: some View {
        Menu {
            ForEach(model.inputs) { input in
                Button {
                    model.selectInput(input)
                } label: {
                    HStack {
                        Text("\(input.shortLabel)  \(input.name)")
                        if input.id == model.currentInputID {
                            Text("✓")
                        }
                    }
                }
            }
        } label: {
            Text(model.currentInputName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(Rectangle().stroke(accent.opacity(0.6), lineWidth: 1))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 220)
    }

    private func sceneChip(_ scene: SceneMetadata) -> some View {
        let selected = scene.id == model.selectedSceneID
        return Button {
            model.selectScene(scene.id)
        } label: {
            Text(scene.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.black : accent)
                .background(selected ? accent : Color.clear)
                .overlay(Rectangle().stroke(accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                labeledSlider("SENS", value: sensitivityBinding, range: 0.2...2.5)
                if model.inputGainSettable {
                    labeledSlider("MIC", value: gainBinding, range: 0...1)
                }
                Picker("Bands", selection: bandBinding) {
                    Text("32").tag(32)
                    Text("64").tag(64)
                    Text("128").tag(128)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Toggle("SHUFFLE", isOn: shuffleBinding)
                    .toggleStyle(.switch)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                #if os(iOS)
                Toggle("HAP", isOn: hapticsBinding)
                    .toggleStyle(.switch)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                #endif
                if model.selectedSceneID == PlinkoScene.id {
                    Button("DROP") { model.fire(.tap(.zero)) }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .buttonStyle(.plain)
                }
                if model.selectedSceneID == ClawScene.id {
                    Button("GRAB") { model.fire(.tap(.zero)) }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .buttonStyle(.plain)
                }
            }
            HStack {
                ForEach(VisualizerPreset.factory) { item in
                    Button(item.name.uppercased()) {
                        model.applyPreset(item, animated: true)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(model.preset.name == item.name ? Color.black : accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.preset.name == item.name ? accent : Color.clear)
                    .overlay(Rectangle().stroke(accent.opacity(0.5), lineWidth: 1))
                }
                Spacer()
                Text(statusText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.7))
            }
        }
        .foregroundStyle(accent)
        .padding(12)
        .background(.black.opacity(0.55))
        .overlay(Rectangle().stroke(accent.opacity(0.35), lineWidth: 1))
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Text("MICROPHONE")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
            Text("Built-in, 3.5mm aux adapter, or USB interface. Input animates scenes only — nothing is recorded or sent.")
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .foregroundStyle(accent)
        .padding(24)
        .background(Color.black.opacity(0.85))
        .overlay(Rectangle().stroke(accent, lineWidth: 1))
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    private var accent: Color {
        Color(hue: Double(model.preset.hue), saturation: Double(model.preset.saturation), brightness: 0.95)
    }

    private var dotColor: Color {
        switch model.status {
        case .running: return .green
        case .interrupted: return .yellow
        case .failed, .unauthorized: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        let bpm = Int(model.bus.snapshot().bpm.rounded())
        let bpmText = bpm > 0 ? "  \(bpm) BPM" : ""
        switch model.status {
        case .running:
            return "LIVE  \(model.currentInputName)  \(Int(model.capture.sampleRate)) Hz  \(model.capture.channelCount)ch\(bpmText)"
        case .interrupted: return "INTERRUPTED"
        case .failed(let message): return message
        case .unauthorized: return "MIC DENIED"
        case .idle: return "IDLE"
        }
    }

    private var sensitivityBinding: Binding<Float> {
        Binding(
            get: { model.preset.sensitivity },
            set: { model.setSensitivity($0) }
        )
    }

    private var gainBinding: Binding<Float> {
        Binding(
            get: { model.inputGain },
            set: { model.setInputGain($0) }
        )
    }

    private var bandBinding: Binding<Int> {
        Binding(
            get: { model.preset.bandCount },
            set: { value in
                model.preset.bandCount = value
                model.applyPreset(model.preset, animated: false)
            }
        )
    }

    private var shuffleBinding: Binding<Bool> {
        Binding(
            get: { model.preset.shuffleOnBeat },
            set: { value in
                model.preset.shuffleOnBeat = value
                model.bumpChrome()
            }
        )
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { model.preset.hapticsEnabled },
            set: { value in
                model.preset.hapticsEnabled = value
                model.bumpChrome()
            }
        )
    }

    private func labeledSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Slider(value: value, in: range)
                .frame(minWidth: 80, maxWidth: 160)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
        }
    }
}

extension VisualizerPreset: Identifiable {
    var id: String { name }
}
