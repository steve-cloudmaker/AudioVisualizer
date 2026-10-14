# Audio Visualizer

A native Swift visualizer host for **iPadOS** and **macOS**. One microphone analysis pipeline publishes musical features; swappable scenes subscribe to that bus.

## Run

Open `AudioVisualizer.xcodeproj` and run the **AudioVisualizer** scheme on a Mac or iPad.

Grant microphone access. Point the device at a speaker, or plug in a **3.5mm aux adapter** / USB interface. The host prefers wired external mics over the built-in capsule when they appear.

Input animates scenes only. Nothing is recorded or sent.

## Scenes

| Scene | Renderer | Mapping |
| --- | --- | --- |
| Analyzer Strip | Canvas | Waterfall, waveform, chromagram, loudness/BPM, response, goniometer |
| Hall of Torches | Metal | Helium-inspired brick arcade, chroma torches, CRT meters |
| Plinko | SpriteKit | Buckets = log RTA, balls = onsets |
| Claw | SpriteKit | Balls = bands, corner window = solo of the grabbed band |
| Micrographic | Canvas | Built-in vector motifs; optional SVGs from Application Support |

Chrome auto-hides. Tap to bring it back. The header menu lists capture devices (AUX / USB / built-in).

## External skins

Drop simple SVGs into:

`~/Library/Application Support/AudioVisualizer/Skins/`

Element `id`s map onto the feature bus (`bass`, `treble`, `band-03`, `key-a`, `onset`, …). Paid packs are not bundled.

## Tests

```bash
xcodebuild -scheme AudioVisualizer -destination 'platform=macOS' test
```

DSP fixtures cover FFT peaks, envelopes, onsets, chroma, stereo, AGC, ring wrap, input ranking, tempo, and SVG id mapping.

## Architecture

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).
