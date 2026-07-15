# MIDI device hotplug re-subscribe (`dlls/winealsa.drv/alsamidi.c`)

> Ported from **shibco/ableton-linux** `patches/0028` (a fix to LGPL-2.1+ Wine),
> regenerated against wine-11.13; behaviour unchanged. Analysis condensed from
> that project's `notes/ABLETON-WINE-MIDI-HOTPLUG.md`. Patch file:
> [`patches/wine/80-midi-hotplug.patch`](../../patches/wine/80-midi-hotplug.patch).

Lets a MIDI controller survive an in-session unplug/replug without restarting
Live. Upstreaming candidate.

## Problem

Wine's ALSA MIDI driver has two hotplug gaps:

1. `alsa_midi_init()` enumerates sequencer ports **once per process** (an
   `init_done` latch); the winmm device table is a one-time snapshot.
2. Each open MIDI in/out is subscribed to a fixed ALSA sequencer `client:port`
   address. On unplug the kernel client disappears and ALSA silently drops the
   subscription. Nothing re-subscribes — **even when the device returns at the
   identical address**.

Result: unplug a controller mid-session and plug it back in, and it stays dead
(no input, no LED feedback) until Live is restarted. On Windows the same replug
just works. This affects ordinary USB-MIDI controllers and Ableton Push alike.

## What the patch does

All within `dlls/winealsa.drv/alsamidi.c`:

- **Listen for port lifecycle.** `seq_open()` subscribes the driver's shared
  input port to the ALSA **System Announce** port (`0:1`), so the record thread
  receives `SND_SEQ_EVENT_PORT_START` events when ports (re)appear.
- **Stable name key.** The "client - port" display-name construction is factored
  out of `port_add()` into a `port_display_name()` helper, so the name used at
  enumeration and the name used for hotplug re-matching are identical.
- **Re-attach on reappearance.** A new `handle_port_start()` queries the new
  port, rebuilds its display name, matches it against the enumerated
  sources/destinations, adopts the new sequencer address, and re-subscribes any
  open input/output. `midi_handle_event()` routes announce-port events to it.

It works whether the device returns at the same or a different ALSA client id,
for both raw kernel sequencer ports and PipeWire Midi-Bridge ports (name-keyed).

## Caveats (inherited from the fix)

- Only devices **present at enumeration** are re-attached; a never-before-seen
  device still needs a Live restart (growing the table dynamically would race the
  unlocked source/destination indexing on other threads).
- Announce processing rides the record thread, which runs only while at least one
  MIDI input is open. Live keeps enabled inputs open, so this holds in practice.
- Identically-named controllers collide: the first table entry wins.

## Verification

- Compiles warning-clean (unix `.so`).
- Reproducible without hardware using shibco's `fakectl` (a fake controller;
  kill + restart simulates a replug) and a winmm MIDI-in listener: the unpatched
  driver freezes permanently after replug, the patched driver resumes in under a
  second, including at a changed client id.
