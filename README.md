<p align="center">
  <img src="screenshots/sunpaper-lockup.png" width="420" alt="Sunpaper">
</p>

# Sunpaper

Sunpaper is a native macOS menu bar app that changes Apple aerial wallpapers
throughout your day. Build a schedule around sunrise and sunset, use fixed
times, or choose a wallpaper temporarily. Custom still images work too.

## Download

Get the packaged app from **[GitHub Releases](https://github.com/mduncs/sunpaper/releases/latest)**,
open the disk image, and drag Sunpaper to Applications.

The latest published release is **v1.1.0 (March 17, 2026)**. It predates the
interface described below. These features and screenshots document the
**current source tree**; this source update does not publish a new app release.

## Your day

Open **Edit schedule…** from the menu bar to arrange your day. Each row has
separate wallpaper and timing choices. Start with a matching Tahoe or Sequoia
collection, or add your own changes. Row menus offer rename, enable/disable,
duplicate, **Download again**, and remove. Schedule edits support undo and redo.

![Your day in dark appearance](screenshots/your-day.png)

These screenshots show real SwiftUI views rendered in offscreen windows with
sample configuration and fake wallpaper services. They illustrate the source
UI—not the current desktop or a live wallpaper-transition test.

<details>
<summary>More screenshots: light appearance, menu states, and editors</summary>

| Your day · light | Settings |
| --- | --- |
| <img src="screenshots/your-day-light.png" width="440" alt="Your day in light appearance"> | <img src="screenshots/settings.png" width="440" alt="Settings with optional smoothing and screen capture access"> |

| Following | Temporary wallpaper | Paused |
| --- | --- | --- |
| <img src="screenshots/menu.png" width="270" alt="Menu bar panel following the schedule"> | <img src="screenshots/menu-temporary.png" width="270" alt="Menu bar panel with a temporary wallpaper and override duration"> | <img src="screenshots/menu-paused.png" width="270" alt="Menu bar panel with the schedule paused"> |

![Wallpaper picker with an explicit confirmation button](screenshots/wallpaper-picker.png)

| Timing editor | Location chooser |
| --- | --- |
| <img src="screenshots/timing-editor.png" width="440" alt="Timing editor with a draft schedule rule"> | <img src="screenshots/location-picker.png" width="440" alt="Location chooser with search and explicit current-location action"> |

</details>

The menu shows the last successfully applied wallpaper, playback state, and
next change. **Pause schedule** keeps the wallpaper while leaving the schedule
editable. **Use another wallpaper…** opens a picker with a still preview;
browsing does not change the desktop. Confirm your choice to apply it, or
cancel without changing anything.

A manual choice while following is temporary: **until the next change**, **for
one hour**, or **until tomorrow** (local midnight). Change its duration in the
menu, or choose **Resume schedule**. A manual choice while paused stays paused.
Temporary overrides last for the current app session; reopening uses the saved
following/paused setting.

## Location and displays

Solar times are calculated locally from your chosen location. Search for a city
and confirm it, or explicitly choose **Use current location** to request macOS
location access. Sunpaper does not ask for location at startup or silently pick
a fallback city. Fixed-time schedules need no location permission or saved
location; city search uses macOS geocoding and may need a connection.

Use one schedule for all displays or select **Different for each display**
in Settings. Each display keeps its saved rules when disconnected or when you
switch modes. Editing a collection or a rule affects only its chosen scope.

## Optional smoothing

**Settings → Smooth wallpaper changes** keeps the previous wallpaper visible
while the next aerial loads. It is on by default and needs macOS screen capture
access. The explicit **Allow screen capture…** action requests that access;
background scheduling does not prompt. Only the wallpaper is captured, not app
windows or audio, and those images stay in memory.

You can turn smoothing off. Scheduling and manual changes then work without
screen capture access, although macOS may briefly show gray during an aerial
reload. The setting includes a **Why is this needed?** explanation. Settings
also contains launch-at-login, location, display mode, retry, and desktop
recovery controls.

Smoothing is a visual workaround, not Apple's private native handoff. See
[TRANSITIONS.md](TRANSITIONS.md) for implementation details and validation limits;
SIP-enabled live handoff validation is still outstanding.

## Requirements and troubleshooting

Sunpaper requires **macOS 14 Sonoma or newer** and is distributed outside the
Mac App Store. Apple aerial switching relies on macOS wallpaper behavior that
may change with system updates. Custom imports support still images, not
custom video files.

If the aerial catalog is empty, open **System Settings → Wallpaper**, download
an Apple aerial, and reopen Sunpaper. Missing selected aerials are downloaded
when needed. A row's **Download again** fetches a fresh copy without discarding
the working file until replacement succeeds.

If a change fails, the last successful wallpaper remains the confirmed choice;
use **Retry** after addressing the reported problem. With smoothing on, missing
screen capture access prevents the change; allow access in Settings or turn
smoothing off. If macOS asks you to quit and reopen after granting access, do
that before retrying. A retained recovery cover exposes **Restore desktop**.

## Building and verification

Open `Sunpaper.xcodeproj` in Xcode and run the Sunpaper scheme, or run its tests:

```sh
git clone https://github.com/mduncs/sunpaper.git
cd sunpaper
xcodebuild test \
  -project Sunpaper.xcodeproj \
  -scheme Sunpaper \
  -destination 'platform=macOS'
```

The current verification baseline is **182 passing Debug unit tests** and a
successful Release build. UI screenshots are generated by the offscreen harness
in [scripts/screenshots/Render.swift](scripts/screenshots/Render.swift). Run
`./scripts/screenshots/render.sh` on a Mac with the Tahoe aerial catalog
available. It renders into `screenshots/` without opening app windows or
changing the desktop. Appearance and downloaded badges reflect local macOS
settings and catalog availability.
See [UI-REFINEMENT.md](UI-REFINEMENT.md) for the interaction and verification notes.

Maintainers can create a signed, notarized release with `scripts/release.sh`;
run `scripts/release.sh --help` for usage. This is separate from building the
source or updating the screenshot gallery.

## License

[MIT](LICENSE)
