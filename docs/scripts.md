# The `scripts/` directory

`install.sh` orchestrates; focused scripts under `scripts/` do the work. Shell
scripts run under `set -eu` (the larger ones use `set -Eeuo pipefail`). Paths
and environment flow through the variables in [environment.md](environment.md).
Live import, the Visual C++ runtime, and the WebView2 runtime are handled by
functions **inside `install.sh`**, not separate scripts.

| Script | Group | Role |
| --- | --- | --- |
| `common.sh` | runtime | Shared helpers + pinned constants (revision, runtime version/asset/SHA, paths). |
| `download-wine-runtime.sh` | runtime | Download, verify, and atomically install the prebuilt runtime. |
| `bootstrap-wine.sh` | runtime | Clone Wine and apply the ENCORE patch idempotently (source builds). |
| `build-wine.sh` | runtime | Configure, compile, and verify ENCORE Wine from source. |
| `prepare-deps.sh` | runtime | Ubuntu/Debian local dev-header sysroot fallback. |
| `package-wine-release.sh` | runtime | Build the runtime + source release archives from a completed build. |
| `install-dependencies.sh` | deps | Distro package detection / check / print / install (runtime & build profiles). |
| `ableton-profile.sh` | ableton | Identify Live 11/12 + edition; resolve the Live executable in a folder or prefix. |
| `configure-prefix.sh` | prefix | Enable host drives and the native folder picker. |
| `set-dpi.sh` | prefix | Write the Wine DPI (`LogPixels`). |
| `install-webview-font.sh` | prefix | Generate + register the Learn View Arial fallback (Live 12). |
| `make-webview-fallback-font.py` | prefix | fontTools tool that builds/verifies the fallback. |
| `install-desktop.sh` | prefix | Render and install the application-menu entry. |
| `launch-ableton.sh` | launcher | Dock/entry launcher; skips if Live already runs. |
| `run-ableton.sh` | launcher | Resolve the Live executable, export runtime env, exec Wine. |
| `select-cpu-topology.sh` | launcher | Compute `WINE_CPU_TOPOLOGY` from the cpuset. |
| `load-runtime-config.sh` | helper | Safely parse `.encore/runtime.conf` (no `eval`). |
| `process-is-running.sh` | helper | True if a given executable path is running. |
| `offer-github-star.sh` | helper | Optional end-of-install GitHub star prompt. |

## Runtime

### `common.sh`
Sourced everywhere. Defines the pinned `WINE_REVISION` and `WINE_SOURCE_DATE_EPOCH`,
the release/runtime versioning (`ENCORE_RELEASE_VERSION`, `ENCORE_RUNTIME_VERSION`,
`ENCORE_RUNTIME_REVISION`), the release asset names, `ENCORE_GLIBC_MIN`, the
pinned `ENCORE_RUNTIME_SHA256`, the release base URL, and paths
(`ENCORE_RUNTIME_ROOT=runtime/wine`, `WINE_INSTALL_PREFIX=/opt/encore-wine`,
`WINE_BUILD`, `ENCORE_PREFIX`, `WINE_PATCH`), plus `say`/`die`/`require_command`.

### `download-wine-runtime.sh`
The `--prebuilt` Wine source. Checks host arch + glibc ≥ `ENCORE_GLIBC_MIN`, downloads
the pinned runtime archive over HTTPS with resume, verifies its SHA-256, rejects
unsafe archive paths, extracts to a temp dir, runs `validate_runtime` (layout +
`.encore-runtime` manifest + `wine --version`), and atomically moves it to
`runtime/wine/`. A valid existing runtime is reused. See [building.md](building.md).

### `bootstrap-wine.sh`
For source builds: ensures `wine/` is a clean checkout at the pinned revision
with the ENCORE patch applied, idempotently (verifies via a throwaway git index
that the tree matches the patch exactly; refuses a tree with other changes).

### `build-wine.sh`
Runs `bootstrap-wine.sh`, requires the mingw-w64 i686+x86_64 gcc/g++ toolchain,
configures with `--enable-archs=i386,x86_64` + reproducible flags + ntsync
headers, builds, then hard-verifies the WoW64 artifact set, `PE_ARCHS`,
`HOST_ARCH`, and required `config.h` defines (incl. `HAVE_LINUX_NTSYNC_H`).
Writes `build/wine64/.encore-build`. See [building.md](building.md).

