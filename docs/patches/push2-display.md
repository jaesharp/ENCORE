# Push 2 display: host-USB bridge (`dlls/libusb-1.0/`)

> Ported from **shibco/ableton-linux** `patches/0032` (a new LGPL-2.1+ Wine
> module), rebased onto wine-11.13. Analysis condensed from that project's
> `notes/ABLETON-WINE-PUSH2-DISPLAY.md`. Patch file:
> [`patches/wine/100-push2-libusb-bridge.patch`](../../patches/wine/100-push2-libusb-bridge.patch);
> activation lives in [`scripts/configure-prefix.sh`](../../scripts/configure-prefix.sh).

ENCORE's first Push **display** support: it lets Ableton's `Push2DisplayProcess.exe`
drive the Push 2's 960×160 screen under Wine. (Push 2 **MIDI** — pads, encoders,
LEDs — works over ALSA already, and reconnects thanks to
[midi-hotplug.md](midi-hotplug.md).)

## Problem

From USB, a Push 2 is a composite device: a class-compliant **MIDI** interface
(interfaces 1–2, claimed by ALSA `snd-usb-audio`) plus a **generic bulk
interface (interface 0)** used only to stream display frames. Ableton's helper
`Push2DisplayProcess.exe` opens interface 0 through the copy of `libusb-1.0`
Ableton bundles, which on Windows reaches the device via SetupAPI/WinUSB.

Under Wine, MIDI works end-to-end, but **Wine's WinUSB emulation cannot open the
Push 2 vendor bulk interface**, so the display helper fails while everything else
about the controller works. The screen stays dark.

## What the patch does

Rather than complete Wine's WinUSB emulation, it adds a Wine **builtin**
`libusb-1.0.dll` — a normal Wine PE/Unix-split module (see the
[PE/Unix split](README.md#the-pe--unix-split)):

- **PE half** (`dlls/libusb-1.0/libusb.c`, built from `libusb-1.0.spec`) exports
  the exact **16-function Win64 `libusb` 1.0.23 ABI**, with Ableton's original
  ordinals, that `Push2DisplayProcess.exe` imports. Each call marshals into a
  fixed-width `WINE_UNIX_CALL`.
- **Unix half** (`dlls/libusb-1.0/unixlib.c`) forwards to the **host's real
  `libusb-1.0.so.0`**, which opens `/dev/bus/usb/...` interface 0 and its bulk
  endpoints (`0x01` / `0x81`) directly. It reuses Wine's existing
  `USB_CFLAGS`/`USB_LIBS` (the same host libusb the `wineusb` driver detects).

It is deliberately narrow: **x86-64 only** (`enable_libusb_1_0=x86_64` in
`configure.ac`; the i386 build is disabled), interface-0/bulk-transfer oriented,
and it does no VID/PID filtering of its own.

### Activation is scoped to the display helper

The builtin is selected **only for `Push2DisplayProcess.exe`**, via a
per-application DLL override that `configure-prefix.sh` writes to the prefix:

```
HKCU\Software\Wine\AppDefaults\Push2DisplayProcess.exe\DllOverrides
    libusb-1.0 = builtin
```

Live's own process keeps loading Ableton's bundled `libusb-1.0` untouched. The
narrow override is the safety boundary — the bridge only ever runs for the one
helper that needs it.

## Rebase notes (11.13)

The three new source files, `Makefile.in`, and `.spec` apply unchanged. The
`configure`/`configure.ac` wiring was re-anchored, and the enable-guard was
switched from 11.11's `ac_cv_lib_usb_1_0_libusb_interrupt_event_handler` to
11.13's `ac_cv_func_libusb_interrupt_event_handler` (11.13 probes libusb with
`AC_CHECK_FUNC`, not `AC_CHECK_LIB`). **Without that change the module silently
disables itself at configure time** and never builds — worth remembering on the
next Wine rebase.

## Verification

- The module compiles warning-clean and links: `unixlib.c` (unix, against host
  `-lusb-1.0`), `libusb.c` (x86_64 mingw PE), and the 16-export
  `libusb-1.0.dll` from the spec. That it builds **at all** confirms the
  configure guard is correct (a wrong variable name would disable it).
- Hardware verification (the Push 2 screen actually lighting up) requires the
  device and has not been done here.

## Not Push 3

This bridge does **not** cover Push 3. `Push3.exe` imports a wider `libusb`
surface (it adds hotplug register/deregister and a synchronous
`libusb_bulk_transfer`) and is a much larger native application; extending the
bridge to it is separate, open work.
