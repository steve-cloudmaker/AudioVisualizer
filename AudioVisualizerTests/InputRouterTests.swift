import XCTest
@testable import AudioVisualizer

final class InputRouterTests: XCTestCase {
    func testHeadsetMicBeatsBuiltIn() {
        let builtIn = AudioInputInfo(id: "1", name: "iPad Microphone", kind: .builtIn)
        let aux = AudioInputInfo(id: "2", name: "Headset Microphone", kind: .headsetMic)
        let chosen = InputRouter.preferred(among: [builtIn, aux], previousID: builtIn.id, preferNewWired: true)
        XCTAssertEqual(chosen?.id, aux.id)
    }

    func testUSBBeatsBluetooth() {
        let usb = AudioInputInfo(id: "u", name: "Scarlett 2i2", kind: .usb)
        let bt = AudioInputInfo(id: "b", name: "AirPods", kind: .bluetooth)
        let chosen = InputRouter.preferred(among: [bt, usb], previousID: nil, preferNewWired: true)
        XCTAssertEqual(chosen?.kind, .usb)
    }

    func testKeepsPreviousWhenNoNewWiredRequested() {
        let builtIn = AudioInputInfo(id: "1", name: "Built-in", kind: .builtIn)
        let usb = AudioInputInfo(id: "2", name: "USB", kind: .usb)
        let chosen = InputRouter.preferred(among: [builtIn, usb], previousID: builtIn.id, preferNewWired: false)
        XCTAssertEqual(chosen?.id, builtIn.id)
    }

    func testWiredStillWinsIfNoPrevious() {
        let builtIn = AudioInputInfo(id: "1", name: "Built-in", kind: .builtIn)
        let line = AudioInputInfo(id: "3", name: "Line In", kind: .lineIn)
        let chosen = InputRouter.preferred(among: [builtIn, line], previousID: nil, preferNewWired: false)
        XCTAssertEqual(chosen?.kind, .lineIn)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(InputRouter.preferred(among: [], previousID: nil, preferNewWired: true))
    }

    func testPortTypeHeadsetMapsToAux() {
        XCTAssertEqual(InputRouter.kind(portTypeRaw: "MicrophoneWired"), .headsetMic)
        XCTAssertEqual(InputRouter.kind(portTypeRaw: "USBAudio"), .usb)
        XCTAssertEqual(InputRouter.kind(portTypeRaw: "MicrophoneBuiltIn"), .builtIn)
    }

    func testTransportFourCC() {
        XCTAssertEqual(InputRouter.kind(transport: 0x626C746E), .builtIn)
        XCTAssertEqual(InputRouter.kind(transport: 0x75736220), .usb)
        XCTAssertEqual(InputRouter.kind(transport: 0x626C7565), .bluetooth)
    }
}

final class TempoTrackerTests: XCTestCase {
    func testTracks120BPM() {
        let tracker = TempoTracker()
        var bpm: Float = 0
        for i in 0..<8 {
            bpm = tracker.ingest(onset: true, time: Double(i) * 0.5)
        }
        XCTAssertEqual(bpm, 120, accuracy: 2)
    }

    func testIgnoresSparseNoise() {
        let tracker = TempoTracker()
        _ = tracker.ingest(onset: true, time: 0)
        _ = tracker.ingest(onset: true, time: 3)
        let bpm = tracker.ingest(onset: true, time: 6)
        XCTAssertEqual(bpm, 0)
    }
}

final class SVGSkinLoaderTests: XCTestCase {
    func testParsesIDsIntoModulators() {
        let xml = """
        <svg><g id="flame"/><path id="band-12"/><circle id="key-a"/></svg>
        """
        let skin = SVGSkinLoader.parse(xml: xml, name: "Test", resource: "test.svg")
        XCTAssertEqual(skin.layers.count, 3)
        XCTAssertEqual(skin.layers.first { $0.id == "flame" }?.modulator, .bass)
        XCTAssertEqual(skin.layers.first { $0.id == "band-12" }?.bandIndex, 12)
        XCTAssertEqual(skin.layers.first { $0.id == "key-a" }?.chromaIndex, 9)
    }
}
