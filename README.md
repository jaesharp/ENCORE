<p align="center">
  <picture>
    <source srcset="assets/branding/encore-logo.svg" type="image/svg+xml">
    <img src="assets/branding/encore-logo.png" alt="ENCORE logo" width="230">
  </picture>
</p>

<h1 align="center">ENCORE</h1>

ENCORE is a guided Wine compatibility setup for running Ableton Live 12 Suite on Linux. It is maintained by `wowitsjack` and focuses on making the difficult parts, including installing a verified patched Wine runtime, configuring HiDPI, native file access, VST3 hosting, audio, drag-and-drop, themed menus, and Learn View, approachable from one command.

> [!WARNING]
> ENCORE is experimental and is not affiliated with Ableton or Wine. Back up important Live Sets and prefixes before testing it.

<p align="center">
  <img src="assets/screenshots/ableton-live-12-session-view.png" alt="Ableton Live 12 Suite running through ENCORE on Linux" width="900">
</p>

<p align="center">
  <img src="assets/screenshots/ableton-live-12-splash.png" alt="Ableton Live 12 Suite splash screen on Linux" width="420">
  <img src="assets/screenshots/ableton-live-12-audio-settings.png" alt="Ableton Live 12 audio settings using PulseAudio through ENCORE" width="380">
</p>

## Features

- Drag files and audio directly from Nautilus and compatible desktop file managers into Live.
- Corrected internal drag-and-drop positioning under Wine and Xwayland.
- Windows VST3 plug-in scanning and hosting, including resizable custom plug-in windows with working mouse input.
- VST3 custom folders anywhere the user selects, including mounted drives, through the native desktop folder picker.
- Audio through Wine's PulseAudio backend on both PulseAudio systems and PipeWire systems using `pipewire-pulse`.
- Guided HiDPI scaling, themed application menus, WebView2 Learn View support, and dynamic CPU topology selection.
- Application-menu integration for GNOME, KDE, and other desktops that support freedesktop desktop entries.

## Quick start

