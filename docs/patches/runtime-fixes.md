# Runtime fixes: DXGI vblank, msvcp `basic_istream`, mount reparse points

Three small, self-contained fixes that Live depends on. Each would be a
candidate for upstreaming.

## 1. DXGI `IDXGIOutput::WaitForVBlank` pacing (`dlls/dxgi/output.c`)

### Problem

Upstream Wine stubs `WaitForVBlank` with `E_NOTIMPL`. GUI frameworks —
including the rendering path Live's UI uses — call it as their **repaint
clock**: wait for vblank, then paint invalid regions. When the call fails,
invalid regions can stay queued forever and the UI stops updating.

### What the patch does

There is no host vblank primitive available at this layer, so the patch
returns a **paced success** instead of a stub:

- Reads the current display mode's refresh rate via
  `wined3d_output_get_display_mode` (clamped to 24–1000 Hz, defaulting to 60
  when the reported value is unusable).
- Computes the time to the next refresh boundary on the
  `QueryPerformanceCounter` timeline (`remaining = period − counter % period`)
  and sleeps exactly that long with `NtDelayExecution` (100 ns units, minimum
  one tick).
- Returns `S_OK`.

Callers therefore get real frame pacing aligned to a stable modulo grid — not
actual scanout synchronisation, but correct cadence and, crucially, success.
A new test in `dlls/dxgi/tests/dxgi.c` asserts three consecutive calls block
measurably (> 0.5 ms total) but less than a second.

## 2. msvcp `basic_istream` move constructor/assignment (`dlls/msvcp90/ios.c`, `dlls/msvcp140/msvcp140.spec`)

### Problem

Two win64 exports of msvcp140 were declared but stubbed in Wine:

```
??0?$basic_istream@DU?$char_traits@D@std@@@std@@IEAA@$$QEAV01@@Z   (move ctor)
??4?$basic_istream@DU?$char_traits@D@std@@@std@@IEAAAEAV01@$$QEAV01@@Z (move assign)
```

Code in Live's stack (MSVC-compiled C++ using `std::basic_istream<char>` moves)
imports them; a stub export means an unresolved call at load or crash at use.

### What the patch does

Implements both in `msvcp90/ios.c` the same way MSVC's runtime does:

- `basic_istream_char_ctor_move` — construct an empty istream
  (`basic_istream_char_ctor(this, NULL, FALSE, virt_init)`) then
  `basic_istream_char_swap` with the source.
- `basic_istream_char_op_assign_move` — swap with the source and return `this`.

The spec file flips the two entries from `stub` to `cdecl`, and a new test
(`test_basic_istream_move` in `dlls/msvcp140/tests/msvcp140.c`) exercises both
through `GetProcAddress`, verifying the internal count field actually moves.

## 3. `WINE_DISABLE_UNIX_MOUNT_REPARSE` (`dlls/ntdll/unix/file.c`)

### Problem

Upstream Wine reports Unix **mount points** as directory reparse points
(`IO_REPARSE_TAG_MOUNT_POINT`), imitating NTFS junctions. But these synthetic
reparse points carry no reparse *data*: an application that canonicalises every
reparse point it encounters via `FSCTL_GET_REPARSE_POINT` — as Live's file
scanner does — gets errors or hangs whenever a library folder crosses a mount
boundary (external drives, network mounts, bind mounts).

### What the patch does

Adds `unix_mount_points_are_reparse_points()` — a one-time
`getenv("WINE_DISABLE_UNIX_MOUNT_REPARSE")` check — and guards the two places
that synthesise the mount-point tag (`fd_get_file_info` for
`FILE_OPEN_REPARSE_POINT` opens, and the parent-`stat` comparison in
`get_file_info`). With the variable set, mount boundaries look like ordinary
directories. The launcher (`scripts/run-ableton.sh`) always exports
`WINE_DISABLE_UNIX_MOUNT_REPARSE=1`; unset it to restore upstream behaviour
for other software.

## Key files

| File | Fix |
| --- | --- |
| `dlls/dxgi/output.c`, `dlls/dxgi/tests/dxgi.c` | vblank pacing + timing test |
| `dlls/msvcp90/ios.c`, `dlls/msvcp140/msvcp140.spec`, `dlls/msvcp140/tests/msvcp140.c` | istream move ops + test |
| `dlls/ntdll/unix/file.c` | mount-reparse suppression |

## Runtime toggles

Only the third fix has one: `WINE_DISABLE_UNIX_MOUNT_REPARSE` (see
[../environment.md](../environment.md)). The DXGI and msvcp changes are
unconditional.

## How to verify

- **DXGI:** the patched `dlls/dxgi/tests/dxgi.c` `test_output` asserts pacing;
  in Live, the UI keeps repainting (scope/meters animate) on systems where it
  previously froze.
- **msvcp:** run the patched msvcp140 tests; both exports resolve via
  `GetProcAddress`.
- **Reparse:** with a sample library on a separate mount, Live's browser must
  index across the mount boundary; `WINE_DISABLE_UNIX_MOUNT_REPARSE=` (empty)
  restores upstream behaviour for comparison.
