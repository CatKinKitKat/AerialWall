# Research: AerialWall and macOS Tahoe Wallpaper Architecture

This document tracks reverse-engineering discoveries made during the development of AerialWall for macOS 26 Tahoe. It reflects the actual investigation path, including dead ends, so future contributors can understand why the code is shaped the way it is.

---

## 1. The Architectural Shift from macOS 15 to macOS 26

Previous macOS versions (Sonoma, Sequoia) managed Aerial wallpapers via:
- A system-level SQLite database at `/Library/Application Support/com.apple.idleassetsd/Aerial.sqlite`
- The `idleassetsd` daemon for asset management
- Videos stored under `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/`

In macOS 26 Tahoe this was completely replaced:

| Component | macOS 15 | macOS 26 |
|-----------|----------|----------|
| Registry | SQLite (Aerial.sqlite) | JSON (entries.json) |
| Daemon | idleassetsd | com.apple.wallpaper.agent |
| Storage | /Library/... (system, root-owned) | ~/Library/... (user-owned) |
| Discovery | Explicit DB rows | UUID-based filename convention |

The privilege change is significant: everything is now in the user's home directory, so user-space apps can manage wallpapers without root or SMAppService.

### entries.json structure

Asset entries require 12 fields including `id`, `localizedNameKey` (displayed literally when not found in `TVIdleScreenStrings.bundle`), `categories`, `subcategories`, `url-4K-SDR-240FPS`, and `previewImage`. URL fields can point to Apple's CDN; the system auto-discovers local files at `videos/<UUID>.mov` and `thumbnails/<UUID>.png` by UUID convention regardless of the URL value.

---

## 2. The Unlock-to-Gray Bug: A Full Investigation

Custom wallpapers would play correctly on the lock screen but revert to a gray background immediately after unlock. This took the longest to diagnose and went through several wrong hypotheses before the real cause was found.

### Wrong hypotheses tested

- **file:// vs https:// URLs in entries.json** — The URL scheme in `url-4K-SDR-240FPS` and `previewImage` was initially thought to matter. Tests showed it does not affect behaviour; the system always uses the local UUID-matched file.
- **Custom category interference** — A custom "AerialWall" top-level category was suspected. Test B (Apple bytes under our category) passed cleanly, ruling this out.
- **B-frames and HEVC level** — Forcing B-frames, adjusting HEVC levels, and matching `has_b_frames=4` had no effect.
- **Frame rate matching (240fps)** — Re-encoding to 240fps made transcodes 5x slower with no improvement.
- **start_time offset (V44)** — VideoToolbox adds a 1-frame PTS offset (~33ms at 30fps). Forcing `start_time=0` via `setpts=PTS-STARTPTS` was necessary but not sufficient on its own.

### The actual cause: HEVC temporal sub-layers (V48)

Live log capture during the lock/unlock cycle revealed the critical signal:

```
[wallpaper:video-sample-reader]
  skipping frame with TSAINFO level: <private> as our level is 3
  Sample buffers dropped in the VideoSampleReader.nextSample(): 2
...
sharedWallpaperRemovalTriggerFired
```

`WallpaperAerialsExtension` filters frames by HEVC `temporal_id`. Apple's stock aerial clips use a 5-layer temporal hierarchy (`temporal_id` 0 through 4). Standard single-layer HEVC has all frames at `temporal_id=0`. The wallpaper reader skips every frame, the wallpaper is marked inactive, and the display falls back to gray.

The reader uses two selection levels depending on render path:
- `our level is 2` -- lock/unlock transition path, accepts `temporal_id >= 1`
- `our level is 3` -- desktop apply path, accepts `temporal_id >= 3`

### The fix

`AVAssetWriter` with `kVTCompressionPropertyKey_BaseLayerFrameRate = srcFps / 2` causes VideoToolbox to emit a 2-layer hierarchical encode with TRAIL_R frames at `temporal_id=0` and TSA_N frames at `temporal_id=1`. This satisfies the level-2 reader used for lock/unlock, and empirical testing showed it also satisfies the level-3 reader for desktop apply (confirmed via the A/B/C/D variant test below).

ffmpeg cannot produce temporal sub-layers. Its `hevc_videotoolbox` wrapper does not expose `BaseLayerFrameRate`. This is why the pure-native `AVAssetWriter` approach is required.

### The A/B/C/D variant test

To eliminate content-specific variables, four variants were generated from Apple's own Tahoe Day clip and tested:

