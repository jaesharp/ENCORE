# The Wine runtime: prebuilt and from source

On this fork, `install.sh` **builds the patched Wine from source by default**;
the **verified prebuilt runtime** is opt-in with `--prebuilt`. (Upstream ENCORE
defaults the other way — prebuilt unless you pass `--build-from-source`.) This
page covers both paths and how the release runtime is produced.

## The prebuilt runtime (opt-in with `--prebuilt`)

`install.sh --prebuilt` runs `scripts/download-wine-runtime.sh`,
which downloads `encore-wine-11.13-r1-x86_64-linux-gnu.tar.xz` from the ENCORE
GitHub release and installs it to `runtime/wine/`. Requirements:

- x86-64 Linux with **glibc ≥ 2.35** (`prebuilt_host_ready` checks this; on an
  older glibc, use `--build-from-source`);
- ~3.5 GiB free (plus your Live folder);
- network access for the one-time download.

It is verified before activation: pinned **SHA-256**, safe archive paths, the
expected `bin/` + `lib/wine/{x86_64-unix,*-windows}` layout, a
`.encore-runtime` manifest (`ENCORE_WINE_RUNTIME_V1` — records ENCORE runtime
version, `wine_version=11.13`, `wine_revision`, patch SHA-256, `arch=x86_64`,
`pe_archs=i386,x86_64`, `glibc_max`), and `wine --version == wine-11.13`.
Extraction is atomic; a valid existing `runtime/wine/` is reused.

## Building from source (the default)

A plain `./install.sh` builds from source; `--build-from-source` selects it
explicitly and `--build-only` stops after the build. `scripts/build-wine.sh`
clones + patches Wine
(see [patches/README.md](patches/README.md)) and compiles it into `build/wine64/`.

### Requirements

- x86-64 Linux, ~15–25 GiB free, substantial CPU/time.
- The **mingw-w64 cross toolchain for both i686 and x86_64** — gcc **and** g++.
  `build-wine.sh` hard-requires `i686-w64-mingw32-gcc`/`-g++` and
  `x86_64-w64-mingw32-gcc`/`-g++`; `install-dependencies.sh` installs them per
  distro (apt `gcc/g++-mingw-w64-{i686,x86-64}`, dnf `mingw{32,64}-gcc[-c++]`,
  pacman `mingw-w64-gcc`).
- The usual dev headers (X11, DBus/PulseAudio/GStreamer/GLib, Fontconfig,
  Vulkan, GnuTLS, udev, ALSA). System `pkg-config` is preferred; an Ubuntu-only
  local-sysroot fallback (`prepare-deps.sh`) stages headers when they can't be
  installed system-wide.

### Configure and verify

Configured with `--enable-archs=i386,x86_64 --with-dbus --with-gstreamer
--with-pulse --prefix=/opt/encore-wine`, plus **reproducible-build flags**
(`SOURCE_DATE_EPOCH`, `-ffile-prefix-map`/`-fdebug-prefix-map`/`-fmacro-prefix-map`)
and **ntsync** headers (`-I packaging/uapi`). `build-wine.sh` refuses to declare
success unless all hold, so "build complete" is meaningful:

- reproducible path-map flags are present for both `i386` and `x86_64` PE objects;
- `HOST_ARCH = x86_64` and `PE_ARCHS = i386 x86_64` (WoW64);
- `winegstreamer` wasn't disabled and GStreamer linked;
- every required `SONAME_*` plus `HAVE_UDEV` **and `HAVE_LINUX_NTSYNC_H`** is in
  `config.h`;
- `wine --version == wine-11.13`, `wineserver` exists, and the full WoW64
  artifact set is present — the Unix halves (`winex11`, `winegstreamer`,
  `winepulse`, `winevulkan`, `comdlg32`) plus PE DLLs for **both** arches
  (`{x86_64,i386}-windows/dxgi.dll`, `ntdll`, `wow64*.dll`, `kernel32`,
  `cmd.exe`, `wineboot.exe`).

It then writes `build/wine64/.encore-build` (`wine_revision`, `patch_sha256`).
To force a rebuild, remove that stamp.

> The prebuilt runtime is built from **exactly this pinned source and patch**;
> `build-from-source` reproduces it. That is why the release publishes a matching
> `encore-wine-11.13-r1-source.tar.xz` alongside the runtime.

## Producing a release runtime

`scripts/package-wine-release.sh [version] [out-dir]` turns a completed build
into the release archives (into `dist/` by default): the compact runtime
(`encore-wine-11.13-r1-x86_64-linux-gnu.tar.xz`), the corresponding source
(`encore-wine-11.13-r1-source.tar.xz`), and — assembled into the turnkey bundle
`ENCORE-v0.1.1-linux-x86_64.tar.xz` with a `SHA256SUMS`. The GitHub Actions
workflow `.github/workflows/build-runtime.yml` ("Build portable Wine runtime",
`workflow_dispatch`) runs this in CI. Release/runtime versions and the pinned
runtime SHA-256 live in `scripts/common.sh`.

## Per-distro dependencies

`install-dependencies.sh` selects the family automatically (override with
`ENCORE_PACKAGE_FAMILY`) and picks the right `xdg-desktop-portal` backend. The
**runtime** profile (used with a prebuilt runtime) covers fontconfig, Liberation
Sans, Python fontTools, desktop-file-utils, Xwayland, the portal backend, and
the GStreamer plugin sets. The **build** profile adds the compiler toolchain,
the mingw-w64 cross compilers, and all dev headers. Preview the exact command
with `scripts/install-dependencies.sh --print build` (or `runtime`), or check
what's missing with `--check` (it verifies capabilities, not just package
names).

## Manual / diagnostic builds

```sh
./install.sh --build-only --build-from-source --install-deps --jobs 8
./install.sh --configure-only --build-from-source   # stop after configure
```
