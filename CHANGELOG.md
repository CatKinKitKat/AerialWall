# Changelog

All notable changes to AerialWall are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [0.1.0] — 2026-05-19

First stable release. Same code as `0.1.0-beta.5`, promoted after the
beta testing window. See the beta entries below for the full list of
features delivered between `0.1.0-beta.1` and `0.1.0-beta.5`.

Distribution: `brew tap CatKinKitKat/aerialwall && brew install --cask aerialwall`

## [0.1.0-beta.5] — 2026-05-19

### Fixed
- Sidebar navigation was sticky after visiting **Logs** — clicking
  "All Wallpapers" did nothing because the dynamic `.badge(count)` modifier
  was interfering with `List(selection:)` tag matching. Switched to
  `NavigationLink(value:)` rows and added `.id(selection)` on the detail
  view so SwiftUI recreates it cleanly when the sidebar selection changes.

## [0.1.0-beta.4] — 2026-05-19

### Fixed
- **Logs view no longer freezes the app.** `OSLogStore.getEntries` is
  synchronous and slow on large windows — moved enumeration to a
  `Task.detached(.userInitiated)` so the main actor stays responsive.
  Result also capped at 500 entries with an early `break` so the table
  never gets a million-row payload. Default range shortened to 15 min;
  the 24-hour option was removed.
- "Reading logs…" progress indicator shown while the enumeration is in
  flight.

## [0.1.0-beta.3] — 2026-05-19

### Added
- **Real Logs viewer** reading from `OSLogStore` for subsystem
  `com.aerialwall.kit`. Time-range picker (5min..24h), level filter pills,
  searchable, color-coded by severity.
- **Developer menu** in the macOS top menu bar with a "Show Logs in Sidebar"
  toggle. Logs sidebar entry is hidden by default and only appears when
  the toggle is on (`@AppStorage("aerialwall.developerMode")`).

### Distribution
- CI + Release runners moved to **macos-26** with Xcode 26 selected via
  `maxim-lobanov/setup-xcode`. The release build now invokes the real
  `actool` against `AerialWall.icon`, producing a multi-appearance
  `Assets.car` (light + dark + tinted), with the pre-rendered files as
  a fallback for older toolchains.

## [0.1.0-beta.2] — 2026-05-19

Second beta. Polish pass + distribution pipeline.

### Added
- **Apply from inside the app** — double-click or `Apply as Wallpaper` from the
  context menu writes to `Index.plist` and signals `WallpaperAgent` (T13, V25)
- **Multi-display support** — apply clears per-display and per-Space override
  dicts so all monitors and Mission Control spaces show the same wallpaper (V53)
- **Library view modes** — toggle between **grid** (default) and **list** in
  the toolbar; persisted via `@AppStorage`
- **About modal** — triggered from the AerialWall menu, with version + GitHub
  links + Ko-fi / Buy Me A Coffee tip buttons
- **Help modal** — triggered from Help menu (⌘?), with getting-started flow,
  troubleshooting tips, and external links
- **Full uninstall flow** — Settings → Danger Zone removes all AerialWall
  entries, files, LaunchAgent, and storage. Apple stock aerials untouched (T15)
- **Structured logging** — `os.Logger` under subsystem `com.aerialwall.kit`;
  inspect live via Console.app (V51)
- **`LocalizedError` everywhere** — all 10 engine errors now surface
  actionable user-facing strings (V52)
- **App icon** — designed in Apple Icon Composer, supports light / dark /
  tinted via Assets.car (V54)

### Distribution
- **`.app` bundle** via `scripts/build-app.sh` — Info.plist, icns from actool
- **Homebrew Cask** auto-published to `CatKinKitKat/homebrew-aerialwall`
  on every release. Install with:
  ```
  brew tap CatKinKitKat/aerialwall
  brew install --cask aerialwall
  ```
  The cask `postflight` strips `com.apple.quarantine` so users never see
  Gatekeeper's "unidentified developer" dialog.
- **No notarization** — paying Apple US$99/yr to skip one dialog is not
  on the roadmap

### Testing
- 80 unit tests across 14 suites (T17), including WallpaperSetter
  (multi-display verification), UninstallEngine, and LocalizedError
- Integration runbook at [`docs/INTEGRATION-TEST.md`](docs/INTEGRATION-TEST.md) (T18)
- Manual test matrix at [`docs/MANUAL-MATRIX.md`](docs/MANUAL-MATRIX.md) (T19)

### Fixed
- CI now compiles cleanly on `macos-15` + Xcode 16 (reverted hand-edited
  `AVVideoComposition.Configuration` migration — will re-land when GitHub
  ships macOS 26 hosted runners)
- `Index.plist` write no longer includes `NSNull` (binary plist format 200
  rejects CFNull, was breaking Apply on real hardware)
- App icon adapts to system light/dark in the .app bundle path (AppDelegate
  no longer force-overrides `applicationIconImage` when CFBundleIconName is
  present in Info.plist)

## [0.1.0-beta.1] — 2026-05-19

First public beta. Core pipeline end-to-end verified on macOS 26.4 Tahoe.

### What works
- Import any `.mp4` / `.mov` / `.m4v` video via drag-and-drop or Import button
- Edit name + description in the import modal before transcoding begins
- Transcode via native VideoToolbox — HEVC Main10, 4K, 2-layer hierarchical
  encoding (`BaseLayerFrameRate`) required by `WallpaperAerialsExtension`
- Appears as **AerialWall** category in System Settings → Wallpaper
- Plays on both desktop and lock screen; survives lock → unlock cycle
- Rename and remove wallpapers from the in-app library
- Atomic `entries.json` mutation with automatic backup (3 snapshots retained)
- Persistence watcher (FSEvents) re-injects entries if Apple's manifest
  is re-pulled from CDN

### Known limitations
- WebM container not supported (AVAssetReader limitation on Tahoe); convert
  to `.mp4` with HandBrake or ffmpeg first
- No `.app` bundle / DMG yet — run via `swift run AerialWall` (tracked: T16)
- Choppy lock-screen → still-frame transition for some source content (B10,
  open investigation)
- First-run onboarding assumes at least one Apple aerial video already
  downloaded in System Settings → Wallpaper

### Architecture notes (for contributors)
See `SPEC.md` for invariants, `GUI.md` for UI/UX spec, and `§B` in SPEC for
the full bug backpropagation log — 20 bugs diagnosed and resolved during
initial development, including the complete reverse-engineering of Tahoe's
`WallpaperAerialsExtension` temporal sub-layer requirement.
