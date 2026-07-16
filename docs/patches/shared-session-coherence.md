# Shared-session view coherence (`dlls/win32u/winstation.c`, `server/mapping.c`)

> Ported from **shibco/ableton-linux** `patches/0018` + `0019` (fixes to
> LGPL-2.1+ Wine), regenerated against wine-11.13. Analysis condensed from
> that project's `notes/ABLETON-WINE-INPUT-BUG.md`. Patch file:
> [`patches/wine/110-shared-session-coherence.patch`](../../patches/wine/110-shared-session-coherence.patch).

Fixes a **vanilla-Wine** shared-memory coherence bug whose symptoms read as UI
misbehavior: multi-second freezes when opening menus, and intermittent
`VST3: plug window creation failed`. Not specific to any rendering stack;
upstreaming candidate.

## Problem

wineserver publishes session state (window classes among it) through a shared
memfd. Clients map those views read-only — and ntdll maps *read-only* views
`MAP_PRIVATE` on Linux, which is **not coherent** for a memfd another process
keeps writing. A client's view can go permanently stale:

- `find_shared_session_object()` reads object id `0` where the server has
  since written a class object;
- `NtUserRegisterClassExW` fails, and window creation dies with a swallowed
  null-call access violation inside `WM_NCCREATE`;
- each swallowed AV burns ~2.4 s in Live's vectored crash handler — felt as
  "menu opens, then the app freezes for seconds";
- the same mechanism kills `Vst3PlugWindow` creation outright.

shibco measured 10–12 session-object mismatches per boot on an affected setup.

## What the patch does

- **win32u** (`0019`, the decisive half): request session views with
  `SECTION_MAP_READ|SECTION_MAP_WRITE` + `PAGE_READWRITE`, so ntdll maps them
  `MAP_SHARED` and they stay coherent with the server's writes. The read-only
  mapping is kept as a fallback.
- **server** (`0018`): pre-dirty newly grown session blocks and fix a
  block-match off-by-one (`<` → `<=`), so freshly extended session memory is
  consistent before clients read it.

## Verification

- Compiles warning-clean (`wineserver`, `win32u.so`).
- shibco's stress verification: 30,000 register-class + create/destroy-window
  iterations across mapping growths, zero failures; session-object mismatches
  per boot went from 10–12 to 0.

## Diagnostics

`WINEDEBUG=warn+winstation,err+class` flags the session-object failure;
`+seh` shows the swallowed access violations.
