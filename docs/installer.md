# The `install.sh` wizard

`install.sh` is the single entry point for setting up ENCORE. Run with no
options in a terminal it detects your system and walks you through every choice;
with flags it can be fully unattended. It is defensive `bash`
(`set -Eeuo pipefail`) with heavy input validation.

> Do **not** run it with `sudo`. It refuses to run as root and asks for `sudo`
> only when installing system packages, showing the exact command first.

## Invocation

```sh
./install.sh [options] [ABLETON_LIVE_FOLDER]
```

Interactive mode is selected automatically when stdin and stdout are TTYs;
`--non-interactive` forces unattended behaviour. A typical unattended run
(prebuilt runtime, importing a Live folder):

```sh
./install.sh --non-interactive --yes --install-deps \
  --live-dir "/path/to/Live 12 Suite" --scale 200 --no-launch
```

## What you supply for Ableton

For a new prefix, pass the **complete installed Live application folder** copied
from a licensed Windows installation — the outer `Live <ver> <edition>/`
directory, which must contain `Program/`, `Resources/`, `Redist/`, and `Legal/`.
Supported: **Live 11 and 12**, editions **Suite, Standard, Intro, Lite, Trial**.

`validate_live_source` rejects anything that isn't a genuine installed copy:
a downloaded installer, a `.exe`/`.msi`, an archive, a lone `.exe`, or only the
inner `Program/` folder. It also requires the folder's name and its
`Program/Ableton Live <ver> <edition>.exe` to match, `Installation.cfg`'s
`variant` to match the edition, the edition icon under `Resources/Icons`, a
Visual C++ redistributable under `Redist/`, and — for Live 12 — a WebView2 setup
under `Redist/`.

## Stage pipeline

`main()` runs these in order. Everything before `start_mutating_run` only
inspects the system; nothing is written until the plan is shown and (interactively)
confirmed.

1. **Banner + system check** — OS, desktop, session, arch; rejects
   non-Linux/non-x86-64, refuses root, warns on non-GNOME / non-Wayland.
2. **Normalize configuration** — resolve/validate prefix, Wine, Ableton, and
   `--live-dir` paths; reject control characters; require the Ableton executable
   to resolve inside the prefix.
3. **Prepare choices** — prefix-safety, existing-Live detection, Wine source
   (prebuilt/build/reuse), job count, DPI/scale, dependency inspection.
4. **Show plan** — prints everything that will happen; exits here on `--dry-run`.
5. **Start mutating run** — take the `flock`, open the timestamped log.
6. **Install system packages** (if approved) → re-verify dependencies.
7. **Obtain Wine** — one of:
   - `build` (default): **Build ENCORE Wine from source** (`build-wine.sh`) → `build/wine64/`.
   - `download` (`--prebuilt`): **Download verified ENCORE Wine runtime**
     (`download-wine-runtime.sh`) → `runtime/wine/`, then verify.
   - reuse an existing `--wine`/default runtime.
8. *(stops here for `--build-only` / `--configure-only`)*
9. **Register the ENCORE prefix** (`mark_prefix`).
10. **Import Ableton Live files** (`import_live_files`) if `--live-dir` given —
    else reuse Live already in the prefix.
11. **Initialize the Wine prefix** (`wineboot -u`, retried once).
12. **Install the Visual C++ runtime** — runs the VC++ redist from your Live
    folder's `Redist/`.
13. **Install the WebView2 Runtime** *(Live 12 only)* — runs the WebView2 setup;
    needs internet; waits for the EdgeWebView runtime to appear.
14. **Configure the prefix** (`configure-prefix.sh`) — host drives + native
    folder picking, the Push 2 display-bridge DllOverride, and WineASIO
    registration (when built). Its display-scale DPI policy runs as `preserve`
    here because the next stage owns DPI.
15. **Apply display scaling** (`set-dpi.sh`) — writes `LogPixels` **and** keeps
    the Live executable's `dpiAwareness` matched-set in step (set above 96 DPI,
    removed at 96).
16. **Install the Learn View font fallback** *(Live 12 only)* (`install-webview-font.sh`).
17. **Save launcher paths** (`save_runtime_config`) → `.encore/runtime.conf`.
18. **Install the application-menu entry** (`install-desktop.sh`) unless `--no-desktop`.
19. **Verify** → complete → optional launch → optional GitHub-star prompt.

Each stage runs through `run_logged`, which tees output to the log and, on
failure, `die`s with the stage name, log path, and a `%q`-quoted retry command.

## Flag reference

Mirrors `./install.sh --help`.

### Setup

