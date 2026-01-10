# Sunpaper - Wallpaper Internals

## How macOS Aerial Video Wallpaper Changing Works

### The Index.plist Structure

The wallpaper configuration lives at:
```
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

**CRITICAL**: This plist has TWO different modes that use DIFFERENT keypaths:

#### Mode 1: "linked" (all displays same wallpaper)
```
AllSpacesAndDisplays.Type = "linked"
AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration  <- SET THIS
SystemDefault.Linked.Content.Choices.0.Configuration         <- AND THIS
Displays = {} (empty)
```

#### Mode 2: "individual" (per-display wallpapers)
```
AllSpacesAndDisplays.Type = "idle" or "individual"
Displays.<UUID>.Desktop.Content.Choices.0.Configuration      <- SET EACH DISPLAY
```

### How to Change Aerial Wallpapers

1. **Kill processes FIRST** (they cache state and write it back on exit):
   ```bash
   killall WallpaperAgent WallpaperAerialsExtension
   sleep 0.3
   ```

2. **Create the Configuration value** (binary plist with assetID, base64 encoded):
   ```python
   import plistlib, base64
   config = {"assetID": "4C108785-A7BA-422E-9C79-B0129F1D5550"}
   binary = plistlib.dumps(config, fmt=plistlib.FMT_BINARY)
   base64_config = base64.b64encode(binary).decode()
   ```

3. **Update the plist** using plutil:
   ```bash
   plutil -replace "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration" \
     -data "$BASE64_CONFIG" "$PLIST_PATH"
   plutil -replace "SystemDefault.Linked.Content.Choices.0.Configuration" \
     -data "$BASE64_CONFIG" "$PLIST_PATH"
   ```

4. **Kill WallpaperAgent AGAIN to force reload** (critical - it won't pick up changes otherwise):
   ```bash
   sleep 0.1
   killall WallpaperAgent
   ```

   launchd auto-restarts the process, which then reads the NEW plist values.

### Tahoe Wallpaper Asset IDs
```
Morning: B2FC91ED-6891-4DEB-85A1-268B2B4160B6
Day:     4C108785-A7BA-422E-9C79-B0129F1D5550
Evening: 52ACB9B8-75FC-4516-BC60-4550CFF3B661
Night:   CF6347E2-4F81-4410-8892-4830991B6C5A
```

### Common Mistakes (things that broke it before)

1. **Using wrong keypaths**: If plist is in "linked" mode but you write to `Desktop` paths, nothing happens (keys don't exist).

2. **Killing processes AFTER modifying plist**: The processes write their cached state on exit, overwriting your changes.

3. **Only killing WallpaperAgent**: The `WallpaperAerialsExtension` also caches state. Kill both BEFORE modifying.

4. **NOT killing WallpaperAgent after modifying**: The process won't pick up new plist values unless restarted. Kill it AFTER modifying too.

5. **Wrong Provider value**: Aerials need `Provider = "com.apple.wallpaper.choice.aerials"` (not "image").

### How to Debug

Check plist mode:
```bash
plutil -p "$PLIST" | head -20
```

Verify assetID was set:
```bash
plutil -extract "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration" raw "$PLIST" | base64 -d | plutil -p -
```

Debug log location: `/tmp/sunpaper-debug.log`

### Backup/Restore

If plist gets corrupted or switches to wrong mode:
```bash
# Backup exists at:
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist.backup

# To restore linked mode:
killall WallpaperAgent WallpaperAerialsExtension
cp "$BACKUP" "$PLIST"
```
