# AerialWall: Native Video Wallpapers for macOS Tahoe

AerialWall is a lightweight, non-sandboxed utility that allows you to use any video as a native macOS wallpaper. It injects your videos directly into the macOS 26 (Tahoe) wallpaper manifest, making them appear alongside Apple's official Aerial shots.

## Features
- **Native Integration:** Injected wallpapers appear in System Settings → Wallpaper.
- **Tahoe Optimized:** Specifically built for the new JSON-based manifest architecture in macOS 26.
- **High Performance:** Uses native VideoToolbox HEVC encoding with 2-layer temporal hierarchy for smooth lock-screen transitions.
- **Open Source:** MIT licensed, no telemetry, no background "helper" apps needed for rendering (uses system agents).

## How it Works
AerialWall transcodes your videos into a specific HEVC format that the macOS `WallpaperAerialsExtension` accepts. It then snapshots your `entries.json`, injects your asset metadata, and restarts the `WallpaperAgent` to apply the changes.

## Requirements
- **macOS 26 (Tahoe)** or later.
- **Non-sandboxed:** Required to modify `~/Library/Application Support/com.apple.wallpaper`.

## Installation
*Coming soon via Homebrew.*

For now, build from source:
```bash
swift build -c release
```

## Contributing
See [RESEARCH.md](RESEARCH.md) for technical details on the Tahoe wallpaper architecture.

## License
MIT
