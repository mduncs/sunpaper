# Custom video wallpapers

Research for [issue #2](https://github.com/mduncs/sunpaper/issues/2). Sunpaper
doesn't do this yet.

Everything below comes from macOS 27.2 (26B5091g): read-only inspection of the
wallpaper store and system binaries, the unified log, and test encodes. **No
custom video has been played through the wallpaper engine yet.** The install
steps in section 3 are untested on 27.2; community tools report them working
on macOS 26. Claims are marked *verified* (checked on 27.2), *reported* (from a
source in the list at the end), or *unknown*.

## Short answer

| Goal | Possible? | How |
| --- | --- | --- |
| Make a video Apple's engine accepts | Yes | A special HEVC encode, made with the tools in this folder |
| Show it as a real wallpaper | Yes on macOS 26 (reported); untested on 27.2 | Add it to the aerial catalog |
| Keep it playing on the desktop | **Not with Apple's engine** | Our own wallpaper extension (private API), or a desktop-level video window |

Apple's engine plays aerials on the lock screen and in the screen saver, then
slows them to a still frame when you unlock. No setting, defaults key, or
`Index.plist` field changes that (*verified*). Issue #2 asks for a real
wallpaper, not an overlay window, and the only way to get one that keeps
playing on the desktop is our own wallpaper extension. See the
[recommendation](#recommendation) in section 4.

## 1. How macOS plays aerials

Paths are under `~/Library/Application Support/com.apple.wallpaper/`.

| Piece | What it is |
| --- | --- |
| WallpaperAgent | Hosts wallpaper extensions on the ExtensionKit point `com.apple.wallpaper` |
| WallpaperAerialsExtension | Apple's aerial renderer, a sandboxed XPC process |
| `aerials/manifest/entries.json` | The catalog. Unpacked from a tar that Apple republishes rarely (last on 2026-09-03); the extension checks for a new one about every 12 hours |
| `aerials/videos/<assetID>.mov` | Downloaded videos |
| `aerials/thumbnails/<id>.png` | 214×130 thumbnails, one per asset and one per subcategory |
| `Store/Index.plist` | The selection, by asset ID. Sunpaper already writes it; see [Wallpaper store layout](../../CONTRIBUTING.md#wallpaper-store-layout) |

Two details shape everything else (*verified*):

- **Custom files must live under `com.apple.wallpaper/`.** The extension's
  sandbox can't read anywhere else in the home folder.
- **The extension slows playback by dropping HEVC temporal sub-layers.** It
  doesn't use AVPlayer; it reads samples itself and steps down through
  temporal levels as it ramps to a still. A file without temporal-layer
  metadata fails with `noTemporalInfo`. The reported symptom: it plays on the
  first lock, pauses on unlock, and never plays again.

## 2. Encoding

| Property | Apple's aerials | Target |
| --- | --- | --- |
| Codec | HEVC Main 10, tagged `hvc1` | Same |
| Pixels and color | 10-bit 4:2:0, BT.709, limited range, SDR | Same |
| Size | 3840×2160 | Same; other sizes *unknown* |
| Frame rate | 240 fps (frame-rate converted) | 60 fps, or 240 fps for the smoothest slowdown |
| Temporal layers | 5, with `tscl` and `tsas` sample groups | 3 or more, with both groups |
| Key frames | Every 5 s | Every 5 s |
| Bit rate | ~12 Mbps | 25–40 Mbps (hardware encoder) |
| Length | 300 s | 60–300 s |
| Audio | None | None |

**ffmpeg can't make this file** (*verified*, ffmpeg 8.1). `hevc_videotoolbox`
produces one layer. `libx265 -x265-params temporal-layers=5` produces layers,
but the mov muxer writes no `tscl`/`tsas` groups. VideoToolbox plus
AVAssetWriter does write them, so the pipeline is ffmpeg for preparation and
`aerial-encode` for the final file.

Commands below run from the repository root.

### Step 1: prepare a ProRes intermediate

This scales and crops to 4K, sets the frame rate, strips audio, tags BT.709,
and builds a seamless loop:

```sh
IN=input.mp4; D=62; F=2    # D = source seconds to use, F = crossfade seconds
ffmpeg -i "$IN" -an -filter_complex \
 "[0:v]scale=3840:2160:force_original_aspect_ratio=increase:flags=lanczos,crop=3840:2160,fps=60,setsar=1,format=yuv422p10le,split[body][head];\
  [head]trim=0:$F,setpts=PTS-STARTPTS[h];\
  [body]trim=$F:$D,setpts=PTS-STARTPTS[b];\
  [b][h]xfade=transition=fade:duration=$F:offset=$((D-2*F)),format=yuv422p10le[v]" \
 -map "[v]" -c:v prores_videotoolbox -profile:v hq \
 -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv prep.mov
```

The output starts at source time `F` and ends by fading into the source's
first `F` seconds, so its last frame leads straight into its first. It is
`D-F` seconds long: 60 s here, a whole number of 5-second key-frame intervals.
Whether the engine loops one clip or queues the next is *unknown*, so make the
seam clean either way.

For an Apple-smooth slowdown, interpolate to 240 fps: replace `fps=60` with
`minterpolate=fps=240:mi_mode=mci` (slow, may leave artifacts), or use an
optical-flow tool such as DaVinci Resolve. *Unknown, inferred*: the ramp slows
time toward zero, so a 60 fps clip shows few distinct frames near the end.

### Step 2: encode with temporal layers

```sh
swiftc -O -o aerial-encode scripts/video/aerial-encode.swift   # once
./aerial-encode prep.mov custom.mov 60 15 3 30       # fps, base-layer fps, layers, Mbps
./aerial-encode prep240.mov custom.mov 240 15 5 40   # 240 fps variant
```

It uses the hardware HEVC encoder with a 15 fps base layer and the
undocumented `NumberOfTemporalLayers` key, re-times frames onto a constant
rate, and writes through an AVAssetWriter passthrough input. At 240 fps the
encoder settles on 4 layers rather than 5 (*verified*).

One difference from Apple's files remains: our `hvcC` box reports one temporal
layer where Apple's reports 5, although the `tscl` groups are correct. Whether
the engine reads that field is *unknown*; tools built the same way are
reported to work on macOS 26.

### Step 3: check the file

```sh
scripts/video/check-aerial-video.py custom.mov
ffprobe -v error -show_entries stream=codec_tag_string,profile,pix_fmt,width,height,r_frame_rate,color_range,color_primaries -of compact custom.mov
# expect: hvc1 | Main 10 | yuv420p10le | 3840x2160 | 60/1 | tv | bt709
```

The checker confirms `hvc1`, the `tscl` description and mapping, the `tsas`
group, no audio, and the key-frame interval. It passes Apple's aerials and
`aerial-encode` output, and fails both ffmpeg encodes (*verified*).

## 3. Installing into Apple's catalog

These steps change the live desktop. Run them by hand, not from an agent, and
**pause Sunpaper first** so it doesn't rewrite `Index.plist` or restart
WallpaperAgent mid-test.

```sh
A="$HOME/Library/Application Support/com.apple.wallpaper"
BK="$HOME/WallpaperBackup-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
ditto "$A/Store" "$BK/Store"
ditto "$A/aerials/manifest" "$BK/manifest"
defaults export com.apple.wallpaper.aerial "$BK/com.apple.wallpaper.aerial.plist"
```

### Route A: replace an aerial's video (quick test)

Swap the file behind the aerial that is showing now. It keeps Apple's name and
thumbnail.

```sh
ID=<asset ID of the current aerial>
V="$A/aerials/videos/$ID.mov"
ditto "$V" "$BK/$ID.mov"              # ditto keeps the SourceURL/LastETag attributes
ditto custom.mov "$V.new"
xattr -w SourceURL "$(xattr -p SourceURL "$V")" "$V.new"
xattr -w LastETag "$(xattr -p LastETag "$V")" "$V.new"
mv -f "$V.new" "$V"
killall WallpaperAerialsExtension WallpaperAgent    # both relaunch on demand
```

Restore with `ditto "$BK/$ID.mov" "$V"` and the same `killall`.

The swap lasts until Apple changes that asset's download URL (the extension
then re-downloads in-use videos whose URL changed, *verified*) or a macOS
update restores the originals (*reported*). Copying the attributes is meant to
avoid an early re-download; that is *untested*.

### Route B: a private catalog (durable)

Give the video its own asset ID in a copy of the catalog, then point the
extension at the copy with two undocumented defaults. Both keys are in the
27.2 binary, with log strings such as "AerialManifestForceLocal is set;
skipping downloaded manifest" (*verified*), and are reported working on 27.0
through 27.2 beta 2.

```sh
U=$(uuidgen); C="$A/aerials/custom"; mkdir -p "$C"
scripts/video/add-catalog-entry.py "$A/aerials/manifest/entries.json" "$C/entries.json" \
  --id "$U" --name "My Video" --video "$A/aerials/videos/$U.mov" --thumb "$A/aerials/thumbnails/$U.png"
SUB=<subcategory ID the script printed>
ditto custom.mov "$A/aerials/videos/$U.mov"
ffmpeg -ss 3 -i custom.mov -frames:v 1 -vf "scale=-2:130,crop=214:130" "$A/aerials/thumbnails/$U.png"
cp "$A/aerials/thumbnails/$U.png" "$A/aerials/thumbnails/$SUB.png"
defaults write com.apple.wallpaper.aerial AerialManifestLocalPathOverride -string "$C/entries.json"
defaults write com.apple.wallpaper.aerial AerialManifestForceLocal -bool true
killall WallpaperAerialsExtension WallpaperAgent
```

Then choose **Custom → My Video** in System Settings → Wallpaper, or set its
ID through Sunpaper.

`AerialManifestForceLocal` also stops the 12-hour catalog check, so Apple's
catalog is frozen until you merge its updates into the copy. One malformed
entry can fail the whole catalog.

To restore, first select a stock aerial so the agent never points at a missing
asset, then:

```sh
defaults delete com.apple.wallpaper.aerial AerialManifestLocalPathOverride
defaults delete com.apple.wallpaper.aerial AerialManifestForceLocal
trash "$C" "$A/aerials/videos/$U.mov" "$A/aerials/thumbnails/$U.png" "$A/aerials/thumbnails/$SUB.png"
killall WallpaperAerialsExtension WallpaperAgent
```

Editing `aerials/manifest/entries.json` in place also works, but the next
catalog Apple publishes replaces it.

### What to check

1. Lock (Control-Command-Q) and the video should play; unlock and it should
   slow to a still. Repeat ten times: it must play on every lock (the
   `noTemporalInfo` check), and a mis-encoded file is reported to crash the
   extension after repeated locks, leaving a black screen.
2. Read the log:
   ```sh
   /usr/bin/log show --last 15m --style compact --predicate 'process == "WallpaperAerialsExtension" AND (eventMessage CONTAINS "noTemporalInfo" OR eventMessage CONTAINS "Action" OR eventMessage CONTAINS "Re-download" OR messageType == error)'
   ```
3. Route B only: after a reboot and a few days unselected, the entry is still
   listed and `videos/$U.mov` still exists.

## 4. Playing on the desktop

### What Apple's engine does

| Event | WallpaperAgent | WallpaperAerialsExtension |
| --- | --- | --- |
| Screen saver starts | `Presentation mode did change: 'default' -> 'idle'` | `Play Action: Switch to .rampingUp` |
| Lock | `'idle' -> 'locked'` | `Play Without Ramp Action: Switch to .playing` |
| Unlock | `'locked' -> 'default'` | `Pause Action: Switch to .beginRampingDown`, on each display's player |

Those lines are from this Mac on 2026-10-02 (*verified*). The desktop is the
`default` presentation mode, and there the aerials extension always ramps
down to a still layer. Nothing switches that off (*verified*):

- WallpaperAgent registers only debug preferences, such as
  `EnableDebugOverlayForPresentationMode`.
- The extension reads only the manifest keys above and shuffle and variant
  options. `EncodedOptionValues` in `Index.plist` is empty.
- `WallpaperExtensionKit` checks debug marker files such as
  `/var/tmp/.AerialsEnable60fps`. What they do is *unknown*; they look like
  internal debugging aids and aren't something to ship.

### Options

| Option | Real wallpaper? | Plays on the desktop | Lock screen | Main risk | Effort |
| --- | --- | --- | --- | --- | --- |
| Our own `com.apple.wallpaper` extension, like Aerial 4.1 and Phosphene | Yes | Yes | Yes | Loads the private `WallpaperExtensionKit`; Developer ID only; can break in any release | High |
| Desktop-level video window, like Plash | No | Yes | No | None beyond power use | Low to medium |
| Hybrid: catalog entry (route B) plus the window, like Backdrop 2 and Wallper | Yes on the lock screen | Yes | Yes | The catalog half relies on undocumented defaults | Medium |

An extension decides for itself what to do in `default` mode, which is how
Phosphene keeps playing (*reported*). The extension point declares a private
entitlement that Apple's own aerials extension doesn't carry and that
reportedly isn't enforced on 27.0.

### Recommendation

Issue #2 asks for a real wallpaper rather than an overlay window, so only the
extension meets it fully. Work toward it in steps, each useful on its own:

1. **Spike route B.** Low effort and reversible. It proves the encode on 27.2
   and gives a real custom wallpaper that plays on the lock screen and rests
   on a still on the desktop. Sunpaper can schedule it by ID like any aerial.
2. **Spike a wallpaper extension**, using Phosphene as the reference. This is
   the only real wallpaper that keeps playing on the desktop. Check Developer
   ID signing first, since it decides whether the route is shippable.
3. **Fall back to the hybrid** if the extension proves too fragile: the
   route B entry for the lock screen plus a desktop-level window. Desktop
   playback then stays on public API, and if Apple drops the override keys the
   window still plays.

### Desktop window design notes (hybrid fallback)

- One borderless, click-through, non-activating window per display at
  `kCGDesktopWindowLevel`, showing an `AVPlayerLayer` that loops with
  `AVPlayerLooper`. It should join all Spaces and stay put in Mission Control
  (*inferred*).
- Pause when the window is occluded, a full-screen app covers it, the display
  sleeps, the screen locks, or Low Power Mode or thermal pressure is on.
  Vendors claim about 1–3% extra power (*reported*).
- The real wallpaper still sits underneath, so menu bar tinting and Mission
  Control show it (*inferred*). Set it to the matching aerial, or a still from
  the video.
- Smoothing covers use the same window level. They must stay above the video
  window during a change.
- The window plays any H.264 or HEVC file. Only the catalog copy needs the
  special encode.

### Sunpaper changes for a catalog entry (route B)

- `AerialCatalog` reads `aerials/manifest/entries.json` directly. It must
  follow `AerialManifestLocalPathOverride` when that is set.
- `AerialAsset` requires `accessibilityLabel`, `categories`, `showInTopLevel`
  and `includeInShuffle`; one entry without them fails the whole decode.
  `add-catalog-entry.py` writes all four.
- `downloadAerial` skips files that already exist. `redownloadAerial` rejects
  a non-HTTP response before touching the file, so a `file://` entry keeps its
  copy.
- Custom imports accept still images only today, so videos need a new import
  path.

## 5. Persistence risks

| Risk | Affects |
| --- | --- |
| Apple publishes a new catalog, replacing `manifest/entries.json` | In-place catalog edits |
| Apple changes an asset's URL, so the in-use video is re-downloaded | Route A |
| Unselected videos are marked purgeable, and CacheDelete removes them under disk pressure (*verified* for Apple's videos; custom files *unknown*). Re-downloading a `file://` URL probably fails | Routes A and B |
| A macOS update replaces the bundled catalog and may restore Apple's videos (*reported*) | Routes A and B |
| The override keys are undocumented and may disappear | Route B |
| `Index.plist` migration resets unknown asset IDs ("Resetting aerial ID to default during migration"; when it triggers is *unknown*) | Route B |
| Private framework or entitlement changes | Own extension |

## 6. Open questions

1. Does 27.2's engine accept our encode (60 fps, 3 layers, `hvcC` reporting
   one layer)? It is reported only for macOS 26.
2. Are `file://` URLs fine for `previewImage` and `url-4K-SDR-240FPS`, and
   what happens when the extension tries to re-download one?
3. Are custom videos purged when unselected?
4. Is URL-change revalidation keyed on the `SourceURL` attribute?
5. Will the override keys survive 27.x updates and macOS 28?
6. Does an HDR clip work? Tahoe ships HDR aerials, but this Mac's are SDR.
7. For our own extension: does Developer ID signing launch, and how much of
   Phosphene's XPC shim would we need?

## Sources

- [wallpaper-aerials-sync](https://github.com/poornack/wallpaper-aerials-sync): file swap, temporal-layer encoding, the `noTemporalInfo` symptom (macOS 26)
- [AerialDrop](https://github.com/YapWH1208/AerialDrop): catalog import, 30 fps two-layer encode (macOS 26)
- [DynamicWallpaperSwitcher](https://github.com/h27539/DynamicWallpaperSwitcher): x265 layers muxed by AVAssetWriter
- [LivePaper](https://github.com/Raunik2/LivePaper): catalog entries with `file://` URLs, overlay window
- [pdfux gist](https://gist.github.com/pdfux/5659724021e584313c00b843312e909d): the override keys (27.0 to 27.2 beta 2)
- [theothernt gist](https://gist.github.com/theothernt/57a51cade0c12c407f48a5121e0939d5): feed URLs for macOS 14 to 27
- [StarTorch PR #64](https://github.com/misaki1301/Startorch-Wallpaper-Engine/pull/64): `com.apple.wallpaper` extension reverse engineering
- [Phosphene](https://github.com/kageroumado/phosphene) and [Aerial release notes](https://aerialscreensaver.github.io/release-notes/): third-party wallpaper extensions
- [Backdrop lock screen support](https://cindori.com/support/backdrop/general/enable-lock-screen-support) and [Wallper](https://www.wallper.app/support/lockscreen): hybrids
- [Backdrop developer on HN](https://news.ycombinator.com/item?id=45247396): naive swaps crash the extension; updates reset them
- [9to5Mac on macOS 27](https://9to5mac.com/2026/08/17/macos-27-golden-gate-beta-6-adds-fifth-dynamic-wallpaper-get-them-all-here-gallery/): unlock behaviour
