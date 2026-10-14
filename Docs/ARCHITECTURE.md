# Architecture

```
Microphone (built-in, 3.5mm aux, USB)
        │
        ▼
AVAudioEngine tap  ──copies only──► AudioRingBuffer
        │
        ▼
FeatureExtractor (Accelerate FFT, log RTA, envelopes, onset, chroma, stereo, AGC, BPM)
        │
        ▼
FeatureBus snapshot
        │
        ├── Canvas scenes   (Analyzer Strip, Micrographic)
        ├── Metal scenes    (Hall of Torches)
        └── SpriteKit scenes (Plinko, Claw)
```

## Why this split

Winamp was a **host**. MilkDrop, AVS, and skins all ate the same features. Scenes here must never run a second FFT.

The audio callback only interleaves floats into the ring. Analysis lives on `studio.audiovisualizer.analysis`. Renderers snapshot `FeatureBus` on the display clock (TimelineView, MTKView, SKScene.update).

## Capture

`AudioCapture` puts the iOS session in `.measurement` mode and disables voice processing so analog adapters and USB interfaces stay unprocessed. `InputRouter` ranks ports:

1. Headset / wired aux (`MicrophoneWired`)
2. Line in
3. USB audio
4. Bluetooth
5. Built-in

Plugging in a Lightning or USB-C 3.5mm adapter fires `newDeviceAvailable`; the host selects that mic and rebuilds the tap at the new sample rate and channel count. Mono aux is duplicated to stereo so the goniometer still has a path.

macOS lists Core Audio input devices and listens for hardware attach. Selecting a device sets `kAudioOutputUnitProperty_CurrentDevice` on the input AudioUnit.

## Features

`AudioFeatures` is an immutable snapshot: waveform, log bands with peak hold, bass/mid/treble, onset pulse, 12-class chroma, correlation/width/goniometer XY, AGC gain, noise floor, silence gate, BPM.

Envelopes (fast attack, slow release) and auto-gain are what make motion feel like dancing instead of raw FFT jitter. Silence decays to rest.

## Scenes

`VisualizerScene` is the plugin contract (`attach` / `update` / `handle` / `detach`). `SceneFactory` + `SceneRegistry` swap scenes without restarting the engine.

Presets are Codable JSON with 1.2s parameter interpolation (MilkDrop-style crossfade of sensitivity/hue).

An external display, when connected, mirrors a **second** Analyzer Strip instance from the same bus. It does not call `tickFrame`, so shuffle/haptics stay single-owner.

## Legal

Hall of Torches borrows the CRT/masonry *language*, not Helium's UI. Micrographics Vol.1 is not shipped; the skin format plus original motifs cover that slot until you drop in licensed SVGs.
