# Research: AerialWall & macOS Tahoe Wallpaper Architecture

This document tracks the reverse engineering discoveries made during the development of AerialWall for macOS 26 (Tahoe).

## 1. The Great Architectural Shift (macOS 15 → 26)

Previous macOS versions (Sonoma/Sequoia) managed Aerial wallpapers via a system-level SQLite database (`Aerial.sqlite`) and the `idleassetsd` daemon. In macOS 26 (Tahoe), this has been completely replaced.

### Key Changes:
- **Registry:** Switched from SQLite to a flat JSON manifest: `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json`.
- **Daemon:** `idleassetsd` is gone; `com.apple.wallpaper.agent` (`WallpaperAgent`) now handles wallpaper lifecycle and rendering.
- **Privilege:** Wallpaper assets and manifests are now owned by the login user in their home directory, rather than being system-wide. This allows non-sandboxed user apps to manage wallpapers without root/Sudo.
- **Discovery:** The system auto-discovers local files in `videos/<UUID>.mov` and `thumbnails/<UUID>.png` based on the IDs present in `entries.json`.

## 2. The "Unlock to Gray" Bug (B12, B14, B17)

One of the most significant challenges was a bug where custom wallpapers would play fine on the lock screen but turn gray immediately upon unlocking the Mac.

### Findings:
1. **PTS Alignment (B14):** The wallpaper extension seeks to exactly `t=0` for the unlock-fade still frame. If the video has an encoder delay (even 1 frame), it reports a non-zero `start_time`. Seeking to 0 on such a file yields nothing, causing the gray fallback.
   - **Fix:** Force first-frame PTS to 0 using `setpts=PTS-STARTPTS`.
2. **VideoToolbox Rejection (B17):** Even with perfect PTS alignment, standard HEVC output from Apple's `VideoToolbox` (VT) was often rejected.
3. **Temporal Sub-layers (V48):** Deeper analysis of Apple's stock clips revealed they use **2-layer hierarchical HEVC**. The `WallpaperAerialsExtension` filters frames by `temporal_id`. If a video lacks sub-layers (specifically TSA NAL units at `temporal_id 1`), the reader skips all frames during the unlock transition.
   - **Fix:** Use `kVTCompressionPropertyKey_BaseLayerFrameRate` set to half the source frame rate. This forces the VT encoder to emit temporal sub-layers.

## 3. Manifest Integrity & "The Vanishing UI" (B13)

The `entries.json` file is strictly validated by `WallpaperAerialsExtension`.

- **Dangling References:** If a category's `representativeAssetID` points to a UUID that doesn't exist in the `assets` list, the extension fails validation.
- **Consequence:** **Every** aerial category (including Apple's stock Landscapes, Cities, etc.) vanishes from the System Settings UI.
- **Fix:** Always ensure `representativeAssetID` is updated to a valid, existing asset during injection or removal.

## 4. Operational Hazards

- **Pipe Deadlocks (B8):** Subprocesses like `ffmpeg` or `AVAssetWriter` pipelines can hang if their `stderr`/`stdout` pipes aren't drained continuously. The kernel pipe buffer is small (~64KB); once full, the child process blocks on `write(2)`.
- **TTY Hangs (B9):** `ffmpeg` tries to put its stdin into raw mode for interactive commands (like pressing 'q' to quit). If launched as a background process without `-nostdin`, it hangs in `tcsetattr`.
- **App Activation (B11):** Swift executables built via SPM without a `.app` bundle launch as `UIElement` processes by default. This causes sheet windows to never become "key," preventing text input. Explicitly setting the activation policy to `.regular` is required.

## 5. Summary of Transcode Requirements for Tahoe

To be accepted by the macOS 26 wallpaper system, a video must:
1. Be **HEVC Main 10** (10-bit).
2. Use the **hvc1** fourcc tag.
3. Have **no audio** tracks.
4. Have **start_time exactly 0.000000**.
5. Contain **temporal sub-layers** (TSA units at `temporal_id 1`).
6. Be placed in `~/Library/Application Support/com.apple.wallpaper/aerials/videos/<UUID>.mov` with a matching PNG in `thumbnails/`.
