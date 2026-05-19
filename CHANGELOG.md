# Changelog

All notable changes to AerialWall are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

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
