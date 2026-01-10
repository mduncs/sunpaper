# Sunpaper

Automatically change video wallpapers on macOS.

Apple's aerial wallpaper collections (Tahoe, Sequoia) include time-of-day variants - morning, day, evening, and night versions of the same location. Sunpaper switches between them based on the actual sun position at your location.

## Screenshots

<p align="center">
  <img src="screenshots/menu.png" width="280" alt="Menu bar showing today's schedule">
  <img src="screenshots/settings.png" width="380" alt="Settings window">
</p>

## Getting Started

1. **Download Apple's aerial wallpapers first**: System Settings > Wallpaper > choose Tahoe or Sequoia and let it download
2. Download Sunpaper and move it to your Applications folder
3. Launch Sunpaper - it appears as a sun icon in your menu bar
4. Grant location permission when prompted
5. Done - your wallpaper now follows the sun

The app references wallpapers already on your Mac. If you haven't downloaded an aerial collection from System Settings, there's nothing to switch between.

## Features

- **Solar-aware scheduling** - transitions happen at actual sunrise and sunset for your location
- **Flexible time slots** - add, remove, or customize transition times
- **Multiple collections** - Tahoe and Sequoia built-in
- **Multi-monitor support** - same wallpaper on all displays, or configure each separately
- **Launch at login** - runs quietly in the background

## How It Works

Apple's aerial collections are designed with time-of-day in mind:
- **Tahoe** has morning, day, evening, and night variants
- **Sequoia** has sunrise, day, and night variants

Sunpaper calculates sunrise and sunset times for your location using the NOAA solar position algorithm, then switches to the matching wallpaper variant. Morning light on screen as the sun comes up, night sky when it gets dark.

## Settings

Click the menu bar icon to see today's schedule. Open Settings to:

- Add or remove time slots
- Set triggers relative to solar events (e.g., "30 minutes before sunset") or fixed times
- Choose which variant plays at each time of day
- Configure per-display wallpapers

## Requirements

- macOS 14.0 (Sonoma) or later - macOS 15.0 (Sequoia) recommended
- Aerial wallpapers must be downloaded first: System Settings > Wallpaper > select an aerial collection

## Known Issues

- **Brief gray flash during transitions** - you may see a gray screen for less than a second while the new video loads. This is a limitation of how macOS refreshes video wallpapers.

## Building from Source

```
git clone https://github.com/mduncs/sunpaper.git
cd sunpaper
xcodebuild -scheme Sunpaper -configuration Release
```

The built app will be in `build/Build/Products/Release/Sunpaper.app`

## Why Not on the App Store?

macOS doesn't provide a public API for changing video wallpapers. Sunpaper works by updating the system's wallpaper configuration file directly, which requires file system access that App Store sandboxing doesn't allow.

## Credits

Built with Claude (Anthropic). Solar calculations based on NOAA's solar position equations.

## License

MIT
