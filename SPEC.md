# SPEC — AerialWall

> v2 — Tahoe-only after live probe on macOS 26.4.1. v1 (macOS-15 SQLite model) superseded; drift recorded in §B.

## §G

FOSS macOS app, Tahoe-only. User videos → transcode HEVC Main10 → drop in `~/Library/Application Support/com.apple.wallpaper/aerials/{videos,thumbnails}/<UUID>.{mov,png}` + append entry to `entries.json` → appear as native wallpaper in System Settings, persist across `WallpaperAgent` restarts and Apple manifest re-pulls.

## §C

- target: macOS 26 (Tahoe) ≥ 26.4
- Swift 6, Xcode 16+
- arch: arm64 + x86_64
- license: MIT
- distro: DMG / Homebrew cask, ⊥ App Store
- sandbox: false (writes `~/Library/...`)
- Hardened Runtime: on
- notarized: ! (Gatekeeper)
- SIP disable: ⊥ required — works with SIP on (verified)
- privilege: user-domain only, ⊥ root, ⊥ SMAppService, ⊥ XPC privileged helper
- assumes `entries.json.version == 1` & `localizationVersion == "22L-1"`; probe @ runtime

## §I

### paths (verbatim, user-level)

```
~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json       # canonical asset+category JSON, v1, ~185KB stock
~/Library/Application Support/com.apple.wallpaper/aerials/manifest/manifest.tar       # Apple-signed manifest tarball, mode 0600
~/Library/Application Support/com.apple.wallpaper/aerials/manifest/manifest.source    # remote tar URL (CDN)
~/Library/Application Support/com.apple.wallpaper/aerials/manifest/TVIdleScreenStrings.bundle/  # Apple-signed localizations, ⊥ modify
~/Library/Application Support/com.apple.wallpaper/aerials/videos/<UUID>.mov           # asset videos, UUID uppercase
~/Library/Application Support/com.apple.wallpaper/aerials/thumbnails/<UUID>.png       # asset thumbnails, PNG (not JPG)
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist                   # selection per screen (Apple-encoded plist)
~/Library/Preferences/com.apple.wallpaper.plist
~/Library/Preferences/com.apple.wallpaper.aerial.plist                                 # new in Tahoe
~/Library/Application Support/AerialWall/library/<UUID>.mov                            # AerialWall transcoded source-of-truth
~/Library/Application Support/AerialWall/thumbs/<UUID>.png
~/Library/Application Support/AerialWall/originals/                                    # optional, user source files
~/Library/Application Support/AerialWall/manifest.json                                 # AerialWall bookkeeping (Codable)
~/Library/LaunchAgents/com.aerialwall.agent.plist                                      # user-domain LaunchAgent
```

note: stock files in `videos/`/`thumbnails/` are user-owned (`mode 0600/0644`, owner = login user). AerialWall must mirror perms.

### daemon

```
com.apple.wallpaper.agent
  binary: /System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent
  domain: gui/<uid>
  plist:  /System/Library/LaunchAgents/com.apple.wallpaper.plist (Apple, ⊥ modify)
  respawn: KeepAlive=true → relaunches on SIGTERM via launchd
```

restart: `kill <pid>` (SIGTERM). launchd respawns ≤2s.
⊥ `launchctl kickstart -k gui/<uid>/com.apple.wallpaper.agent` → SIP exit 150 even in user domain.
PID lookup: `launchctl list | awk '$3=="com.apple.wallpaper.agent" {print $1}'`.

### entries.json schema (v1, observed)

```jsonc
{
  "version": 1,
  "initialAssetCount": 4,
  "localizationVersion": "22L-1",
  "assets": [ /* 156 stock entries */ ],
  "categories": [ /* 5 stock entries */ ]
}
```

