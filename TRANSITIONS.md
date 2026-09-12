# Smooth wallpaper handoff

This implementation is a visual workaround, not Apple’s entitlement-protected native aerial setter. **Integrated SIP-enabled acceptance testing remains outstanding.**

Sunpaper snapshots only WindowManager's wallpaper window on each connected display using ScreenCaptureKit. Click-through, nonactivating desktop-level windows hold the old pictures while the existing Index.plist/restart operation runs. Incoming pictures crossfade *inside opaque windows*, which are then removed. With macOS Reduce Motion enabled, the picture swaps without animation after the same readiness checks. Fading the windows themselves produced a black dip in the research prototype and is intentionally not used.

## Operation

- Scheduled changes and confirmed manual choices await completion. Browsing in the picker is in-app only. A shared gate serializes aerial changes across all displays. Superseded requests cannot publish stale scheduler state; a cancelled in-flight mutation must recover before the next change begins.
- Captures stay in memory; no app-window images, cursor, audio, or recording files are captured by the product.
- Smoothing is on by default and requires normal screen capture access. Settings → Smooth changes has an explicit request button and a collapsible explanation of the private native entitlement. With smoothing on, missing permission stops before any wallpaper mutation; background scheduling never prompts or silently falls back.
- Users can explicitly turn smoothing off. Aerial changes then use the same serialized plist/reload transaction without capture, overlays or visual-readiness polling, so a gray flash may be visible. Video readability is still checked before mutation, and write failures/cancellation still restore the saved plist. A failed uncovered restoration does not claim a cover is visible. An existing retained recovery cover must be resolved before either mode can proceed.
- Readiness compares spatial RGB signatures against representative frames decoded from the requested aerial's first minute, aspect-filled for each display. A constrained exposure adjustment handles macOS's dimmed secondary wallpaper. There are no asset IDs or scene-color rules in the matcher.
- Sampling starts with the reload. Every display must depart from its original appearance, then match its expected scene for three consecutive samples. The scene is checked again after blending before the covers are removed. A still-visible old image is not sufficient evidence of a reload.
- A failed change restores the exact pre-change Index.plist under cover and verifies its previous appearance. Failed restoration retains the cover and exposes an explicit retry action; it does not leave a permanent polling loop running. Quit waits for pending work and asks before discarding a retained recovery cover.
- Static images still use NSWorkspace and are rejected while an aerial transition/recovery owns the desktop. Provider writes are required so a failed provider change cannot count as a successful aerial update.

## Verification and limits

The earlier isolated prototype measured zero suspect gray/black frames across 7,485 target-only composited frames and eight visible A/B switches on two displays. That was a SIP-disabled boot, a two-scene classifier, and the prototype—not a live acceptance test of this implementation.

The Release build and all **182 unit tests** pass. Local installation and launch are not a live handoff acceptance test.

The production matcher was checked offline against 28 saved native frames from both displays: all matched their expected scene, and none matched the other test scene. Golden Gate references were decoded from its local video; Tahoe used the saved video reference because its video was no longer in the local cache. Four representative native/reference signature pairs are retained as unit-test fixtures. Tests also cover cancellation, serialization, recovery errors, delayed downloads, stale scheduler errors, and validation without touching the real wallpaper.

The polling budget is 25 seconds per reload/restoration. Readiness is conservative image matching, not a native renderer-ready signal. Flat-color backgrounds, a scene outside the sampled video interval, unusual scaling, or a changed display layout may be inconclusive and cause recovery. ScreenCaptureKit or AVFoundation calls themselves are OS asynchronous operations, not a hard real-time deadline.

Still required before claiming the user's SIP-on no-flash goal is solved: smoothing enabled with normal capture permission, actual SIP-on transitions, visual handoff evaluation, and Spaces/full-screen/lock/wake/display-reconfiguration testing. No private entitlement, injection, TCC modification, or SIP change is part of this implementation.


The repository includes wallpaper-only signature fixtures and automated tests. Machine-specific instrumentation, raw recordings, original desktop configurations and signing material are not included.
