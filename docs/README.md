# ENCORE documentation

ENCORE is a guided Wine compatibility setup for running Ableton Live 11 and 12
on Linux. It **builds the patched Wine from source by default** (a verified
prebuilt runtime is available with `--prebuilt`), configures a Wine prefix, and
imports your own installed Live
application folder. This folder is the deep documentation; the top-level
[README](../README.md) is the quick start.

## Where to start

| You are… | Read, in order |
| --- | --- |
| Installing or tuning ENCORE | [installer.md](installer.md) → [environment.md](environment.md) → [troubleshooting.md](troubleshooting.md) |
| A contributor getting oriented | [architecture.md](architecture.md) → [patches/README.md](patches/README.md) → the feature page you care about |
| Building or packaging the runtime | [building.md](building.md) → [scripts.md](scripts.md) |

## Contents

- [architecture.md](architecture.md) — what ENCORE is, component map, prebuilt-vs-source runtime, the copy-installed-Live model, licensing.
- [installer.md](installer.md) — the `install.sh` wizard: flags, the stage pipeline, safety/resume, on-disk state.
- [scripts.md](scripts.md) — reference for all 22 helper scripts.
- [building.md](building.md) — the default source build (mingw + ntsync + reproducible), the opt-in prebuilt runtime, and release packaging.
- [wineasio.md](wineasio.md) — opt-in low-latency audio (WineASIO → JACK/PipeWire) and the `jacklinkd` device-recovery helper.
- [environment.md](environment.md) — every `ENCORE_*` and `WINE_*` variable: consumer, default, effect, precedence.
- [troubleshooting.md](troubleshooting.md) — known limitations and symptom → cause → fix tables.
- [glossary.md](glossary.md) — Wine/X11/portal/DAW terminology.

### The Wine patch

- [patches/README.md](patches/README.md) — canonical build facts, diffstat, PE/Unix split, feature index.
- [patches/portal-file-picker.md](patches/portal-file-picker.md) — native xdg-desktop-portal file chooser (comdlg32).
- [patches/cpu-and-threads.md](patches/cpu-and-threads.md) — `WINE_CPU_TOPOLOGY` override and stale-thread recovery.
- [patches/windowing-and-hidpi.md](patches/windowing-and-hidpi.md) — VST3 windows, the HiDPI config-rounding state machine, and the custom-NC decoration gate.
- [patches/windowing-nspa.md](patches/windowing-nspa.md) — reentrant `WM_WINDOWPOSCHANGED` suppression (HiDPI resize loop).
- [patches/drag-and-drop.md](patches/drag-and-drop.md) — host-file drag-and-drop with DPI-correct routing.
- [patches/menu-theming.md](patches/menu-theming.md) — dynamic Ableton menu-bar theming.
- [patches/runtime-fixes.md](patches/runtime-fixes.md) — DXGI `WaitForVBlank`, msvcp `basic_istream`, mount-reparse.
- [patches/audio-endpoint-friendlyname.md](patches/audio-endpoint-friendlyname.md) — audio-endpoint FriendlyName re-wrap crash fix.
- [patches/midi-hotplug.md](patches/midi-hotplug.md) — MIDI controller hotplug re-subscribe.
- [patches/opengl-srgb.md](patches/opengl-srgb.md) — EGL sRGB-capable pixel formats.
- [patches/push2-display.md](patches/push2-display.md) — Push 2 display over host USB (libusb bridge).
- [patches/shared-session-coherence.md](patches/shared-session-coherence.md) — shared-session view coherence.
- [patches/activation-timestamps.md](patches/activation-timestamps.md) — real `_NET_ACTIVE_WINDOW` timestamps.
- [patches/layered-attr-sync.md](patches/layered-attr-sync.md) — layered-attribute sync (black popup shadows).
- [patches/gl-editor-visual.md](patches/gl-editor-visual.md) — real drawable visual in `set_dc_drawable`.
- [patches/present-dpi-context.md](patches/present-dpi-context.md) — present/resize rects in the window's DPI context.

## Conventions

- Code references use `path:function()` form (line numbers drift on rebase).
- Canonical patch facts (pinned revision, diffstat) live once in
  [patches/README.md](patches/README.md); other pages link rather than repeat.
- Each patch feature page follows the same skeleton: Problem → What the patch
  does → Key files → Runtime toggles → Caveats → How to verify.
- These docs describe the current `dev` tree. The **r1** prebuilt runtime
  (release **v0.1.1**) predates patches `31` and `70`–`150` and the patch-`30`
  custom-NC gate — a **source build** (the default) includes them; the prebuilt
  runtime gains them only when a new runtime is published. Re-verify
  project-level pages after upstream moves.