**asset entry** — required ∀ 156/156:
```jsonc
{
  "id":                  "<UUID uppercase>",
  "accessibilityLabel":  "<str — VoiceOver label, NOT main UI display name>",
  "categories":          ["<UUID>"],          // FK → categories[].id
  "subcategories":       ["<UUID>"],          // FK → categories[].subcategories[].id
  "includeInShuffle":    true|false,
  "localizedNameKey":    "<str — display name. rendered LITERALLY if not in TVIdleScreenStrings.bundle>",
  "pointsOfInterest":    {},
  "preferredOrder":      <int — lower = earlier; -100 surfaced @ top, verified>,
  "previewImage":        "https://sylvan.apple.com/.../*.png",   // local thumbnails/<id>.png auto-discovered
  "shotID":              "<str, e.g., TA_L_002>",
  "showInTopLevel":      true|false,
  "url-4K-SDR-240FPS":   "https://sylvan.apple.com/.../*.mov"    // local videos/<id>.mov auto-discovered
}
```

optional asset field: `"group": "<str>"` (44/156 stock — grouping animated lock+desktop pairs).

**category entry**:
```jsonc
{
  "id":                       "<UUID>",
  "localizedNameKey":         "<str>",
  "localizedDescriptionKey":  "<str>",
  "preferredOrder":           <int>,
  "previewImage":             "<URL>",
  "representativeAssetID":    "<UUID>",
  "subcategories": [
    { "id": "<UUID>", "localizedNameKey": "...", "localizedDescriptionKey": "...",
      "preferredOrder": <int>, "previewImage": "<URL>", "representativeAssetID": "<UUID>" }
  ]
}
```

stock category UUIDs (do NOT modify):
- Landscapes:  `A33A55D9-EDEA-4596-A850-6C10B54FBBB5`
  - Tahoe sub: `0DC99DD8-3386-4D1E-8878-C43E97EB710A`
  - Sequoia sub: `78D1B993-DA5B-4CA6-90F0-865DA7F9091D`
  - Sonoma sub: `3CC63110-FF0E-4443-9A2D-63CD0795954E`

### transcode params (ground-truth from Apple's "Tahoe Day" .mov)

```
-an
-vf scale=3840:2160:force_original_aspect_ratio=decrease,pad=3840:2160:(ow-iw)/2:(oh-ih)/2
-c:v hevc_videotoolbox       # fallback: libx265
-tag:v hvc1
-profile:v main10
-pix_fmt p010le              # VT output; libx265 → yuv420p10le (same family, accepted)
-b:v 12M                     # Apple sample: 12.4 Mbps
-color_primaries bt709 -color_trc bt709 -colorspace bt709
-movflags +faststart
-f mov
```

container: `major_brand=qt`. Apple stock 299s clip — long-form, NOT seamless-loop. Skip loop encoding.

### AerialWall manifest (`~/Library/Application Support/AerialWall/manifest.json`)

```swift
struct AerialWallEntry: Codable {
    let uuid: String                 // uppercase, matches entries.json id + filenames
    var name: String                 // user display name (→ localizedNameKey)
    let originalFilename: String
    let importedAt: Date
    let durationSeconds: Double
    let resolution: String           // "3840x2160"
    let videoPath: String            // ~/Library/Application Support/AerialWall/library/<uuid>.mov
    let thumbPath: String            // ~/Library/Application Support/AerialWall/thumbs/<uuid>.png
    var isInjected: Bool             // last verified presence in entries.json
}
struct AerialWallManifest: Codable {
    var schemaVersion: Int = 1
    var entriesSchemaSeen: Int       // entries.json.version observed @ install (compat gate)
    var wallpapers: [AerialWallEntry] = []
}
```

### targets

```
AerialWall          → SwiftUI app
AerialWallAgent     → slim user-domain LaunchAgent (PersistenceWatcher, no UI, no XPC)
AerialWallKit       → shared framework (models, Constants, JSON codec)
```

⊥ AerialWallHelper target — no privileged operation needed.

### GUI reference

UI/UX detail (window structure, sidebar, toolbar, library, alerts, onboarding,
settings, menubar extra, keyboard shortcuts) lives in `GUI.md` at repo root.
GUI.md's §Tahoe reconciliation appendix overrides any of its sections that
conflict with this SPEC. T12, T13, and the UX surfaces of T15 cite GUI.md.

### SPM deps