| Test | Config | Apply | Lock | Unlock |
|------|--------|-------|------|--------|
| A | 4K, single-layer | Pass | Pass | Gray |
| B | 4K, 2-layer | Pass | Pass | Pass |
| C | 2880x1620, 4-layer | Pass | Pass | Pass |
| D | 2880x1620, single-layer | Pass | Pass | Gray |

Result: temporal sub-layers are required; 2 layers is sufficient; resolution does not matter.

---

## 3. The Native Transcode Pipeline

Because ffmpeg cannot produce temporal sub-layers, the transcode pipeline is entirely native Apple frameworks:

```
AVURLAsset (input)
  -> AVMutableVideoComposition (scale, pad, colour, setpts)
  -> AVAssetReaderVideoCompositionOutput
  -> AVAssetWriterInput (HEVC Main10, BaseLayerFrameRate=srcFps/2)
  -> AVAssetWriter (.mov, QuickTime container)
```

### Required output parameters

| Parameter | Value | Reason |
|-----------|-------|--------|
| Codec | HEVC (hvc1 tag) | hev1 tag causes playback issues |
| Profile | Main 10 | 10-bit, matches Apple stock |
| Pixel format | yuv420p10le | 10-bit 4:2:0 |
| Container | QuickTime .mov | major_brand=qt |
| Audio | None | Stripped during transcode |
| start_time | 0.000000 | Wallpaper extension seeks to t=0 for still frame |
| Temporal layers | >= 2 | TSA frames required by video-sample-reader |

### Subprocess hazards (ffmpeg is still used in tests)

- **Pipe buffer deadlock (B8):** The kernel pipe buffer is ~64KB. ffmpeg writes verbose stderr; if no consumer drains it, ffmpeg blocks on `write(2)` indefinitely. `FileHandle.readabilityHandler` must drain stderr continuously.
- **TTY hang (B9):** Without `-nostdin`, ffmpeg calls `tcsetattr` on stdin. As a background process this hangs. Always pass `-nostdin`.

---

## 4. entries.json Integrity

### Category representative ID (B13)

`WallpaperAerialsExtension` validates the entire manifest on load. If any category's `representativeAssetID` references a UUID that does not exist in `assets`, the extension refuses to surface any aerial category in System Settings -- including Apple's stock Landscapes, Cities, etc.

On removal: when the last asset belonging to a custom category is removed, the category must also be removed. When the representative asset is removed but others remain, the representative must be reassigned. See `InjectionEngine.remove(id:from:maintaining:)`.

### URL fields

`previewImage` and `url-4K-SDR-240FPS` must use `https://` scheme. Fields with `file://` paths caused inconsistent behaviour in some render paths.

### Schema version gate

The current manifest format is `version=1`. `InjectionEngine` gates all mutations on this version; if Apple ships a new schema, injection is refused cleanly rather than corrupting an unknown format.

---

## 5. Wallpaper Selection (Index.plist)

The currently applied wallpaper is stored in:

```
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

The relevant structure is a binary-encoded sub-plist inside `AllSpacesAndDisplays.Linked.Content.Choices[0].Configuration`:

```swift
["assetID": "<UUID>"]
```

Writing this plist and signalling `WallpaperAgent` (SIGTERM, launchd respawns it) applies the wallpaper without requiring System Settings to be open.

`launchctl kickstart -k` is SIP-blocked for system-signed agents on Tahoe even in the user domain. Plain `kill <pid>` works.

---

## 6. Desktop App Activation (B11)

Swift executables built with SwiftPM and launched without a `.app` bundle default to `UIElement` activation policy. Sheet windows never become the key window, silently dropping all keyboard input.

Fix: register `NSApplicationDelegateAdaptor` and call `NSApp.setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps: true)` in `applicationDidFinishLaunching`.

---

## 7. WebM and AVFoundation Compatibility

`AVAssetReader` does not support the WebM container on macOS 26. Loading a WebM file via `loadTracks(withMediaType: .video)` throws `NSOSStatusErrorDomain -17913`. Users must convert to `.mp4` or `.mov` first.

---

## 8. References

- `SPEC.md` -- full invariant list (V1-V50+) and bug backpropagation log (B1-B20+)
- `Sources/AerialWallKit/TranscodeEngine.swift` -- native VT transcode pipeline
- `Sources/AerialWallKit/InjectionEngine.swift` -- entries.json mutation with integrity checks
- `Sources/AerialWallKit/PersistenceWatcher.swift` -- FSEvents watcher for manifest re-pulls
