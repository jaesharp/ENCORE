# Troubleshooting & known limitations

## Known limitations

- **GNOME/Wayland/Xwayland is the primary tested path.** KDE and other desktops
  are supported for packaging but window-management work is experimental there.
- **WebView2 (Live 12) requires `--no-sandbox`** under this Wine build, weakening
  isolation for the Learn View page. It is part of the default
  `ENCORE_WEBVIEW2_FLAGS` (see [environment.md](environment.md)).
- **DirectComposition is disabled** (`dcomp=` in `WINEDLLOVERRIDES`); the Learn
  View uses SwiftShader and CPU compositing.
- **You supply Ableton.** ENCORE never downloads, bundles, or runs the installer;
  it imports a complete installed Live folder you provide.

## First diagnostic step

```sh
ENCORE_DRY_RUN=1 scripts/run-ableton.sh
```

Then the logs: install logs `logs/install-YYYYmmdd-HHMMSS.log` (path printed on
any failure, with a quoted retry command); launch log `logs/ableton-dock.log`.

## Obtaining Wine (prebuilt runtime)

| Symptom | Cause | Fix |
| --- | --- | --- |
| "requires glibc 2.35 or newer; use --build-from-source" | Host glibc too old for the prebuilt runtime | Run `./install.sh --build-from-source` (needs the mingw toolchain — see [building.md](building.md)). |
| "runtime checksum verification failed" | Corrupted/incomplete download, or a stale pin | Re-run setup (the download resumes); if it persists, the pinned `ENCORE_RUNTIME_SHA256` may need updating for the current release. |
| "runtime archive contains an unsafe path" | Tampered/unexpected archive | Do not use it; re-download from the official release. |
| "the runtime destination exists but is not a valid ENCORE runtime" | `runtime/wine/` is present but fails validation | Remove `runtime/wine/` and re-run so it re-downloads. |

## Supplying the Ableton Live folder

`validate_live_source` explains exactly why a folder was rejected. Common ones:

| Message (paraphrased) | Cause | Fix |
| --- | --- | --- |
| "That path is an executable or installer" / "…an archive" | You pointed at an installer, `.exe`/`.msi`, or a `.zip`/`.7z` | Install Live on Windows (or extract your licensed copy), then supply the resulting **folder**. |
| "Select the parent Live folder, not Program by itself" | You selected the inner `Program/` | Select the outer `Live <ver> <edition>/` folder. |
| "not a complete installed Live folder: missing … Program/Resources/Redist/Legal" | Incomplete copy | Copy the entire outer folder, preserving all subdirectories. |
| "Installation.cfg does not match the detected … folder" | Folder/executable/`variant` mismatch | Ensure the folder name, the `.exe` name, and `Installation.cfg`'s `variant` all name the same version+edition. |
| "does not contain a supported Visual C++ redistributable under Redist" | `Redist/` incomplete | Copy the complete folder including `Redist/`. |
| "This Live 12 folder is missing the WebView2 setup" | `Redist/` lacks the WebView2 installer (Live 12) | Supply a complete Live 12 folder. |
| "must be self-contained and may not contain symbolic links" | The copy has symlinks/special files | Copy so files are real (e.g. `cp -a` from the original). |

## Prefix / prerequisite installs

| Symptom | Cause | Fix / knob |
| --- | --- | --- |
| "Wine did not finish initializing the prefix" | `wineboot` failed twice | Check the log; ensure the runtime is valid and disk isn't full. |
| "Visual C++ setup failed…" / files not installed | VC++ redist from `Redist/` didn't apply | Re-run; ensure the imported folder's `Redist/` is complete. |
| "WebView2 did not finish installing" (Live 12) | The WebView2 bootstrapper needs internet to fetch the runtime | Connect to the internet and re-run ENCORE. |
| "Ableton Live is running…" | Live is open | Close Live; ENCORE waits and never kills it. |
| "selected prefix is non-empty and not recognized" | Pointing at a folder ENCORE didn't create | Use an empty `--prefix`, or `--adopt-prefix` after checking it. |

## Runtime issues (after setup)

