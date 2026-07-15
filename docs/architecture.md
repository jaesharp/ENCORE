# Architecture

## What ENCORE is

ENCORE is a **guided Wine compatibility setup for running Ableton Live 11 and 12
on Linux**. It **builds the patched Wine from source by default** (a verified
prebuilt runtime is available with `--prebuilt`), configures a Wine prefix for
Live, and imports a
copy of your own already-installed Live application folder. It supplies the hard
compatibility work — native file dialogs, HiDPI, VST3 hosting, audio,
drag-and-drop, themed menus, and (Live 12) the Learn View — from one command.

The intellectual core is one file: `patches/encore-wine.patch`
(see [patches/README.md](patches/README.md)). Everything else builds, downloads,
verifies, or configures a Wine that carries that patch.

## Two things you supply, two things ENCORE supplies

- **You supply:** a supported Linux system, and the **complete installed Live 11
  or 12 application folder** copied from a licensed Windows installation
  (Suite, Standard, Intro, Lite, or Trial). ENCORE never downloads, bundles, or
  runs the Ableton installer.
- **ENCORE supplies:** the patched Wine runtime (built from source by default), a
  configured prefix, the Microsoft prerequisites bundled inside your Live folder
  (Visual C++ runtime; for Live 12 also the WebView2 runtime), and a launcher +
  desktop entry.

## Component map

```
  you ── run ──▶ install.sh   (guided wizard / stage orchestrator, ~1900 lines)
                     │
                     ▼
   ┌───────────── scripts/ ─────────────────────────────────────────────┐
   │ WINE RUNTIME (pick one)                                             │
   │   build-wine.sh             compile patched Wine   ─▶ build/wine64/ │  (default)
   │   download-wine-runtime.sh  fetch+verify prebuilt  ─▶ runtime/wine/ │  (--prebuilt)
   │                                                                     │
   │ ABLETON                                                             │
   │   ableton-profile.sh   identify Live 11/12 + edition               │
   │   (install.sh import)  copy your installed Live folder ─▶ prefix    │
   │                                                                     │
   │ PREFIX CONFIG                                                       │
   │   configure-prefix.sh  portal picker + host drives                 │
   │   set-dpi.sh           Wine DPI                     ─▶ ableton-prefix/
   │   install-webview-font.sh  Learn View Arial (Live 12)              │
   │   install-desktop.sh   application-menu entry                      │
   └─────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
              .encore/runtime.conf  (remembers prefix / wine / ableton)
                     │
                     ▼
   launch-ableton.sh ─▶ run-ableton.sh ─▶ ENCORE Wine + prefix ─▶ Ableton Live
                        (exports runtime env: WebView2 flags, DLL overrides,
                         CPU topology, ENCORE_* toggles)
```

## Two phases: set up, then run

**Setup** (`install.sh`, detailed in [installer.md](installer.md)) —
system check → normalize config → prepare choices → plan → install packages →
**obtain Wine** (build from source *or* download prebuilt) → register prefix →
**import your Live folder** → initialize prefix (`wineboot`) → install the
Visual C++ runtime → install WebView2 (Live 12) → enable host files + portal →
set DPI → install Learn View font (Live 12) → save launcher paths → desktop
entry → verify.

**Run** (`scripts/launch-ableton.sh` → `run-ableton.sh`) — read the saved paths,
resolve the Live executable for the installed edition, export the runtime
environment (see [environment.md](environment.md)), and `exec` ENCORE Wine on it.

## The prebuilt runtime and its verification

With `--prebuilt`, ENCORE downloads a pinned runtime archive
(`encore-wine-11.13-r1-x86_64-linux-gnu.tar.xz`) from the ENCORE GitHub release
and installs it to `runtime/wine/`. `download-wine-runtime.sh` verifies it
rigorously before activating it:

- host is x86-64 with **glibc ≥ 2.35**;
- the archive matches a pinned **SHA-256** and contains only safe paths;
- the extracted tree has the expected `bin/`, `lib/wine/x86_64-unix/*.so`, and
  `lib/wine/{x86_64,i386}-windows/*.dll` layout (WoW64: both PE arches, no
  `i386-unix`);
- a `.encore-runtime` manifest (`ENCORE_WINE_RUNTIME_V1`) records the ENCORE
  runtime version, `wine_version=11.13`, the pinned `wine_revision`, the
  **patch SHA-256**, `arch=x86_64`, `pe_archs=i386,x86_64`, and a `glibc_max`;
- `wine --version` reports `wine-11.13`.

Extraction is atomic (staged in a temp dir, validated, then moved into place),
and a valid existing runtime is reused. This prebuilt path is opt-in with
`--prebuilt`; the default is [building from source](building.md), which is also
the route when the host glibc is too old for the runtime.

## Importing Ableton Live (copy, not install)

ENCORE takes a **complete installed Live folder** — the outer
`Live <ver> <edition>/` directory containing `Program/`, `Resources/`, `Redist/`,
and `Legal/`. `validate_live_source` (in `install.sh`) enforces that it is a
genuine installed copy (not an installer, `.exe`, archive, or lone `Program/`):
it checks the required files (`Ableton Live Engine.dll`, `Installation.cfg`
whose `variant` matches the edition, `Resources/GUI.alp` + `Graphics.alp`, a
non-empty `Legal/` license, the edition icon, a VC++ redist under `Redist/`,
and — for Live 12 — a WebView2 setup), and rejects symlinks/special files.
`import_live_files` copies it into `drive_c/ProgramData/Ableton/` inside the
prefix **transactionally** (`cp -a --reflink=auto` into staging → validate →
back up any existing copy → publish → re-validate → drop the backup), so a
failure never leaves a half-imported or destroyed Live folder.

## Prefix ownership and safety

- A prefix ENCORE owns is tagged `ableton-prefix/.encore-prefix`
  (`ENCORE_PREFIX_V1`).
- ENCORE refuses a non-empty prefix it doesn't recognise unless `--adopt-prefix`.
- It never deletes a dirty Wine checkout, an unrelated prefix, or downloads;
  Live import and font/runtime installs are transactional with rollback.
- Runs are serialised with an `flock` lock and root is refused.

See [installer.md](installer.md) for the full safety and resume model.

## Licensing posture

- ENCORE redistributes **no** Ableton software; you supply your own installed
  Live folder, and ENCORE runs only the Microsoft prerequisites bundled inside
  it (Visual C++; for Live 12, WebView2).
- The Wine patch is a source delta under the applicable upstream Wine file
  licenses (the prebuilt runtime is built from exactly that pinned source; the
  matching source archive is published alongside each release).
- The Learn View font fallback is generated locally from your installed
  Liberation Sans (see [scripts.md](scripts.md)); no font binary is shipped.

## Where to go next

- Advanced users: [installer.md](installer.md) → [environment.md](environment.md)
  → [troubleshooting.md](troubleshooting.md).
- Building the runtime yourself: [building.md](building.md).
- Contributors on the patch: [patches/README.md](patches/README.md) and the six
  feature pages.
- Terminology: [glossary.md](glossary.md).
