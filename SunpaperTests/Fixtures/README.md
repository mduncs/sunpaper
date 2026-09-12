# Wallpaper frame signatures

`WallpaperFrameSignatures.json` contains four 32×24 RGB samples from the September 9, 2026 target-window-only native wallpaper recordings: Tahoe Day and Golden Gate Sunset, on the main and dimmed secondary display. Each base64 value represents packed RGB bytes, not a screenshot file.

`captured` is a native frame; `reference` is the aspect-filled video/reference frame it should match; `otherScene` is the other scene at the same aspect ratio, which it must reject. These regression fixtures exercise real crop/dimming differences independently of the synthetic dark, monochrome, blank, and wrong-scene tests. The production matcher contains no scene identifiers.
