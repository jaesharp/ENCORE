# Diagnostic probes

Small, single-purpose diagnostics for the Wine behaviours ENCORE patches.
They are **manual maintainer/tester tools** — not built or run by the
installer, and nothing at runtime depends on them.

The sources are taken **verbatim** from
[shibco/ableton-linux](https://github.com/shibco/ableton-linux) (`tools/`,
mirrored in their `beta/tester-kit/probes/`), whose maintainer confirmed all
tools and source in that repository are **LGPL — the same license as Wine**.
Keeping them byte-identical preserves provenance; ENCORE adds only this README
and `scripts/build-probes.sh`.

Build everything with:

```sh
scripts/build-probes.sh          # -> build/probes/
```

Native probes need the ALSA and X11 dev headers; the PE probes build CRT-free
with the same mingw-w64 cross compiler the Wine build already requires, and run
inside the prefix:

```sh
WINEPREFIX=$PWD/ableton-prefix build/wine64/wine build/probes/dpispy.exe
```

## The probes

| Probe | Side | What it does |
| --- | --- | --- |
| `fakectl` | native (ALSA) | Fake ALSA-seq MIDI controller: client "FakeCtl", one duplex port, a note-on/off pair every 500 ms. Kill + restart it to simulate a USB MIDI unplug/replug (the client id changes, exactly like hardware). |
| `midihot.exe` | PE (winmm) | Lists midi-in devices, opens the first whose name contains `FakeCtl` (or arg 1), prints every `MIM_DATA` until killed. |
| `dpispy.exe` | PE | Dumps DPI awareness context, per-window DPI, and logical/physical rects for every visible window → `dpispy.txt`. |
| `metricprobe.exe` | PE | Creates a window with Live's exact main-window anatomy (style `0x16cf0000`, ex `0x100`, real menu bar) and prints the `AdjustWindowRectExForDpi` vs `WM_NCCALCSIZE` non-client arithmetic → `metricprobe.txt`. |
| `wmresize.exe` | PE | Minimal reproducer for the WM-driven resize settle: a visible overlapped window that mimics Live's `WM_WINDOWPOSCHANGED` handler (client → adjust → `SetWindowPos`) and logs every rect for ~30 s → `wmresize.txt`. Class `WmResizeProbe`. |
| `xsettle` | native (X11) | Finds Live's toplevel X window (`XSETTLE_MATCH`, default `bleton`): `find` prints id+geometry, `moveresize X Y W H` sends `_NET_MOVERESIZE_WINDOW` (a WM-side tile/snap), `poll SECONDS` prints geometry changes at 100 ms. |

## Recipe: verify MIDI hotplug (patch 80) without hardware

The `fakectl` + `midihot` pair proves winealsa's hotplug re-subscribe end to
end, no controller required:

```sh
scripts/build-probes.sh
build/probes/fakectl &                      # fake controller appears
WINEPREFIX=$PWD/ableton-prefix build/wine64/wine build/probes/midihot.exe &
                                            # prints MIM_DATA lines
kill %1; sleep 2; build/probes/fakectl &    # "replug": new client id
# with patch 80: MIM_DATA lines resume; without it: silence until restart
```

## Recipe: drive the windowing/DPI work

- `dpispy.exe` while Live runs: confirm Live's main window reports the expected
  DPI context and that logical vs physical rects agree with the display scale.
- `metricprobe.exe`: the non-client arithmetic behind the `+4px`/settle bugs.
- `wmresize.exe` + `xsettle moveresize`/`poll` from the X side: reproduce a
  WM-driven configure against a Live-shaped window without Live, and watch
  whether the size settles or drifts.
