# AerialWall: GUI/UX Specification (Native-First)

> Authoritative for UI work (T12, T13, T15 UX surfaces). Pairs with `SPEC.md`.
> The §Tahoe reconciliation appendix at the bottom of this file overrides items
> that conflict with the Tahoe-only architecture in `SPEC.md` v2.

## Design Philosophy

Build AerialWall as a **first-class macOS citizen**. Use native AppKit/SwiftUI controls, system colors, and standard layouts throughout. The goal is an app that:

1. Looks correct on macOS today and **automatically looks correct** after future OS redesigns: no manual tweaks needed.
2. Borrows structural simplicity from **GNOME HIG** (single primary window, progressive disclosure, clear primary action, no modal clutter).
3. Has zero custom chrome except minor polish tweaks (thumbnail radius, row sizing).

**References to feel like**: Photos, Pastel, Sequel Pro, GNOME's Loupe or Solanum: utilitarian and considered, not "designed".

**DO NOT**:
- Custom title bar or hidden traffic lights
- Hardcoded hex colors anywhere: use semantic `NSColor` / SwiftUI `.primary`, `.secondary`, `Color(.windowBackgroundColor)` etc.
- Custom animations beyond what SwiftUI/AppKit provides by default
- Custom progress indicators, toasts, or status badges: use system equivalents
- Reinvent NSAlert, NSOpenPanel, NSProgressIndicator

***

## Window Structure

### Main window

```
Standard NSWindow:
  - Normal title bar, traffic lights, app name in title
  - Style: .titled, .closable, .miniaturizable, .resizable
  - Min size: 760 × 520pt
  - Default size: 960 × 620pt
  - No custom titlebar, no hidden title bar
```

### Layout: NavigationSplitView

```
┌──────────────────────────────────────────────────────────┐
│  ● ○ ●   AerialWall                       [toolbar]      │  ← standard NSToolbar
├─────────────────┬────────────────────────────────────────┤
│                 │                                        │
│  SIDEBAR        │  CONTENT                               │
│  (sidebar       │  (main view — swaps based on           │
│   list style)   │   sidebar selection)                   │
│                 │                                        │
└─────────────────┴────────────────────────────────────────┘

Implement with SwiftUI NavigationSplitView:
  - sidebar: fixed-width, system sidebar appearance
  - detail: content area
```

***

## Sidebar

Use SwiftUI `List` with `.listStyle(.sidebar)`. Standard SF Symbol icons with `.font(.body)`.

```swift
// Sections and items:

Section("Library") {
    Label("All Wallpapers", systemImage: "photo.on.rectangle.angled")
    Label("Recently Added",  systemImage: "clock")
}

Section("System") {
    Label("Settings", systemImage: "gearshape")
    Label("Logs",     systemImage: "terminal")
}
```

- Selection drives the content area.
- Badge on "All Wallpapers" shows count using `.badge(count)` modifier.
- No custom colors, no custom fonts: pure system sidebar rendering.

***

## NSToolbar

Declare an `NSToolbarDelegate` or use SwiftUI `.toolbar {}`. Items:

```
Left side:
  [Scope bar — NSSegmentedControl]
    Segments: "All" | "Applied" | "Errors"
    Tracks selection, filters the content view

Center (flexible space):
  NSSearchField — placeholder "Search wallpapers"
  keyboardShortcut: Cmd+F

Right side:
  [Import…]   NSToolbarItem, standard bordered button
              action: opens NSOpenPanel
              keyboardShortcut: Cmd+O
```

Place flexible spaces around the search field so it stays centered on wide windows.
Toolbar items use `.toolbarItemIdentifier` and standard toolbar item sizing.
No custom drawn items.

***

## Library View (content area: "All Wallpapers")

### Option A: Grid (if ≤ ~50 wallpapers expected)

```swift
ScrollView {
    LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 180, maximum: 240))],
        spacing: 12
    ) {
        ForEach(wallpapers) { wp in
            WallpaperThumbnailCell(wallpaper: wp)
        }
        ImportDropCell()   // always last
    }
    .padding(16)
}
```

