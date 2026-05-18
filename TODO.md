# AerialWall TODO

## Core Functionality
- [ ] **AerialWallAgent (T9):** Implement the background binary. Integrate `PersistenceWatcher` to monitor `entries.json` and auto-reconcile on Apple manifest re-pulls.
- [ ] **WallpaperSetter (T13):** Implement the "Apply" logic. Use `NSWorkspace` and `Index.plist` fallback to programmatically set the active wallpaper per-display.
- [ ] **Error Handling (T14):** Robust handling for schema version mismatches, locked manifests, and multi-display edge cases.
- [ ] **Uninstall Flow (T15):** Complete cleanup logic (strip entries, delete transcodes, unload LaunchAgent, restore system state).

## Project Polish
- [ ] **Issue Templates:** Add `.github/ISSUE_TEMPLATE/` (bug, feature).
- [ ] **Distribution:** Create Homebrew Cask or DMG packaging script.
- [ ] **Testing:** Expand integration tests (T17/T18) for full-flow verification.

## Done (v0.1.0)
- [x] Native VT-only transcoding with temporal sub-layers (V48).
- [x] JSON injection engine for macOS 26 (Tahoe).
- [x] Swift UI Library and Import workflows.
- [x] Research documentation on Tahoe architecture.
- [x] GitHub Actions build/test CI.
