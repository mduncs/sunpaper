# Sunpaper interface and runtime

This document describes the current source interface. The latest published
[GitHub release](https://github.com/mduncs/sunpaper/releases/latest), v1.1.0
(March 17, 2026), predates these changes. This source update does not publish a
new app release.

## App surfaces

| Surface | Behaviour |
| --- | --- |
| Your day | Shared schedule editor with confirmed wallpaper, next change, location, and display scope. Four standard changes fit in the default window. |
| Schedule rows | Separate wallpaper and timing choices. Rename, enable/disable, duplicate, download again, or remove through the row menu. Disabled changes remain editable. |
| Collections | Tahoe or Sequoia replaces the selected scope with four matching changes in one undoable edit. |
| Menu bar | Consistent following, temporary, and paused states, with choose/edit/settings commands and retry after a failed change. |
| Wallpaper picker | Local selection and still preview; only explicit confirmation saves or applies a choice. Cancel leaves the selection unchanged and does not import files. Local download availability is shown. |
| Timing editor | Draft solar or fixed-time rule with today's resolved time. Done saves; Cancel discards. Fixed times work without location. |
| Location chooser | City search or an explicit current-location request, followed by confirmation. No startup permission prompt or silent fallback city. |
| Settings | Login item, location, display mode, optional smoothing, screen capture access, and recovery. Troubleshooting is secondary; clearing a schedule is separate and undoable. |

## Runtime semantics

One controller owns persisted preferences and shared runtime state. Construction
is inert; app startup explicitly starts scheduling. Older saved configuration
remains readable through the compatible versioned-envelope decoder.

Expected schedule and successful wallpaper confirmation are separate. A due
slot is not proof that its wallpaper applied. Each display retains its own
successful confirmation; failures and superseded requests cannot publish an
unconfirmed choice. All-display custom images are applied as scoped jobs so a
partial failure still records the displays that succeeded.

Pause keeps the wallpaper while allowing schedule edits. Manual choices while
following create temporary overrides: next change, one hour, or tomorrow at
local midnight. Choosing manually while paused remains paused. Overrides keep
their deadline through ordinary edits, reconcile after wake, and can end early
with Resume schedule. They are session-only; reopening uses the persisted
following/paused setting. Unassigned or disabled rows are not wallpaper changes.

Fixed rules resolve without a location. Solar times are calculated locally from
saved coordinates; city search uses macOS geocoding, while current-location
access is requested only by the user's explicit action.

Cosmetic edits do not restart wallpaper changes. Per-display schedules survive
mode switches and disconnected displays. Open editors retain their captured
display scope even when selection or display mode changes elsewhere. Collection
replacement and other schedule edits support undo/redo without undoing a later
pause or smoothing preference. Custom imports are still images; Download again
retains an aerial's working file until its replacement succeeds.

## Smoothing and recovery

Smoothing is enabled by default, including for older preferences. It uses a
public-API wallpaper-only visual cover, not Apple's private native setter.
Screen capture access is needed only with smoothing on and is requested through
the explicit Settings action. Wallpaper snapshots stay in memory; app windows,
audio, and recording files are not captured.

With smoothing off, scheduling and manual choices use the same serialized
aerial reload without capture or overlays; a gray flash may be visible. Changing
the preference does not restart a confirmed wallpaper, alter an in-flight
application's snapshotted policy, or extend a temporary override. It can retry a
scheduled change that previously failed for lack of capture access.

Cancellation still waits for required recovery. Failed covered restoration retains the old picture and exposes Restore desktop
instead of claiming success. An uncovered restoration failure reports that the
previous configuration could not be restored, without claiming a cover exists. Reduce Motion skips the blend,
not the readiness and recovery checks. See [TRANSITIONS.md](TRANSITIONS.md) for
the implementation and remaining live-validation limits.

## Screenshots and verification

The current baseline is **182 passing Debug unit tests** and a successful
Release build. Tests use injected dependencies rather than real wallpaper
setters. The screenshot harness renders actual SwiftUI views in offscreen,
never-shown windows using sample configuration and fake wallpaper services.
These images are sample UI examples, not captures of the current desktop
or evidence of a live wallpaper transition.

The public harness is [scripts/screenshots/Render.swift](scripts/screenshots/Render.swift),
with [scripts/screenshots/render.sh](scripts/screenshots/render.sh) as the entry
point. The [README gallery](README.md#your-day) shows its output:

| View | Screenshot |
| --- | --- |
| Your day, dark / light | [Dark](screenshots/your-day.png) · [Light](screenshots/your-day-light.png) |
| Menu, following / temporary / paused | [Following](screenshots/menu.png) · [Temporary](screenshots/menu-temporary.png) · [Paused](screenshots/menu-paused.png) |
| Settings, including smoothing | [Settings](screenshots/settings.png) |
| Wallpaper picker | [Picker](screenshots/wallpaper-picker.png) |
| Timing editor | [Timing](screenshots/timing-editor.png) |
| Location chooser | [Location](screenshots/location-picker.png) |

Offscreen rendering verifies layout, not foreground click-through behaviour.
SIP-enabled live smoothing, Spaces/full-screen, lock/wake, and display-change
handoff validation remain separate acceptance work.
