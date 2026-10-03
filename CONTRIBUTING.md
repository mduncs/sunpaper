# Development guide

The [README](README.md) covers using Sunpaper. This guide covers building,
maintaining, and verifying the current source.

## Build and test

Open `Sunpaper.xcodeproj` in Xcode and run the Sunpaper scheme, or use:

```sh
xcodebuild test -project Sunpaper.xcodeproj -scheme Sunpaper \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/debug -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Sunpaper.xcodeproj -scheme Sunpaper \
  -configuration Release -derivedDataPath build/release-check CODE_SIGNING_ALLOWED=NO
```

These commands produce local, unsigned verification builds. The October 3,
2026 baseline is **228 passing unit tests** and a successful Release build.
Tests inject wallpaper services, timers, and display state; they do not change
the real desktop. A passing build or local launch is not a live handoff test.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sunpaper/Models` | Catalog, schedule rules, and persisted configuration |
| `Sunpaper/Services` | Shared controller, scheduling, displays, and wallpaper operations |
| `Sunpaper/Views` | SwiftUI surfaces and shared design components |
| `SunpaperTests` | Unit tests and wallpaper-only regression fixtures |
| `screenshots` | Current UI examples and repository branding |
| `scripts/screenshots` | Reproducible offscreen screenshot renderer |
| `scripts/release.sh` | Signed/notarized release packaging |

Keep generated builds in ignored `build/` and packages in ignored `dist/`.
Historical design drafts and machine-specific research belong outside the
checkout, not alongside current documentation. `site/`, when present locally,
is a separate repository. Required app-icon resolutions and screenshot states
are intentional variants, not archived versions.

## Runtime contracts

One controller owns shared runtime state and persisted preferences. Construction
is inert; app startup explicitly starts scheduling. Preserve compatibility with
older saved configuration through the versioned-envelope decoder. Unreadable
data is copied once to `wallpaperConfig.unreadableBackup` before defaults take
over, and data from a newer schema is never overwritten. Keep persisted keys
stable across renames (`isFollowingSchedule` is still saved as
`enableSolarTracking`). Coordinates are validated on load, edit, and choose.

The expected schedule and the last successfully applied wallpaper are separate
state. A due slot does not prove an application succeeded. Confirm each display
only after success, including partial success when applying custom images to
all displays. Failed or superseded requests must not publish stale confirmation.

Pause preserves the wallpaper while allowing edits. Manual choices while
following create session-only overrides; choices while paused remain paused.
Keep override deadlines through ordinary edits, reconcile after wake, and
restore the persisted following/paused setting on reopening. Cosmetic edits
must not reapply a confirmed wallpaper. Disabled or unassigned rows are not
wallpaper changes.

Fixed rules work without location. Solar rules use saved coordinates; request
current-location access only through an explicit user action. Per-display
schedules survive mode changes and disconnection. Open editors retain their
original display scope. Pickers and editors use drafts: cancellation neither
applies wallpaper nor imports a file. Undoing an edit must not undo a later
pause or smoothing preference. Aerial re-downloads preserve the working file
until replacement succeeds; custom imports support still images only.

## Wallpaper store layout

Verified live on macOS 27 (October 2026), and modelled in
`WallpaperStoreLayout`:

- An `AllSpacesAndDisplays` dictionary is one wallpaper everywhere. It
  overrides both `Displays` and `Spaces`.
- Per-display wallpapers need `AllSpacesAndDisplays` set to the string `$null`,
  plus `Displays.<UUID>` entries keyed by `CGDisplayCreateUUIDFromDisplayID`.
  Sunpaper's own saved display IDs are translated only when writing.
- WallpaperAgent then derives `Spaces.<space>` entries from `Displays`. Those
  win afterwards, so a per-display change drops the Spaces that reference its
  display.

Sunpaper writes whole entries (`{Type: linked, Linked: {Content, LastSet,
LastUse}}`) so a missing parent key can't fail a change. Leaving all-displays
mode copies the current wallpaper to the other connected displays first.
Verification compares each display's entry, and each custom image, with the
schedule.

## Smooth wallpaper handoff

Smoothing is a visual workaround, not Apple's entitlement-protected native
aerial setter. **Integrated SIP-enabled live validation remains outstanding.**
The product does not use a private entitlement, injection, TCC modification,
or a SIP change.

ScreenCaptureKit snapshots WindowManager's wallpaper window on each display.
Click-through, nonactivating desktop-level windows hold those pictures during
the `Index.plist` write and wallpaper reload. New pictures blend *inside opaque
windows* before the covers are removed; fading the whole windows can expose a
black dip. Reduce Motion skips the blend, not readiness or recovery checks.
Captures stay in memory and exclude app windows, cursor, audio, and recordings.

### Permission and serialization

Smoothing defaults to on, including for older preferences. Without screen
capture access, a smoothed change falls back to the unsmoothed path instead of
failing, and the scheduler publishes `smoothingUnavailableBecauseOfPermission`
so Settings can say so. Background scheduling never prompts. Settings provides
an explicit permission request, **Quit & Reopen** (macOS caches the permission
check per process), and an opt-out. With smoothing off, changes still serialize, validate video readability,
and roll back on failure, but use no capture, overlays, or visual polling. A
gray flash may be visible.

Snapshot the smoothing preference for each request. Changing it does not replay
a successful change, alter an in-flight request, or extend an override; it can
retry a scheduled change that failed. A shared gate
serializes aerial changes across displays. Cancellation must finish recovery
before the next mutation. Static `NSWorkspace` changes are rejected while an
aerial transition or recovery owns the desktop. Provider writes must succeed
before an aerial update can count as successful.

### Readiness and recovery

Compare spatial RGB signatures with representative frames from the requested
aerial's first minute, aspect-filled for each display. Constrained exposure
adjustment handles dimmed secondary wallpapers; the matcher has no scene IDs
or scene-specific color rules. Every display must depart from its original
appearance and match the expected scene for three consecutive samples. Check
again after blending before removing covers.

On failure, restore the exact pre-change `Index.plist` and verify the previous
appearance under cover. Failed restoration retains the cover and exposes
**Restore desktop**, without leaving a permanent polling loop. Resolve any
retained cover before another change, even with smoothing off: **Retry**
restores first, then retries the change. Covers fit only the display layout
they were captured for. After a display change they can't be verified, so
recovery removes them and restores uncovered. Display changes settle for two
seconds, then retry a retained recovery once before reconciling the schedule.
An uncovered restoration failure must not claim a cover exists. Quit waits for
pending work and asks before discarding a retained recovery cover.

### Validation limits

Readiness uses conservative image matching, not a native renderer-ready signal.
The polling budget is 25 seconds per reload/restoration; OS asynchronous capture
and decoding calls are not hard real-time deadlines. Flat scenes, frames outside
the sampled interval, unusual scaling, or changed display layouts may be
inconclusive and trigger recovery.

An earlier SIP-disabled prototype showed no suspect gray/black frames in its
limited two-scene test; that does not validate the integrated implementation.
The production matcher was also checked offline against 28 native frames from
two displays. Four wallpaper-only native/reference pairs are retained as
[regression fixtures](SunpaperTests/Fixtures/README.md), alongside tests for
cancellation, serialization, recovery failures, downloads, and stale state.

Before claiming no-flash behavior with SIP on, verify real transitions with
normal capture permission and visually evaluate the handoff. Spaces,
full-screen apps, lock/wake, and display reconfiguration also need live coverage.

## Screenshots

```sh
./scripts/screenshots/render.sh
# Optional output directory:
./scripts/screenshots/render.sh /tmp/sunpaper-screenshots
```

Run on a Mac with the Tahoe aerial catalog available. The
[renderer](scripts/screenshots/Render.swift) uses actual SwiftUI views in
never-shown windows, sample configuration, and fake wallpaper services. It
does not launch Sunpaper, change wallpaper, or take over the user's desktop.
Appearance and downloaded badges reflect local macOS/catalog state.

The default output is `screenshots/`: dark/light schedule and Settings views,
three menu states, the wallpaper/timing/add-change/location editors, and
smoothing off.
Review these current variants together when changing shared UI. Offscreen
renders verify layout, not foreground interactions or live transition quality.

## Releases

Run `scripts/release.sh --help` for signed, notarized DMG requirements. The
`--unsigned` option is for local packaging verification, not distribution.
Packaging outputs go to `dist/`; never commit app bundles, signing material,
raw captures, or machine-specific desktop configurations. A source push or
screenshot refresh does not publish a new downloadable release.
