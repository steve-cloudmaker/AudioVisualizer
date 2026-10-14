import Foundation

/// A capture device the host can select. Wired aux adapters (Lightning/USB-C → 3.5mm) show up as `headsetMic`.
struct AudioInputInfo: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: Kind

    enum Kind: String, Sendable {
        case headsetMic
        case lineIn
        case usb
        case bluetooth
        case builtIn
        case aggregate
        case unknown
    }

    var isWiredExternal: Bool {
        switch kind {
        case .headsetMic, .lineIn, .usb: return true
        default: return false
        }
    }

    var shortLabel: String {
        switch kind {
        case .headsetMic: return "AUX"
        case .lineIn: return "LINE"
        case .usb: return "USB"
        case .bluetooth: return "BT"
        case .builtIn: return "BUILT-IN"
        case .aggregate: return "AGG"
        case .unknown: return "IN"
        }
    }
}

/// Pure ranking so a 3.5mm / USB adapter wins over the built-in mic without touching AVFoundation in tests.
enum InputRouter {
    static func score(_ kind: AudioInputInfo.Kind) -> Int {
        switch kind {
        case .headsetMic: return 0
        case .lineIn: return 1
        case .usb: return 2
        case .aggregate: return 3
        case .bluetooth: return 4
        case .unknown: return 5
        case .builtIn: return 6
        }
    }

    /// Prefer a newly attached wired mic (aux adapter, USB interface). Otherwise keep the current choice.
    static func preferred(
        among inputs: [AudioInputInfo],
        previousID: String?,
        preferNewWired: Bool
    ) -> AudioInputInfo? {
        guard !inputs.isEmpty else { return nil }

        if preferNewWired, let wired = bestWired(in: inputs) {
            return wired
        }
        if let previousID, let existing = inputs.first(where: { $0.id == previousID }) {
            return existing
        }
        if let wired = bestWired(in: inputs) {
            return wired
        }
        return inputs.min { lhs, rhs in
            let ls = score(lhs.kind)
            let rs = score(rhs.kind)
            if ls != rs { return ls < rs }
            return lhs.name < rhs.name
        }
    }

    static func bestWired(in inputs: [AudioInputInfo]) -> AudioInputInfo? {
        inputs
            .filter(\.isWiredExternal)
            .min { score($0.kind) < score($1.kind) || (score($0.kind) == score($1.kind) && $0.name < $1.name) }
    }

    /// AVAudioSession.Port raw values plus CoreAudio transport FourCCs.
    static func kind(portTypeRaw: String) -> AudioInputInfo.Kind {
        switch portTypeRaw {
        case "MicrophoneWired", "HeadsetMic":
            return .headsetMic
        case "LineIn":
            return .lineIn
        case "USBAudio", "USB":
            return .usb
        case "BluetoothHFP", "BluetoothA2DP", "BluetoothLE":
            return .bluetooth
        case "MicrophoneBuiltIn", "BuiltInMic", "BuiltInSpeaker":
            return .builtIn
        default:
            let lower = portTypeRaw.lowercased()
            if lower.contains("usb") { return .usb }
            if lower.contains("headset") || lower.contains("wired") { return .headsetMic }
            if lower.contains("line") { return .lineIn }
            if lower.contains("bluetooth") { return .bluetooth }
            if lower.contains("builtin") || lower.contains("built-in") || lower.contains("built_in") {
                return .builtIn
            }
            if lower.contains("aggregate") { return .aggregate }
            return .unknown
        }
    }

    static func kind(transport: UInt32) -> AudioInputInfo.Kind {
        switch transport {
        case 0x626C746E: return .builtIn          // 'bltn'
        case 0x75736220: return .usb              // 'usb '
        case 0x70636920: return .usb              // 'pci '
        case 0x31333934: return .usb              // '1394'
        case 0x626C7565: return .bluetooth        // 'blue'
        case 0x626C6561: return .bluetooth        // 'blea'
        case 0x68646D69: return .lineIn           // 'hdmi'
        case 0x64707274: return .lineIn           // 'dprt'
        case 0x67727020: return .aggregate        // 'grp '
        case 0x61616767: return .aggregate        // 'aagg'
        default: return .unknown
        }
    }
}