#### WallpaperThumbnailCell

```
┌──────────────────┐
│                  │  ← NSImageView, aspect 16:9
│    thumbnail     │    corner radius: 8pt (only non-system tweak)
│                  │    clips to bounds, no border
├──────────────────┤
│ Name             │  ← .font(.headline), .lineLimit(1), truncatingTail
│ 2:34 · 4K        │  ← .font(.caption), .foregroundStyle(.secondary)
└──────────────────┘

Interaction:
  - Single click:   selects cell (standard selection highlight)
  - Double click:   triggers "Apply as Wallpaper"
  - Right click:    system context menu (see §Context Menus)

Selection style:
  Use List/selection binding or NSCollectionView's built-in selection.
  Applied wallpaper: show SF Symbol "checkmark.circle.fill" overlaid
  top-right corner of thumbnail, using .tint(.green) — system green,
  not hardcoded hex.
```

### Option B: Table view (preferred for GNOME + macOS-native feel)

```swift
Table(wallpapers, selection: $selectedID, sortOrder: $sortOrder) {
    TableColumn("Name",       value: \.name)
    TableColumn("Duration",   value: \.durationString)  { Text($0.durationString).monospacedDigit() }
    TableColumn("Resolution", value: \.resolution)
    TableColumn("Status") { wp in
        StatusBadge(status: wp.status)  // simple Text with system color, see below
    }
    TableColumn("Added",      value: \.importedAt)      { Text($0.importedAt, style: .relative) }
}
.tableStyle(.inset(alternatesRowBackgrounds: true))
```

Table gives you free: column resizing, sort by column header, keyboard navigation, accessibility, and row selection.

**StatusBadge**: just a `Text` with `.foregroundStyle(color)`: no custom capsule, no background:
```swift
// Applied:  "● Applied"   .foregroundStyle(.green)
// Pending:  "Not applied" .foregroundStyle(.secondary)
// Error:    "⚠ Error"     .foregroundStyle(.red)
// Encoding: "Encoding…"   .foregroundStyle(.secondary)  + progress indicator
```

**Primary action**: double-click row or press Return when row selected → Apply.

***

## Import Drop Zone

```swift
// Append as a special last row in table (or last cell in grid):

// In table: a clearly labeled empty-state placeholder below the table
// In grid: a dashed-border cell

ImportDropCell:
  Dashed border: RoundedRectangle using .stroke(style: StrokeStyle(dash: [5]))
                 color: Color(.separatorColor)  ← system color, adapts automatically
  Content:
    Image(systemName: "arrow.down.circle")
      .font(.largeTitle)
      .foregroundStyle(.secondary)
    Text("Drop video here")
      .font(.headline)
      .foregroundStyle(.secondary)
    Text("or use Import… (⌘O)")
      .font(.caption)
      .foregroundStyle(.tertiary)

Drag-over state:
  .border color → Color.accentColor  ← system accent (blue by default, user-overridable)
  background → Color.accentColor.opacity(0.05)
  No custom animations — just the color change.
```

***

## Empty State (no wallpapers imported yet)

Replace content area with centered ContentUnavailableView (macOS 14+):

```swift
ContentUnavailableView(
    "No Wallpapers Yet",
    systemImage: "photo.on.rectangle.angled",
    description: Text("Import a video to use it as a native aerial wallpaper.")
) {
    Button("Import Video…") { openImportPanel() }
}
```

This is a fully native component: correct spacing, correct typography, correct icon sizing, localization-ready.

***

## Transcode Progress (in-context, no modal)

While encoding, the row/cell shows progress inline:

**In table view**:
```swift
TableColumn("Status") { wp in
    if wp.isTranscoding {
        HStack(spacing: 6) {
            ProgressView(value: wp.transcodeProgress)
                .frame(width: 80)
                .controlSize(.small)
            Text("\(Int(wp.transcodeProgress * 100))%")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } else {
        StatusBadge(status: wp.status)
    }
}
```

