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
- [scripts.md](scripts.md) — reference for all 19 helper scripts.
- [building.md](building.md) — the default source build (mingw + ntsync + reproducible), the opt-in prebuilt runtime, and release packaging.
- [environment.md](environment.md) — every `ENCORE_*` and `WINE_*` variable: consumer, default, effect, precedence.
- [troubleshooting.md](troubleshooting.md) — known limitations and symptom → cause → fix tables.
- [glossary.md](glossary.md) — Wine/X11/portal/DAW terminology.

### The Wine patch

- [patches/README.md](patches/README.md) — canonical build facts, diffstat, PE/Unix split, feature index.
- [patches/portal-file-picker.md](patches/portal-file-picker.md) — native xdg-desktop-portal file chooser (comdlg32).
- [patches/cpu-and-threads.md](patches/cpu-and-threads.md) — `WINE_CPU_TOPOLOGY` override and stale-thread recovery.
- [patches/windowing-and-hidpi.md](patches/windowing-and-hidpi.md) — VST3 windows and the HiDPI config-rounding state machine.
- [patches/drag-and-drop.md](patches/drag-and-drop.md) — host-file drag-and-drop with DPI-correct routing.
- [patches/menu-theming.md](patches/menu-theming.md) — dynamic Ableton menu-bar theming.
- [patches/runtime-fixes.md](patches/runtime-fixes.md) — DXGI `WaitForVBlank`, msvcp `basic_istream`, mount-reparse.

## Conventions

- Code references use `path:function()` form (line numbers drift on rebase).
- Canonical patch facts (pinned revision, diffstat) live once in
  [patches/README.md](patches/README.md); other pages link rather than repeat.
- Each patch feature page follows the same skeleton: Problem → What the patch
  does → Key files → Runtime toggles → Caveats → How to verify.
- These docs describe ENCORE at release **v0.1.1** with the **r1** Wine runtime.
  The `patches/*` pages describe the pinned Wine patch (unchanged since it was
  written); re-verify project-level pages after upstream moves.
