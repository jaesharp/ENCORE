# WineASIO: low-latency audio (WineASIO → JACK/PipeWire)

ENCORE can build and wire up **WineASIO**, an ASIO driver that bridges Windows
ASIO to the host's JACK server (PipeWire's JACK on a modern desktop). Live then
sees a low-latency **WineASIO** device instead of routing through the higher-latency
default path. This is opt-in and built from source alongside Wine.

> WineASIO is a separate project (GPL-2.0+), pinned and fetched like Wine. The
> integration — the sample-rate patch, the `jacklinkd` recovery helper, and the
> build/register/launcher wiring — is adapted from **shibco/ableton-linux**
> (`ABLETON-WINE-AUDIO-*` notes), attributed in each file.

## Components

| Piece | What it is | Where |
| --- | --- | --- |
| WineASIO driver | `wineasio.dll` (+ Unix `.so`), built against ENCORE's Wine | `runtime/wineasio/` (generated) |
| Sample-rate patch | Keeps the backend rate instead of the fatal `ASE_NoClock` | [`patches/wineasio/0001-clamp-sample-rate.patch`](../patches/wineasio/0001-clamp-sample-rate.patch) |
| `jacklinkd` | Restores JACK links after an audio device replug | `tools/jacklinkd.c` → `runtime/wineasio/jacklinkd` |
| Build step | Fetch + patch + build + install | [`scripts/build-wineasio.sh`](../scripts/build-wineasio.sh) |
| Registration | `regsvr32` into the prefix + host `libjack` check | [`scripts/configure-prefix.sh`](../scripts/configure-prefix.sh) |
| Launcher wiring | `WINEASIO_*` env, `WINEDLLPATH`, starts `jacklinkd` | [`scripts/run-ableton.sh`](../scripts/run-ableton.sh) |

## The sample-rate patch (why Live doesn't crash on first launch)

WineASIO can't change the backend graph rate, and many machines run one fixed rate
(a laptop/Deck codec at 48 kHz). Stock WineASIO returns `ASE_NoClock` on a
mismatch — but **Live treats that refusal as fatal**: it throws out of its
`OnSetSampleRate` handler, the exception is uncaught, and Live dies during
startup, *before* the Preferences dialog exists, so the user can never reach the
control that would fix the rate. A fresh install lands in a permanent crash loop
(Live defaults to 44.1 kHz, PipeWire to 48 kHz). The patch keeps the backend rate
and reports success; Live reads the effective rate back with `GetSampleRate` and
runs the engine at the graph's real rate.

## Device recovery: `jacklinkd`

Live's ASIO "device" is the JACK graph, which survives a hardware unplug — but the
JACK *links* between WineASIO's ports and the hardware ports are destroyed with the
device, and PipeWire/WirePlumber never restore JACK links on replug. `jacklinkd`
is a port-less JACK client the launcher starts: it remembers the links a port held
when it disappeared and re-creates them when a same-named port returns, leaving
deliberate disconnects alone. It restores only links it has seen (it can't invent
routing for a never-connected device) — the same limitation as the
[MIDI hotplug](patches/midi-hotplug.md) fix.

## Building it

WineASIO is built by default during a **source** install and installed to
`runtime/wineasio/` (nothing is copied into the Wine tree):

```sh
./install.sh                 # builds Wine, then WineASIO + jacklinkd
./install.sh --no-wineasio   # skip WineASIO
./scripts/build-wineasio.sh  # (re)build it on its own against an already-built Wine
```

`build-wineasio.sh` clones WineASIO at the pinned revision (`WINEASIO_REVISION` in
`common.sh` — 1.3.0), applies `patches/wineasio/*.patch`, stages a private install
of the built Wine for the ABI, builds the 64-bit driver, and compiles `jacklinkd`.
It needs the **JACK development headers** (`libjack-jackd2-dev` /
`pipewire-jack-audio-connection-kit-devel`) — added to the dependency lists — and
the host **`libjack.so.0`** at runtime (`pipewire-jack`, or JACK2).

The prebuilt-runtime path (`--prebuilt`) does not include WineASIO; use a source
build for low-latency audio.

## First use (in Live)

1. Preferences → Audio → **Driver Type: ASIO** → **Device: WineASIO**.
2. Untick **Auto-Scale Plugin Window** if a plugin window resize-loops.
3. If WineASIO isn't listed: install `pipewire-jack` and restart Live; confirm the
   prefix was configured (`configure-prefix.sh`).

## Runtime knobs

Set in the environment before launch (see [environment.md](environment.md)):
`WINEASIO_NUMBER_INPUTS`/`_OUTPUTS` (default 2), `WINEASIO_FIXED_BUFFERSIZE`
(default `on`), `WINEASIO_PREFERRED_BUFFERSIZE` (default 256 — raise to 512 if you
hear crackles), `WINEASIO_CONNECT_TO_HARDWARE` (default `on`).

## What ENCORE verifies vs. what needs your machine

The build is verified end-to-end (the patched driver compiles and links against
ENCORE's Wine; `jacklinkd` compiles and links against the host JACK; the launcher
wires everything when `runtime/wineasio/` is present). The **runtime** behaviour —
Live listing WineASIO, low-latency playback, and link recovery on replug — needs a
JACK/PipeWire session and audio hardware to confirm. `scripts/check-live-audio.sh`
automates the first check: it launches Live, watches the Live log until the audio
driver reports `Open: finished` (exit 0) or fails, then shuts the session down
(see [scripts.md](scripts.md)).