| Flag | Effect |
| --- | --- |
| `--live-dir DIR` | Complete Windows-installed Live 11 or 12 folder (may also be a positional argument). |
| `--prefix DIR` | Wine prefix (default `./ableton-prefix`). |
| `--ableton FILE` | Existing Ableton executable inside the prefix; must resolve within `--prefix`. |
| `--adopt-prefix` | Allow use of a non-empty, unrecognised prefix. |
| `--replace-live` | Replace Live already in the prefix using `--live-dir`. |
| `--dpi N` | Wine DPI, 72–384. Mutually exclusive with `--scale`. |
| `--scale PERCENT` | 100, 125, 150, 175, 200, or 250. |
| `--jobs N` | Parallel jobs for the source build (1–64). |
| `--wine FILE` | Reuse an existing ENCORE Wine runtime; implies no build. |
| `--prebuilt` | Download the verified prebuilt runtime instead of building. |
| `--build-from-source` | Compile the patched Wine tree locally (**default**). |
| `--no-build` | Require an existing `--wine`/default runtime. |
| `--build-only` | Build Wine, then stop before Ableton setup. |
| `--configure-only` | Configure Wine, then stop (advanced diagnostics). |

### Dependencies and automation

| Flag | Effect |
| --- | --- |
| `--install-deps` / `--no-install-deps` | Install / never install missing distro packages. |
| `--non-interactive` | Never prompt; fail when a required choice is missing. |
| `--yes` | Accept recommended/default confirmations. |
| `--dry-run` | Detect and print the plan without writing or downloading. |
| `--no-desktop` | Do not install the application-menu entry. |
| `--launch` / `--no-launch` | Launch / do not launch Ableton after setup. |
| `--no-color` | Disable coloured output (also honours `NO_COLOR`). |
| `-h`, `--help` | Show help. |

## Display scaling

The wizard recommends a DPI from the current desktop/monitor; you always choose.

| Desktop scale | Wine DPI |
| --- | ---: |
| 100% | 96 |
| 125% | 120 |
| 150% | 144 |
| 175% | 168 |
| 200% | 192 |
| 250% | 240 |

Change it later with `./install.sh --no-build --dpi N`. The scaling stage also
maintains per-monitor awareness: above 96 DPI the Live executable's Image File
Execution Options carry `dpiAwareness=2` (Live reads the monitor DPI from the X
server), removed again at 96 — see the windowing feature pages for why the
matched-set matters. Standalone `configure-prefix.sh` runs can instead
auto-detect and apply a calibrated block via `ENCORE_DPI_MODE`
(see [environment.md](environment.md)).

## Safety and resume model

- **Serialised** — an `flock` on `.tmp/install.lock` prevents concurrent runs.
- **Never destructive** — never deletes a dirty Wine checkout, an unrelated
  prefix, or completed downloads.
- **Transactional Live import** — `import_live_files` stages a validated copy,
  backs up any existing Live (with `--replace-live`), publishes, then
  re-validates; on any failure it restores the previous folder.
- **Prefix adoption** — refuses a non-empty prefix lacking an `.encore-prefix`
  marker or a recognised Live executable, unless `--adopt-prefix`.
- **Idempotent stages** — a valid prebuilt runtime (its `.encore-runtime`
  manifest) or a completed source build (`build/wine64/.encore-build` stamp) is
  reused; the VC++ and WebView2 installs are skipped when already present
  (`vc_runtime_ready`, `webview2_ready`).
- **Live must be closed** — `pause_for_live_to_close` waits (interactive) or
  fails (non-interactive) before any prefix mutation; ENCORE never kills Live.
- **Logs** — every run logs to `logs/install-YYYYmmdd-HHMMSS.log`.

## On-disk state ENCORE writes

| Path | Format | Purpose |
| --- | --- | --- |
| `runtime/wine/` | prebuilt tree + `.encore-runtime` manifest (`ENCORE_WINE_RUNTIME_V1`) | the downloaded (`--prebuilt`) Wine runtime |
| `build/wine64/.encore-build` | `wine_revision=…`, `patch_sha256=…` | source-build completion stamp |
| `ableton-prefix/.encore-prefix` | `ENCORE_PREFIX_V1` | marks a prefix as ENCORE-owned |
| `.encore/runtime.conf` | 4 lines: `ENCORE_RUNTIME_V1`, prefix, wine, ableton (0600) | launcher path memory; repo-relative paths stored relative |
| `logs/` | text | per-run install and launch logs |
| `.tmp/install.lock` | PID | run serialisation |

`.encore/runtime.conf` is parsed by `scripts/load-runtime-config.sh` **without
`eval`**; environment variables and command-line options override the saved
values.

## Requirements verification

The final `verify_installation` hard-checks that Wine is executable, the
imported Live executable exists, the runtime config is well-formed, and (unless
`--no-desktop`) the desktop entry exists and passes `desktop-file-validate`.
A failure here names the missing artifact.