Download the turnkey archive from the [latest release](https://github.com/wowitsjack/ENCORE/releases/latest), extract it, open a terminal in its folder, and run:

```sh
./install.sh
```

The release already contains the compact ENCORE Wine runtime. Cloning the repository also works: the setup script downloads and verifies that same pinned runtime before setup.

The setup script is an interactive wizard. It:

- detects Ubuntu/Debian, Fedora, Arch Linux, and CachyOS package systems;
- checks the desktop, session, CPU, memory, disk space, and existing ENCORE setup;
- finds complete Windows-installed Ableton Live 12 folders or lets you drag one into the terminal;
- explains and recommends display scaling instead of silently forcing a DPI;
- uses the bundled runtime or downloads it with a pinned SHA-256 checksum;
- keeps local Wine compilation as an explicit advanced option;
- shows the exact system package command before asking for sudo;
- resumes safe completed work when rerun after a cancellation or failure;
- installs the application-menu entry and optionally launches Live;
- optionally offers authenticated GitHub CLI users a final chance to star ENCORE; pressing Enter accepts, and unauthenticated users are never prompted.

Do **not** run the whole script with `sudo`. ENCORE asks for sudo only if you approve installation of missing system packages.

The release includes only ENCORE and its patched Wine runtime. Ableton Live, the Wine prefix, plug-ins, user files, and authorization data are never included. Supply the complete Ableton application folder from your own licensed Windows installation, or the same complete folder extracted another way from your licensed copy.

## Supplying Ableton Live

ENCORE does not download, run, or bundle the Ableton installer. To create a new prefix, supply the complete `Live 12 Suite` application folder from an existing Windows installation. On a normal Windows installation, this is `C:\ProgramData\Ableton\Live 12 Suite`. You may instead supply the same complete application folder if you obtained it by extracting your own licensed copy another way.

Select the outer `Live 12 Suite` folder:

```text
Live 12 Suite/
├── Program/
│   ├── Ableton Live 12 Suite.exe
│   └── Ableton Live Engine.dll
├── Resources/
├── Redist/
└── Legal/
```

Do not select the folder containing the downloaded Ableton installer, the installer archive itself, a lone `.exe`, or only the inner `Program` subfolder. Those are not the complete installed application folder and ENCORE rejects them.

ENCORE copies the complete folder into its Wine prefix, validates the copy before activating it, then runs the Visual C++ and WebView2 setup programs retained under `Redist`. The small WebView2 bootstrapper downloads the actual runtime, so a fresh prefix needs an internet connection during this step. ENCORE does not reproduce unrelated Windows shell associations or device-driver registration.

Allow free space for the complete Live folder plus about 3.5 GiB for staging, the Wine prefix, Visual C++, and WebView2. ENCORE measures the selected folder and checks the destination before it starts copying.

## Binary releases

Each release publishes four files:

- `ENCORE-v0.1.0-linux-x86_64.tar.xz`: the recommended turnkey package with ENCORE and Wine ready to use;
- `encore-wine-11.13-r1-x86_64-linux-gnu.tar.xz`: the runtime-only asset used by the setup script;
- `encore-wine-11.13-r1-source.tar.xz`: the complete corresponding patched Wine source and build instructions;
- `SHA256SUMS`: checksums for all three archives.

The runtime uses an x86-64 Unix host build plus Wine's combined i386 and x86-64 Windows PE support. This lets the 64-bit Live application and its retained 32-bit prerequisite installers run in one prefix. It is built on Ubuntu 22.04 against glibc 2.35, stripped, audited for absolute build paths and unsafe runtime search paths, then smoke-tested on Ubuntu, Fedora, and Arch Linux. Graphics drivers, audio services, desktop portals, and glibc remain supplied by the user's distribution so the bundle can work with the host desktop and GPU.

ENCORE compiles upstream Wine 11.13 NTSync support. It uses `/dev/ntsync` when the running kernel provides it and falls back to normal Wine server synchronization when it does not. ENCORE does not currently add Proton or Wine-GE Fsync patches.

## Supported systems

- x86-64 Linux.
- Ubuntu 22.04 or newer and Debian 12 or newer through `apt`.
- Fedora through `dnf`/`dnf5`.
- Arch Linux and CachyOS through `pacman`.
- A Wayland session with Xwayland available is recommended.

GNOME on Wayland is the best-tested desktop. The package setup supports KDE and other desktops, including their portal backends, but ENCORE's window-management compatibility work is still experimental there.

On Arch and CachyOS, approving dependency installation runs `pacman -Syu` because partial upgrades are unsupported. The wizard shows the command before invoking sudo.

The binary runtime is roughly 50 MiB compressed and about 300 MiB after extraction. An optional `--build-from-source` build still needs roughly 15–25 GiB of free space and can use substantial CPU.

## Display scaling

The wizard recommends a value from the current desktop and monitor when it can. You always get the final choice:

| Desktop scale | Wine DPI |
| --- | ---: |
| 100% | 96 |
| 125% | 120 |
| 150% | 144 |
| 175% | 168 |
| 200% | 192 |
| 250% | 240 |

For mixed-DPI monitors, choose the scale of the monitor where Ableton normally opens. You can rerun `./install.sh --no-build` later to change it safely.

## Existing installations and retries

If the selected prefix already contains a complete Ableton installation, the wizard offers to reuse it. A matching verified runtime is reused offline. Interrupted runtime downloads resume safely, and optional source builds resume through Make. ENCORE never deletes a dirty Wine checkout, an unrelated prefix, or completed work.

Once setup begins, detailed logs are stored under `logs/`. A failure reports the stage, log path, and safely quoted retry command. Fix the stated problem and rerun it; completed safe stages are retained. If a Live source folder was supplied but the selected prefix already contains a complete copy, ENCORE reuses the existing copy unless `--replace-live` is explicit. Replacement is staged and validated before the old folder is swapped out.

Live must be closed while ENCORE changes the prefix. In interactive mode the wizard waits for you to close it. It never kills Live or injects remote input.

## Automation and advanced paths

Run `./install.sh --help` for every option. A fully specified unattended install looks like:

```sh
./install.sh --non-interactive --yes --install-deps \
  --live-dir "/path/to/Live 12 Suite" \
  --scale 200 --no-launch
```

Useful alternatives:

```sh
./install.sh --dry-run
./install.sh --build-from-source --build-only --install-deps --jobs 4
./install.sh --no-build --dpi 96
./install.sh --prefix "$HOME/Music/Ableton Prefix"
```

ENCORE refuses to modify a non-empty prefix it does not recognize. Inspect the folder first, then pass `--adopt-prefix` only when you deliberately want ENCORE to own it.

The wizard remembers the selected prefix, Wine, and Ableton paths in `.encore/runtime.conf`, so later setup runs and the bare launcher keep working with custom locations and with `--no-desktop`. Environment variables and command-line options override those saved choices. Setup and launcher variables include:

- `ABLETON_LIVE_DIR`: complete Windows-installed `Live 12 Suite` source folder for a new import.
- `ENCORE_PREFIX`: Wine prefix; defaults to `ableton-prefix`.
- `ENCORE_WINE`: existing ENCORE Wine executable.
- `ENCORE_ABLETON`: Ableton executable path inside the prefix.
- `ENCORE_CPU_TOPOLOGY`: runtime CPU topology override. The default is selected from the Linux affinity/cpuset and capped at eight logical CPUs.
- `ENCORE_WEBVIEW2_FLAGS`: complete WebView2 flag override. Set it to an empty value to disable launcher-supplied flags.

Live's **Settings > Plug-ins > VST3 Custom Folder > Browse** control uses the native desktop folder picker. ENCORE exposes the selected host path to Live and its plug-in scanner, including folders outside your home directory and folders on mounted drives. No symlink or VST path variable is required.

## Known limitations

- GNOME/Wayland/Xwayland is the primary tested window-management path; other desktops remain experimental.
- WebView2 currently requires `--no-sandbox` under this Wine build, weakening isolation for the remote Learn View page.
- DirectComposition is disabled; Learn View uses SwiftShader and CPU compositing.
- Binary releases currently target x86-64 Linux. ARM64 and 32-bit Wine builds are not provided.

## Bug reports and next steps

We love bug reports. ENCORE covers an unusual mix of Wine, desktop integration, audio, plug-ins, graphics, and hardware, so real-world reports are one of the best ways to make it better. If something breaks, [open a GitHub issue](https://github.com/wowitsjack/ENCORE/issues) with your Linux distribution, desktop/session, GPU, the steps that trigger the problem, and the relevant ENCORE log. Please remove personal information and do not upload Ableton installers, installed Ableton application files, Live content, or other licensed files.

The next areas of development are:

- Ableton Push support, including reliable discovery and communication with Push hardware;
- broader USB and MIDI setup, permissions, and hot-plug handling across supported distributions;
- continued compatibility work for plug-ins, WebView2, graphics, audio, and non-GNOME desktops.

## Licensing and bundled material

ENCORE does not redistribute Ableton software. `patches/encore-wine.patch` is a source delta against the pinned upstream Wine revision and remains subject to the applicable upstream file licenses. Binary releases include Wine's license and notices inside the runtime plus the complete corresponding patched Wine source as a separate release asset.

ENCORE does not ship a replacement font binary. It creates a prefix-local Arial-compatible fallback from the user's installed Liberation Sans, retains the source font's license records, and records the source hash in the generated font metadata.