```
FFmpegKit (arthenica/ffmpeg-kit)
swift-log (apple/swift-log)
```

⊥ SQLite.swift — no SQLite anywhere.

## §V

V1:  video out → HEVC Main10, 10-bit, `.mov` (qt brand), 3840×2160, SDR bt709
V2:  video out → `-tag:v hvc1` (≠ `hev1`) — QuickTime compat
V3:  video out → ⊥ audio tracks (`-an`)
V4:  pre-inject → `AVURLAsset(url).load(.isPlayable) == true` else reject
V5:  writes ∈ `~/Library/Application Support/com.apple.wallpaper/aerials/`, ⊥ `/Library/`, ⊥ `/System/Library/`
V6:  ⊥ root, ⊥ SMAppService, ⊥ XPC privileged helper — all ops as login user
V7:  asset UUID UPPERCASE, matches `entries.json:asset.id` ∧ `videos/<UUID>.mov` ∧ `thumbnails/<UUID>.png`
V8:  ⊥ modify `TVIdleScreenStrings.bundle` (Apple-signed; modifications wiped on manifest re-pull)
V9:  `localizedNameKey` = user-facing display name string verbatim (rendered literally on miss — V20 of v1 confirmed)
V10: `accessibilityLabel` set to same display name (VoiceOver), NOT the main UI label
V11: `previewImage` URL → keep https:// to existing Apple asset (safe default) OR set to local `file://`; local `thumbnails/<id>.png` auto-discovered regardless
V12: `url-4K-SDR-240FPS` URL → same; local `videos/<id>.mov` auto-discovered by UUID
V13: ∀ AerialWall asset → injected with all 12 required fields (§I asset entry block)
V14: entries.json write → atomic: write `<path>.tmp` + `rename(2)` to final, ⊥ partial-write
V15: entries.json write → preserve top-level keys + ordering (`version`, `initialAssetCount`, `localizationVersion`, `assets`, `categories`) to minimize diff vs Apple-canonical
V16: agent restart → `kill <pid>` SIGTERM. ⊥ `launchctl kickstart -k` (SIP exit 150, verified)
V17: agent PID lookup → `launchctl list` parse, column 1 of row where column 3 == `com.apple.wallpaper.agent`
V18: post-kill → wait ≤5s for new PID; verify via `launchctl list`
V19: persistence watch → FSEvents (`DispatchSource.makeFileSystemObjectSource`) on `entries.json` + `manifest.tar`, ⊥ polling
V20: drift detection → @ event, load entries.json, ∃ AerialWall entry ∈ AerialWall manifest ∉ entries.json → re-inject all + restart agent
V21: schema version probe @ launch → `entries.json.version != 1` → surface compat warning, ⊥ inject; track expected version in AerialWall manifest
V22: AerialWall storage = `~/Library/Application Support/AerialWall/` (user-level, ⊥ `/Users/Shared` — no privilege boundary to cross)
V23: encoder → `hevc_videotoolbox` primary, `libx265` fallback when VT unavailable
V24: ⊥ AVPlayerLayer-over-transparent-NSWindow fake wallpaper
V25: ⊥ `NSWorkspace.setDesktopImageURL` on raw `~/Library/Application Support/AerialWall/library/` path without prior entries.json injection
V26: ⊥ AppKit window-level tricks for lock screen drawing
V27: custom category injection → optional. If used: new UUID, append to `entries.json:categories[]`, track in AerialWall manifest. Default behavior: reuse stock Landscapes category UUID (`A33A55D9-...`)
V28: category mutation scope → AerialWall touches only categories it created (track in AerialWall manifest). ⊥ modify stock category entries
V29: uninstall → strip AerialWall entries from `entries.json` (by AerialWall manifest UUID list), delete `videos/<UUID>.mov` + `thumbnails/<UUID>.png`, delete `~/Library/Application Support/AerialWall/`, unload LaunchAgent, restart `WallpaperAgent`
V30: backup safety → before first inject, snapshot `entries.json` → `~/Library/Application Support/AerialWall/backups/entries.json.<ISO8601>.bak`; retain ≥3 most recent
V31: hardlinking ⊥ used for injected `.mov` — always a real copy of transcoded output (originals may be at different paths; users may delete; refcount surprises break expectations)
V32: UI colors → semantic only (`.primary`, `.secondary`, `.tertiary`, `Color(.windowBackgroundColor)`, `Color(.separatorColor)`, `Color(.textBackgroundColor)`, `.tint(Color.accentColor)`). ⊥ hardcoded hex anywhere
V33: UI components → native AppKit/SwiftUI only. ⊥ custom titlebar, ⊥ hidden traffic lights, ⊥ custom progress indicators, ⊥ custom toasts/badges/sheets. Use `NSAlert`, `NSOpenPanel`, `ProgressView`, `ContentUnavailableView`, `Table`, `Form.formStyle(.grouped)`
V34: only non-system UI tweak permitted = thumbnail corner radius 8pt. Everything else system-default
V35: ⊥ helper-install onboarding step (no helper exists on Tahoe — V6). Onboarding shows only when `Constants.entriesJSONPath` is absent, & lists "Open System Settings → Wallpaper" steps
V36: user-facing path text → `~/Library/Application Support/AerialWall/...` (V22). ⊥ "/Users/Shared/AerialWall/..." in any UI string
V37: subprocess pipes (`stdout` & `stderr`) → drain continuously via `FileHandle.readabilityHandler`. ⊥ accumulate to EOF without reading (kernel pipe buffer ~64KB → blocking write deadlock on chatty subprocesses like ffmpeg)
V38: subprocesses with tty-aware interactive input (ffmpeg, top, less, …) → must be invoked with their non-interactive flag (`-nostdin` for ffmpeg). Without it, the child calls `tcsetattr` on stdin and blocks in `ioctl` when stdin is a pipe / no controlling tty
V39: SPM-launched SwiftUI executable → MUST register `NSApplicationDelegateAdaptor` whose `applicationDidFinishLaunching` calls `NSApp.setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps: true)`. Without it, the app launches as a UIElement-style background process, sheet windows never become key, and TextField inside a sheet silently drops clicks/keypresses (B11)
V40: AerialWall assets → use `Constants.AerialWallCategory.{categoryID,subcategoryID}` (V27). On every inject, pass `ensureCategory:` to `InjectionEngine.inject` — the engine appends our top-level category to `entries.json:categories[]` if absent, idempotent. ⊥ inject under a stock category UUID
V41: `entries.json` asset URL fields (`previewImage`, `url-4K-SDR-240FPS`) → `https://` scheme, shape `https://sylvan.apple.com/aerialwall/<UUID>/...`. ⊥ `file://` — wallpaper runtime accepts file:// for initial selection but rejects it on unlock-rebind & falls back to gray. Local files auto-discovered by UUID convention at `videos/<UUID>.mov` / `thumbnails/<UUID>.png` regardless of URL value
V42: `entries.json` asset shape → match Apple stock pattern on numeric/bool fields: `preferredOrder` = small positive int, `includeInShuffle` = true, `showInTopLevel` = true. Conservative emulation reduces runtime contract surface
V43: AerialWall custom category & subcategory `representativeAssetID` MUST always point to a currently-existing asset in `entries.json:assets[]`. ⊥ dangling rep → `WallpaperAerialsExtension` validation fails wholesale & every aerial category vanishes from System Settings UI (not just ours). Maintained by: `InjectionEngine.inject(_:upsertCategory:)` refreshes rep+previewImage on every insert; `InjectionEngine.remove(_:from:maintaining:)` reassigns rep to a remaining asset, or strips the custom category if no assets remain. Stock Apple categories (§I) never modified (V28)
V44: transcoded `.mov` first-frame PTS MUST equal 0. VT/source delay can yield a 1-frame `start_time` offset (~33ms @ 30fps). `WallpaperAerialsExtension` seeks to t=0 for the unlock-fade still frame & finds no frame there → gray fallback (B14). Enforced by appending `setpts=PTS-STARTPTS` to the `-vf` filter chain + `-muxdelay 0 -muxpreload 0` muxer flags. Verified post-transcode via ffprobe `start_time == 0`
V45: reverted — 240fps frame-duplication didn't fix unlock-gray, made transcode ~5× slower (30+ min on real 4K content)
V46: transcoded `.mov` MUST include B-frames. Apple stock encodes have `has_b_frames=4`; VT defaults to 0. Pass `-bf 4 -refs 4` to ffmpeg — VT honors the option (with its own cap, observed 2) which yields a non-zero `has_b_frames` in ffprobe. Conjecture (untested): the unlock-fade still-frame extraction prefers an I-frame after a B-frame group; pure all-I/P timelines may miss the lookback window. Verified post-transcode via ffprobe `has_b_frames > 0`
V47: reverted (libx265 path) — also failed unlock-rebind. ffmpeg's `hevc_videotoolbox` wrapper failed because it doesn't expose VT's `kVTCompressionPropertyKey_BaseLayerFrameRate`. libx265 failed because no public x265 flag produces enough HEVC temporal sub-layers. Resolution: V48
V48: TranscodeEngine is **pure native** — `AVURLAsset` + `AVMutableVideoComposition` (scale/pad/color/orientation) + `AVAssetWriter` w/ VideoToolbox HEVC encoder driven by `kVTCompressionPropertyKey_BaseLayerFrameRate = srcFps/2`. Produces 2-layer hierarchical HEVC (TRAIL_R at `temporal_id 0` + TSA_N at `temporal_id 1`) — sufficient for WallpaperAerialsExtension's `video-sample-reader` to find frames at non-zero `temporal_id` and not skip the entire stream (B17). ⊥ ffmpeg in runtime pipeline (only used in tests for testsrc synthesis). Side-effect: WebM container inputs fail at the `loadTracks` step (AVAssetReader doesn't support WebM on Tahoe) — surfaced as `TranscodeError.inputFormatUnsupported` with actionable UI text. Test `transcodeProducesTemporalSubLayers` verifies output via ffprobe `trace_headers` (`TSA_N` + `temporal_id > 0`)

