# Audio endpoint FriendlyName re-wrap fix (`dlls/mmdevapi/devenum.c`)

> Ported from **shibco/ableton-linux** `patches/0021` (a fix to LGPL-2.1+ Wine),
> regenerated against wine-11.13; behaviour unchanged. The root-cause analysis
> below is condensed from that project's `notes/ABLETON-WINE-AUDIO-CRASH-BUG.md`.
> Patch file: [`patches/wine/70-audio-endpoint-friendlyname.patch`](../../patches/wine/70-audio-endpoint-friendlyname.patch).

A small, self-contained fix that stops a prefix's audio-endpoint registry from
corrupting itself over successive launches. General WineHQ bug; an upstreaming
candidate.

## Problem

`mmdevapi` stores each audio endpoint under
`HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices\Audio`, with a
`FriendlyName` property of the form `"<FormFactor> (<driver description>)"`,
e.g. `Speakers (Realtek HD Audio)`. `MMDevice_Create()` **rebuilds and re-saves**
that FriendlyName on every call — including when a device is *reloaded from the
registry*, whose stored `drv_id` is already a finished FriendlyName.

- **Present devices** get a fresh, flat description from the driver each boot, so
  their name is regenerated correctly.
- **Absent devices** (an unplugged USB interface, a powered-off monitor's audio,
  a disconnected Bluetooth sink) are only ever reloaded from the registry. Each
  reload wraps the already-wrapped name one level deeper:
  `Speakers (Speakers (Speakers (…)))`. Depth of 70+ has been observed.

Eventually the endpoint enumeration that Live performs at startup
(right after `Audio In Out: Constructor finished`) chokes on the pathological
name and the process crashes. The audio server reports flat names throughout —
the nesting is generated entirely by Wine on read-back.

## What the patch does

`MMDevice_Create()` gains a `BOOL init_props` parameter:

- `load_driver_devices()` (creating a device from a **raw driver-supplied name**)
  passes `TRUE` — the name properties are generated as before.
- `load_devices_from_reg()` (**reloading** a stored, already-formatted device)
  passes `FALSE` — the stored `Properties` key is left untouched, so the
  FriendlyName is preserved verbatim instead of being re-wrapped.

The change is limited to `dlls/mmdevapi/devenum.c`: the function signature plus
its two call sites.

## Verification

- Compiles warning-clean for both `x86_64-windows` and `i386-windows`
  (the module is PE).
- With the patch, launching Live repeatedly leaves absent endpoints' FriendlyName
  flat in the registry instead of gaining a nesting level per boot.

## Note: healing an already-corrupt prefix

The patch stops the *growth* but does not shorten names already nested by an
older runtime. A prefix that has already accumulated deep nesting needs a
one-time clear (see [../troubleshooting.md](../troubleshooting.md)):

```sh
WINEPREFIX=… wine reg delete \
  'HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices\Audio' /f
```

Active endpoints regenerate flat on the next launch; absent devices are simply
not recreated until they return.
