# Integration Test Checklist

End-to-end verification on real hardware. Run this before tagging a release.

Build the bundle first:

```bash
./scripts/regen-icon.sh
./scripts/build-app.sh
open build/AerialWall.app
```

---

## T18.1: First-run smoke

1. AerialWall.app launches without crashing
2. The Library view appears with Apple's stock aerials listed (Tahoe, Sequoia, Sonoma)
3. No errors in the AerialWall alert panel
4. Dock icon shows the AerialWall logo (light mode + dark mode both adapt)

## T18.2: Import flow

1. Drop or click-import a `.mp4` ≤ 4K HEVC/H.264 source
2. Import sheet shows name + description fields, both focusable and editable
3. After OK, transcode progress bar advances 0 → 100 %
4. On completion: the new wallpaper appears in the library list, status `● Ready`
5. Open **System Settings → Wallpaper**: the **AerialWall** category exists at the bottom of the list, containing the new entry with its thumbnail
6. Verify in Console.app (subsystem `com.aerialwall.kit`):
   - `transcode start ... done`
   - `injection inject asset id=...`
   - `backup snapshot entries.json.<timestamp>.bak`

## T18.3: Apply flow

1. Double-click the new wallpaper in AerialWall's library (or right-click → Apply as Wallpaper)
2. Status indicator changes to "Applied" (green checkmark)
3. Desktop wallpaper changes within a second
4. System Settings → Wallpaper reflects the same selection
5. **Multi-display:** with an external monitor connected, both screens show the same new wallpaper (V53)

## T18.4: Lock + unlock cycle (the critical B17 regression check)

1. Apply the new wallpaper
2. Press `Ctrl+Cmd+Q` (lock screen)
3. Wait until lock-screen wallpaper plays: should be smooth, no stutter
4. Unlock with password / Touch ID
5. **Desktop background MUST still be the AerialWall video** (not gray)
6. Repeat steps 2–5 three times to confirm it's deterministic, not lucky

## T18.5: Apple manifest re-pull survival (V19, V20)

1. Apply an AerialWall wallpaper, confirm it's working
2. Simulate Apple's tar re-pull:
   ```bash
   touch "~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json"
   ```
3. The PersistenceWatcher in AerialWall should fire: check Console.app:
   - `watcher event entries.json`
   - `injection reconciliation: <N> assets re-injected`
4. Verify AerialWall entries are still present in System Settings

## T18.6: Remove flow

1. Right-click an AerialWall wallpaper → Remove
2. Confirm dialog → Remove
3. Entry disappears from AerialWall library + System Settings
4. **Critical:** other aerial categories (Apple's Landscapes, Cities, etc.) still appear in System Settings (V43: no dangling category rep)

## T18.7: Uninstall flow (T15)

**WARNING**: this is destructive: only run on a test account.

1. Settings → Danger Zone → Uninstall AerialWall…
2. Choose **Preserve backups**
3. Confirm → wait for completion
4. Verify:
   - `~/Library/Application Support/AerialWall/library/`, `/originals/`, `/thumbs/`, `/manifest.json` all gone
   - `~/Library/Application Support/AerialWall/backups/` **still exists**
   - All AerialWall entries gone from System Settings → Wallpaper
   - Apple stock aerials all still present (V28)
5. Repeat with **Full**: same, plus `backups/` gone