**In grid view**:
```swift
// Overlay on thumbnail area only:
ZStack(alignment: .bottom) {
    thumbnailImage
    if wallpaper.isTranscoding {
        VStack(spacing: 4) {
            ProgressView(value: wallpaper.transcodeProgress)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .padding(.horizontal, 8)
            Text("Encoding \(Int(wallpaper.transcodeProgress * 100))%")
                .font(.caption2)
                .foregroundStyle(.white)
        }
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

No custom progress bar styling. `.progressViewStyle(.linear)` with `.controlSize(.small)` is exactly right.

***

## Apply Wallpaper

Keep the happy path dead simple:

1. User double-clicks row / cell, OR selects and presses Return.
2. If privileged helper not installed yet → `NSAlert` (§Alerts).
3. Otherwise, XPC call fires. Show `.progressViewStyle(.circular)` in the status column during the ~2s daemon restart.
4. On success: status updates to "● Applied", no fanfare.
5. On failure: status updates to "⚠ Error", user can hover for tooltip with error detail, or click "View Logs" from context menu.

No full-screen overlays. No custom sheets. One action, one outcome.

***

## Context Menus

Right-click on any wallpaper cell/row:

```swift
.contextMenu {
    Button("Apply as Wallpaper")  { apply(wallpaper) }
    Divider()
    Button("Rename…")             { beginRename(wallpaper) }
    Button("Show in Finder")      { reveal(wallpaper) }
    Button("Copy UUID")           { copyUUID(wallpaper) }
    Divider()
    Button("Remove", role: .destructive) { confirmRemove(wallpaper) }
}
```

Rename: inline edit (double-click the name label) or via context menu → standard text field focus.

***

## Alerts (use NSAlert / SwiftUI .alert for all dialogs)

**Remove confirmation**:
```swift
.alert("Remove \"\(wallpaper.name)\"?",
       isPresented: $showRemoveAlert) {
    Button("Remove", role: .destructive) { remove(wallpaper) }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("The video file will remain in /Users/Shared/AerialWall/Library. The wallpaper will be removed from the macOS wallpaper system.")
}
```

**Privileged helper install** (first launch only):
```swift
.alert("AerialWall needs permission",
       isPresented: $needsHelperInstall) {
    Button("Install Helper…") { installHelper() }
    Button("Not Now", role: .cancel) {}
} message: {
    Text("AerialWall requires a privileged helper to write to the macOS wallpaper database. You'll be asked for your password once.")
}
```

**Import error**:
```swift
.alert("Import Failed",
       isPresented: $showImportError) {
    Button("OK", role: .cancel) {}
} message: {
    Text(importErrorMessage)
}
```

Standard NSAlert maps to these automatically. Stick to .alert: no custom error sheets.

***

## Settings Window (Cmd+,)

Separate window opened via `Settings {}` scene or `NSWindowController`.

Use `.formStyle(.grouped)` (macOS 13+) for clean grouped preference layout:

```swift
Form {
    Section("General") {
        Toggle("Start helper at login", isOn: $launchAtLogin)
        Toggle("Apply wallpaper to all displays", isOn: $applyToAllDisplays)
    }

    Section("Import") {
        Picker("Video quality", selection: $quality) {
            Text("Fast").tag(Quality.fast)
            Text("Balanced").tag(Quality.balanced)
            Text("Maximum").tag(Quality.maximum)
        }
        Picker("Target resolution", selection: $resolution) {
            Text("4K (3840×2160)").tag(Resolution.uhd)
            Text("1080p (1920×1080)").tag(Resolution.fhd)
            Text("Match source").tag(Resolution.source)
        }
        Toggle("Keep original files", isOn: $keepOriginals)
    }

    Section("Advanced") {
        Picker("Base Apple asset", selection: $baseAsset) {
            ForEach(appleAssets) { asset in
                Text(asset.name).tag(asset.id)
            }
        }
        .pickerStyle(.menu)
    }

    Section {
        Button("Remove All Injected Wallpapers…", role: .destructive) {
            showRemoveAllAlert = true
        }
        Button("Uninstall AerialWall…", role: .destructive) {
            showUninstallAlert = true
        }
    } header: {
        Text("Danger Zone")
    }
}
.formStyle(.grouped)
```

Window size: ~480×520pt, not resizable. Standard preferences window proportions.

***

## Log Viewer (sidebar "Logs" selection)

Replace content area with a simple scrollable monospaced log view:

```swift
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(logLines) { line in
                Text(line.formatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(line.level.color)  // system colors only:
                                                        // .primary for INFO
                                                        // .green for SUCCESS
                                                        // .orange for WARN
                                                        // .red for ERROR
                    .textSelection(.enabled)
                    .id(line.id)
            }
        }
        .padding(12)
    }
    .onChange(of: logLines.count) {
        proxy.scrollTo(logLines.last?.id, anchor: .bottom)
    }
}
.background(Color(.textBackgroundColor))  // system text editor background
.toolbar {
    ToolbarItem(placement: .automatic) {
        Button("Clear") { logLines.removeAll() }
    }
}
```

No custom terminal styling. `.textBackgroundColor` + SF Mono + system semantic colors = looks correct everywhere.

***

## Onboarding (first launch: sheet)

One-time sheet presented on first launch over the main window:

```swift
.sheet(isPresented: $showOnboarding) {
    VStack(alignment: .leading, spacing: 20) {
        Text("Before you start")
            .font(.title2).bold()

        // Step list using native LabeledContent or plain VStack rows
        OnboardingStep(
            number: 1,
            title: "Install privileged helper",
            detail: "Required to write to the macOS wallpaper database.",
            isDone: helperInstalled,
            action: { installHelper() },
            actionLabel: "Install Helper…"
        )

        OnboardingStep(
            number: 2,
            title: "Download an Apple wallpaper video",
            detail: "Open System Settings → Wallpaper and download any Apple video (e.g. \"Dubai Skyline\").",
            isDone: aerialDBExists,
            action: { openSystemSettings() },
            actionLabel: "Open Wallpaper Settings"
        )

        OnboardingStep(
            number: 3,
            title: "Set that Apple video as your wallpaper",
            detail: "AerialWall will hook into that asset slot.",
            isDone: aerialVideoSelected
        )

        Spacer()

        HStack {
            Spacer()
            Button("Continue") { showOnboarding = false }
                .buttonStyle(.borderedProminent)
                .disabled(!allStepsDone)
                .keyboardShortcut(.return)
        }
    }
    .padding(24)
    .frame(width: 480, height: 360)
}
```

`OnboardingStep` is a plain HStack: step number in a circle (using `.background(Circle()...)`), title + detail as VStack, checkmark when done (SF Symbol `checkmark.circle.fill`, `.tint(.green)`), optional button.
Standard SwiftUI: no custom components beyond layout.

***

## Menubar Extra (optional)

If desired, a small NSStatusItem:

```swift
MenuBarExtra("AerialWall", systemImage: "photo.on.rectangle.angled") {
    if let current = appliedWallpaper {
        Text("Playing: \(current.name)")
            .font(.headline)
    } else {
        Text("No wallpaper applied")
            .foregroundStyle(.secondary)
    }
    Divider()
    Button("Open AerialWall…")   { openMainWindow() }
    Divider()
    Label(daemonStatusLabel, systemImage: daemonStatusIcon)
        .foregroundStyle(daemonStatusColor)  // .green / .orange / .red
    Divider()
    Button("Quit AerialWall") { NSApp.terminate(nil) }
}
.menuBarExtraStyle(.menu)
```

***

## Keyboard Shortcuts

All declared via `.keyboardShortcut` or `CommandGroup`:

```
Cmd+O          Import…
Cmd+F          Focus search
Return         Apply selected wallpaper
Delete         Remove selected (with confirmation alert)
Cmd+,          Settings
Cmd+L          Go to Logs
Cmd+R          Restart daemon
Cmd+Shift+F    Show in Finder
```

***

## The One Non-Native Tweak Allowed

**Thumbnail corner radius**: system `NSImageView` defaults to 0. Set `cornerRadius = 8` and `wantsLayer = true`. That's it. Everything else system-default.

***

## Implementation notes

- Use `Color(.windowBackgroundColor)`, `Color(.controlBackgroundColor)`, `Color(.separatorColor)`, `.primary`, `.secondary`, `.tertiary`: never hardcoded hex.
- Use `.tint(Color.accentColor)` for interactive highlights. System accent is user-configurable in System Settings.
- Use `.controlSize(.small)` on progress indicators and compact UI elements.
- Use `Table` over custom grids wherever possible: free accessibility, sorting, and keyboard nav.
- Use `ContentUnavailableView` for empty states (macOS 14+), `@available` fallback for older.
- App target: macOS 14+ minimum. No backward compat hacks needed for any of the above.
- Sandbox: **disabled** (required for `/Library` writes: document this clearly in the README).

***

## §Tahoe reconciliation (overrides above where they conflict with SPEC.md v2)

The base spec above was written before the live `entries.json` probe revealed
the Tahoe user-level model. The following overrides apply. Everything else
stands.

### R1: Privileged helper does not exist on Tahoe

Writes go to `~/Library/...` as the login user. No SMAppService helper, no XPC,
no password prompt. Affected:

- **Onboarding sheet**: drop step 1 ("Install privileged helper"). Renumber:
  - step 1 (was 2): "Download an Apple wallpaper video"
  - step 2 (was 3): "Set that Apple video as your wallpaper"
  - (and even those become *optional*: `entries.json` is shipped pre-populated
    by `manifest.tar` on first login, so a fresh install can usually skip both.
    Show the onboarding only if `Constants.entriesJSONPath` is absent.)
- **Apply wallpaper §step 2**: drop "If privileged helper not installed yet → NSAlert".
  No alert. Just call the local injection path.
- **"AerialWall needs permission" alert**: remove entirely.
- **Settings → General → "Start helper at login"**: replace with
  **"Start watcher at login"** (the AerialWallAgent LaunchAgent, user-domain).

### R2: Storage path references

User-facing text mentions `/Users/Shared/AerialWall/Library`. Replace ∀ with
`~/Library/Application Support/AerialWall/library/` (SPEC §I, V22).

### R3: Settings → Advanced "Base Apple asset" picker

Obsolete model (slot-hooking an existing Apple asset). On Tahoe we append a
fresh entry to `entries.json` directly. **Drop the entire Advanced section** or
repurpose it for FFmpeg path override (`AERIALWALL_FFMPEG`): see SPEC T5.

### R4: Deployment target

GUI spec says "macOS 14+ minimum". SPEC §C is **macOS 26 (Tahoe) ≥ 26.4 only**.
All GUI components used here (`NavigationSplitView`, `Table`,
`ContentUnavailableView`, `.formStyle(.grouped)`, `MenuBarExtra`,
`@Observable`) are available on 26+.

### R5: Sandbox justification

README must say: sandbox is disabled because the wallpaper aerials directory
(`~/Library/Application Support/com.apple.wallpaper/aerials/`) is **outside the
sandbox container** even though it lives under `~/Library/`. There is no `/Library/`
write requirement: that was the macOS-15 model.

### R6: Daemon status surface

GUI spec references "daemonStatusLabel" / "daemonStatusIcon" in the MenuBarExtra.
The only relevant daemon is `com.apple.wallpaper.agent` (SPEC §I). The label
should reflect whether `AgentRestart.findAgentPID()` returns a PID:

- found: green dot, "WallpaperAgent running"
- missing: red dot, "WallpaperAgent not running"

There's also a second daemon to surface: the **AerialWall** LaunchAgent
(`com.aerialwall.agent`): `.green` when loaded, `.orange` when not.