| Symptom | Likely cause | Fix / knob |
| --- | --- | --- |
| Browse dialog is the old Wine one, not the native picker | Portal disabled/unavailable | Confirm `FileDialogPortal=always` (set by `configure-prefix.sh`) and a FileChooser portal backend; force with `WINE_FORCE_PORTAL=1`. See [portal-file-picker.md](patches/portal-file-picker.md). |
| Can't reach host files / other drives in the picker | Host root drive missing | `configure-prefix.sh` maps a drive letter to `/`; re-run `./install.sh --no-build`. |
| VST3 window has no title bar / garbled after resize / mis-scaled | VST3 toggles off | Ensure `ENCORE_NATIVE_VST3_DECORATIONS`/`_RESIZE_REPAINT`/`_DPI` = `1`. See [windowing-and-hidpi.md](patches/windowing-and-hidpi.md). |
| Window jitters/drifts when moved on a scaled display | HiDPI config rounding | Suppressed by the config-rounding state machine; report with a `winex11.drv` log if it recurs. |
| Menu bar is grey, doesn't match Live | Menu theming off | Ensure `ENCORE_ABLETON_MENU_THEME=1`. See [menu-theming.md](patches/menu-theming.md). |
| Dragging files from the desktop does nothing | DnD path/target | See [drag-and-drop.md](patches/drag-and-drop.md). |
| Audio glitches under load | CPU topology | Inspect/override `WINE_CPU_TOPOLOGY`. See [cpu-and-threads.md](patches/cpu-and-threads.md). |
| Live hangs scanning across a mount point | Reparse-point canonicalisation | `WINE_DISABLE_UNIX_MOUNT_REPARSE=1` (set by the launcher) addresses this. See [runtime-fixes.md](patches/runtime-fixes.md). |
| Live crashes at startup right after opening audio | An older runtime nested an audio endpoint's registry name without bound (`Speakers (Speakers (…))`) | Fixed going forward by [audio-endpoint-friendlyname.md](patches/audio-endpoint-friendlyname.md); heal an already-corrupt prefix **once** with `wine reg delete 'HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices\Audio' /f`, then relaunch. |
| A MIDI controller (Push included) goes dead after an in-session unplug/replug | ALSA dropped the subscription on unplug | Re-subscribed automatically by [midi-hotplug.md](patches/midi-hotplug.md) **if the device was present when Live started**; a never-before-seen device still needs a Live restart. |
| A plugin editor crashes Live as it opens (needs an sRGB framebuffer) | The GUI requires `WGL_FRAMEBUFFER_SRGB_CAPABLE`, unadvertised in stock Wine | Advertised by [opengl-srgb.md](patches/opengl-srgb.md); make sure your runtime includes patch `90` (any current source build does). |
| Push 2's screen stays dark although its pads/MIDI work | Wine's WinUSB can't open the Push 2 display (bulk) interface | ENCORE routes `Push2DisplayProcess.exe` through a `libusb-1.0` bridge — see [push2-display.md](patches/push2-display.md); confirm the prefix was configured (`configure-prefix.sh`) and your runtime includes patch `100`. |
| WineASIO missing from Live's audio device list | Host `libjack` not found, or WineASIO not built/registered | Install `pipewire-jack` and restart Live; WineASIO needs a **source** build (it isn't in the prebuilt runtime) and `configure-prefix.sh` to have registered it. See [wineasio.md](wineasio.md). |
| Crackling / dropouts on WineASIO | Buffer size too small | Raise `WINEASIO_PREFERRED_BUFFERSIZE` to `512` (or the WineASIO panel's buffer). |
| Audio goes silent after unplugging/replugging an interface | PipeWire doesn't restore JACK links on replug | `jacklinkd` (started by the launcher) restores links it has seen; a device that was never wired to Live needs manual routing. See [wineasio.md](wineasio.md). |
| Opening a menu freezes Live for seconds; intermittent "VST3: plug window creation failed" | Stale shared-session views (vanilla-Wine coherence bug) | Fixed by patch `110` — see [shared-session-coherence.md](patches/shared-session-coherence.md); diagnose with `WINEDEBUG=warn+winstation,err+class`. |
| Menus open then instantly close; keyboard shortcuts inert (strict WMs) | Zero-timestamp activation requests dropped by the WM | Fixed by patch `120` — see [activation-timestamps.md](patches/activation-timestamps.md). |
| Solid black rectangles around plugin popup menus | Layered shadow windows never get per-pixel alpha | Fixed by patch `130` — see [layered-attr-sync.md](patches/layered-attr-sync.md). |
| A plugin editor flickers between two sizes (half-size "ghost"); a modal in it can't be closed | Live's **Auto-Scale Plugin Window** hosts the editor DPI-unaware; its size negotiation never converges | Right-click the device header → untick **Auto-Scale Plugin Window**, reopen the editor (host config, not a Wine bug — see [present-dpi-context.md](patches/present-dpi-context.md)). |
| A GL-rendered plugin editor collapses to 1×1 and wedges Live (X `BadMatch` in stderr) | GL present onto a non-default-visual window picks the wrong pict format | Fixed by patch `140` — see [gl-editor-visual.md](patches/gl-editor-visual.md). |

## Reporting

Include the dry-run output, the relevant log, your distro/desktop/session, DPI,
and the Live version+edition. For patched behaviour, a Wine debug-channel log
(`WINEDEBUG=+winex11` etc.) for the affected subsystem is invaluable.