### `prepare-deps.sh`
Ubuntu/Debian fallback: when DBus/PulseAudio/GStreamer/GLib dev packages can't be
installed system-wide, stages just their headers under `deps/*-sysroot/` via
`apt-get download` + `dpkg-deb -x`.

### `package-wine-release.sh`
Turns a completed build into the release archives (runtime + corresponding
source), used to produce GitHub releases (also driven by the CI workflow).

## Dependencies

### `install-dependencies.sh`
Distro-aware package handling with modes `--check`/`--print`/`--install` and
profiles `runtime` | `build`. Detects apt/dnf/pacman (override
`ENCORE_PACKAGE_FAMILY`), selects the right `xdg-desktop-portal` backend, and —
for the build profile — includes the **mingw-w64 i686+x86_64 cross compilers**.
`--check` verifies capabilities (Python fontTools, Liberation Sans, a FileChooser
portal backend, GStreamer codecs, the cross compilers), not just package names.

## Ableton

### `ableton-profile.sh`
Sourced (no shell-option changes). Maps a Live executable name to its version,
edition, folder, WM class, and icon (`encore_ableton_profile_from_executable`);
validates that a path is a supported `…/Live NN Edition/Program/Ableton Live NN
Edition.exe` (`encore_ableton_path_is_supported`); finds supported executables
under a root; and resolves the single Live executable in a prefix
(`encore_resolve_ableton_executable`). Used by `install.sh` and `run-ableton.sh`
so both agree on which Live (11/12, any edition) a prefix holds.

## Prefix configuration

### `configure-prefix.sh`
Symlinks a free Wine drive letter (e.g. `Z:`) to `/` and sets
`FileDialogPortal=always` under the imported Live executable's AppDefaults
`X11 Driver` key. Refuses to run while Live is open. See
[portal-file-picker.md](patches/portal-file-picker.md).

### `set-dpi.sh`
Validates the DPI (72–384) and writes `HKCU\Control Panel\Desktop` `LogPixels`.

### `install-webview-font.sh` + `make-webview-fallback-font.py`
Live 12 only. The Learn View's Chromium needs a real "Arial" family. The Python
tool (fontTools) rebuilds the user's Liberation Sans as Arial, preserving license
records and embedding the source SHA-256; the shell script installs and registers
it transactionally (temp file, backup, rollback), and is a no-op if already
correct.

### `install-desktop.sh`
Renders `packaging/encore.desktop.in` into
`$XDG_DATA_HOME/applications/encore.desktop` with careful escaping, using the
imported Live edition's name and icon; validates with `desktop-file-validate`.

## Launcher

### `launch-ableton.sh`
The desktop entry point. Exits 0 if Ableton is already running; otherwise execs
`run-ableton.sh`, logging to `logs/ableton-dock.log`.

### `run-ableton.sh`
Loads `runtime.conf`, resolves the Live executable via `ableton-profile.sh`,
picks the Wine binary (`runtime/wine/bin/wine`, falling back to
`build/wine64/wine`), assembles the WebView2 flags and CPU topology, exports the
full runtime environment (see [environment.md](environment.md)), and execs Wine.
`ENCORE_DRY_RUN=1` prints the computed environment and exits.

### `select-cpu-topology.sh`
Computes `WINE_CPU_TOPOLOGY` from the allowed CPU set (`Cpus_allowed_list`):
`8` when more than eight CPUs are allowed; the supported count for sparse/limited
sets; nothing when the default dense set is already ≤ 8. Pairs with
[cpu-and-threads.md](patches/cpu-and-threads.md).

## Helpers

### `load-runtime-config.sh`
Sourced (needs `ROOT`). Reads exactly four lines of `.encore/runtime.conf`,
validates the `ENCORE_RUNTIME_V1` header, resolves repo-relative paths, and sets
`ENCORE_PREFIX`/`ENCORE_WINE`/`ENCORE_ABLETON` only when not already set. Never
`eval`s the file.

### `process-is-running.sh`
Given an executable path, scans `/proc/*/cmdline` and exits 0 if a running
process matches. Used to detect a running Live before mutating the prefix.

### `offer-github-star.sh`
Only for authenticated interactive `gh` users: offers a one-time star of the
repository. Never prompts unauthenticated users; failure never affects install.