## §T

```
id |st|task                                                                |cites
T1 |x |Xcode proj: app + agent target + AerialWallKit framework            |§C
T2 |x |Constants.swift: paths, bundle IDs, stock category UUIDs            |§I
T3 |x |entries.json codec: parse v1, schema-version probe, atomic write    |V14,V15,V21
T4 |x |InjectionEngine: append asset, verify post-restart, remove          |V7,V13,V14,V20
T5 |x |TranscodeEngine: FFmpegKit + hevc_videotoolbox + libx265 fallback   |V1,V2,V3,V23
T6 |x |ThumbnailGenerator: AVAssetImageGenerator → PNG @ t=1s              |§I
T7 |x |AerialWallManifest: Codable load/save manifest.json                 |V22
T8 |x |AgentRestartHelper: PID lookup + SIGTERM + post-kill wait           |V16,V17,V18
T9 |x |PersistenceWatcher: FSEvents on entries.json + manifest.tar         |V19,V20
T10|x |LaunchAgent: install/uninstall, plist @ ~/Library/LaunchAgents/     |§I
T11|x |Backup mgr: snapshot entries.json before inject, retain 3           |V30
T12|x |SwiftUI UI: library grid, import sheet, apply, status indicator     |§I,GUI
T13|. |WallpaperSetter: NSWorkspace + Index.plist fallback for apply       |V25
T14|. |Error handling: missing entries.json, schema mismatch, restart fail, Apple manifest re-pull drift, multi-display |V20,V21
T15|. |Uninstall flow: strip entries, delete files, restore backup if asked|V29
T16|. |Notarization + DMG packaging                                        |§C
T17|. |Unit tests: Transcode validation, Injection (vs entries.json copy), Watcher, Manifest |V1,V2,V14
T18|. |Integration test on Tahoe 26.4+: full flow, manifest re-pull survival, apply|V20,V29
T19|. |Manual matrix: M1/M2/M3 + Intel, 26.x patch versions, single/multi display, SIP on/off |§C
```

