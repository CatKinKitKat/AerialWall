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

## §T

```
id |st|task                                                                |cites
T1 |x |Xcode proj: app + agent target + AerialWallKit framework            |§C
T2 |x |Constants.swift: paths, bundle IDs, stock category UUIDs            |§I
T3 |. |entries.json codec: parse v1, schema-version probe, atomic write    |V14,V15,V21
T4 |. |InjectionEngine: append asset, verify post-restart, remove          |V7,V13,V14,V20
T5 |. |TranscodeEngine: FFmpegKit + hevc_videotoolbox + libx265 fallback   |V1,V2,V3,V23
T6 |. |ThumbnailGenerator: AVAssetImageGenerator → PNG @ t=1s              |§I
T7 |. |AerialWallManifest: Codable load/save manifest.json                 |V22
T8 |. |AgentRestartHelper: PID lookup + SIGTERM + post-kill wait           |V16,V17,V18
T9 |. |PersistenceWatcher: FSEvents on entries.json + manifest.tar         |V19,V20
T10|. |LaunchAgent: install/uninstall, plist @ ~/Library/LaunchAgents/     |§I
T11|. |Backup mgr: snapshot entries.json before inject, retain 3           |V30
T12|. |SwiftUI UI: library grid, import sheet, apply, status indicator     |§I
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
```