## §B

```
id |date      |cause                                                                                              |fix
B1 |2026-05-18|v1 §1.3 assumed `Aerial.sqlite` + `idleassetsd` + `/Library/...` model; macOS 26 replaced with `entries.json` (JSON v1) + `WallpaperAgent` + `~/Library/...` (user-level). Validated by probe — no SQLite, no idleassetsd, no Aerial-Extension on Tahoe. |V5,V6 (rewrite)
B2 |2026-05-18|v1 §3 spec'd thumbnails as JPG. Apple Tahoe uses PNG (60+ stock files in `thumbnails/*.png`).      |V7,T6
B3 |2026-05-18|v1 §4.2 spec'd `launchctl kickstart -k system/<label>` for daemon restart. Tahoe SIP returns exit 150 even in `gui/<uid>` for Apple-signed agents. SIGTERM via `kill` works (launchd respawns). |V16
B4 |2026-05-18|v1 implicitly assumed `accessibilityLabel` = display name. Live probe: `localizedNameKey` renders LITERALLY when bundle key absent; that's the actual display string. `accessibilityLabel` is VoiceOver-only. |V9,V10
B5 |2026-05-18|v1 V11 said "uuid lowercased". Apple uses UPPERCASE UUIDs in `entries.json:id` + filenames.       |V7
B6 |2026-05-18|v1 §13.3 prescribed a SQLite-schema-probe CLI (T3). Moot — no SQLite. Repurposed T3 as JSON-schema probe + version-gate. |T3
B7 |2026-05-18|External GUI/UX spec arrived describing privileged-helper onboarding, /Users/Shared paths, "Base Apple asset" slot-hook picker — all macOS-15-era assumptions that don't apply on Tahoe (V6, V22). Saved to GUI.md with §Tahoe reconciliation appendix overriding 6 items (R1–R6). |V32,V33,V34,V35,V36
B8 |2026-05-18|TranscodeEngine import hung at 5% for 7+ minutes on a 4K AV1 WebM. ffmpeg process ran at 0.0% CPU. Cause: stderr `Pipe()` captured but never read while the process ran; kernel pipe buffer filled (~64KB) and ffmpeg blocked on `write(2)` forever. terminationHandler never fired. |V37
B9 |2026-05-18|After fixing B8, ffmpeg still hung at 2% for 7+ minutes at 0.0% CPU. `sample` showed stack `term_init → tcsetattr → ioctl` — ffmpeg trying to put its stdin into raw mode for interactive 'q' handling, blocking forever because the subprocess has no controlling terminal. Fix: `-nostdin` arg.|V38
B10|2026-05-18|First successful end-to-end import (Dolby AV1 → HEVC) plays as wallpaper but transition on screen lock/unlock is choppy & not a smooth fade to a still frame like Apple's stock assets. Output is also grainy at 12M default bitrate from an already-lossy source. Partial mitigation: default bitrate bumped 12M → 20M. Root cause of choppy unlock unknown — Apple may rely on specific QuickTime atoms / shotID lookups / frame-rate match (240fps) that our output lacks. Needs deeper investigation; not closed. |—
B11|2026-05-18|ImportSheet TextFields dropped all input — clicks didn't take focus, typing didn't register. Cause: SPM `.build/.../AerialWall` executable has no `.app` bundle / Info.plist, so macOS launches it with default UIElement-style activation policy and sheet windows never become key. Fix: `NSApplicationDelegateAdaptor` with `setActivationPolicy(.regular)` + `activate(ignoringOtherApps: true)`. Belt-and-suspenders: `@FocusState` auto-focuses the Name field on appear. |V39
B12|2026-05-18|Custom wallpaper plays on initial selection + lock, but on unlock the wallpaper goes gray. Diff against Apple stock entry: `previewImage` + `url-4K-SDR-240FPS` were `file://` (ours) vs `https://sylvan.apple.com/...` (Apple). Hypothesis: initial-selection path resolves local file by UUID convention regardless of URL; unlock rebind re-reads URL and rejects file:// scheme, runtime falls back to gray. Also `preferredOrder=-100` vs Apple's small-positive and `includeInShuffle=false` vs Apple's `true` may contribute. Fix: V41 synthesize Apple-shaped `https://sylvan.apple.com/aerialwall/<UUID>/...` URLs; V42 match Apple's numeric/bool conventions. |V41,V42
B13|2026-05-18|After Remove + Re-import via UI, System Settings → Wallpaper showed only Dynamic Wallpapers / Pictures / Colors — every aerial category (Landscapes, Cities, Underwater, Space, Mac, AerialWall) vanished. Root cause: Remove flow stripped the asset but left the AerialWall category in place with its `representativeAssetID` still pointing at the deleted asset's UUID. Re-import created a new asset with a new UUID and the existing `ensureCategory` was idempotent (no-op when category exists) → rep dangled. `WallpaperAerialsExtension` validates the manifest, finds the rep target missing, and refuses to surface ANY aerial categories. Probable B12 contributor too — partial load may succeed for initial pick but fail for unlock-rebind. Fix: V43 — `inject` now upserts (refreshes rep+preview to every newly-injected asset), `remove` reassigns rep on rep-owner deletion or strips the custom category when its last asset is gone. Existing dangling state in entries.json patched by hand via a Python script. |V43
B14|2026-05-18|Custom wallpaper plays during lock screen but goes gray on unlock. Test A (stock Apple wallpaper) works fine — system healthy. Test B (Apple's Tahoe Day bytes hardlinked under our AerialWall category) works fine — custom category innocent. ffprobe diff against Apple stock: our transcoded `.mov` reports `start_time=0.033008` (= one frame @ 30fps), Apple reports `start_time=0.000000`. VT or source-side encoder delay leaks through. `WallpaperAerialsExtension` seeks to t=0 for its unlock-fade still frame, finds nothing at that timestamp on our file, falls back to gray. This was also the actual root cause of B12 — the file:// / preferredOrder / shuffle / category guesses earlier were red herrings. Fix: V44 — `setpts=PTS-STARTPTS` filter + `-muxdelay 0 -muxpreload 0` muxer flags force first-frame PTS to 0. Validated by ffprobe in unit test.|V44
B15|2026-05-18|V44 fix landed (`start_time=0.000000` confirmed via ffprobe) but unlock-gray still happened. Remaining diff vs Apple: `r_frame_rate` 30/1 vs 240/1, `has_b_frames` 0 vs 4, HEVC level 5.0 vs 5.2.1. First attempt V45 forced `-r 240` to match Apple's `4KSDR240FPS` directory convention — encode jumped from 1× to ~5× (30+ min on real 4K), DID NOT fix unlock-gray. V45 reverted. Pivoted to V46 — add B-frames via `-bf 4 -refs 4`. VT honors the flag (capped at `has_b_frames=2`); transcode time back to baseline.|V46
B16|2026-05-18|V46 (B-frames via VT) didn't fix unlock-gray. Stale snapshot cache from previous broken-state encodes ruled out as cause: cache purge + agent restart didn't help, fresh imports get fresh cache entries anyway (filenames are content-hashed). |—
B17|2026-05-19|Definitive Test C: re-encoded Apple's Tahoe Day through our ffmpeg pipeline (hevc_videotoolbox, -bf 4, setpts=0), still gray on unlock. Test D pivot: native VT via Swift `AVAssetWriter` with `BaseLayerFrameRate = srcFps/2` → produces TSA pictures at `temporal_id 1`. Live test passed end-to-end (lock + unlock + smooth still). Log analysis pinpointed `[wallpaper:video-sample-reader] skipping frame with TSAINFO level: <private> as our level is 3` — the wallpaper extension filters frames by HEVC temporal_id. Single-layer encodes get every frame skipped → `sharedWallpaperRemovalTriggerFired` → gray. neither ffmpeg's `hevc_videotoolbox` wrapper (doesn't expose `BaseLayerFrameRate`) nor libx265 (no flag produces temporal sub-layers) can solve this. **Only direct VT via Swift `AVAssetWriter` does.** Fix: V48 — pure-native TranscodeEngine.|V48
```
