# Dynamic menu-bar theming (win32u)

## Problem

Live draws its own dark UI, but the Win32 menu bar (`File Edit Create …`) is
drawn by Wine with stock system colours — a light grey strip glued onto a dark
application. Wine has no theme engine hook that would let the menu bar follow
an application's palette, and Live offers no way to draw the bar itself.

## What the patch does

`dlls/win32u/menu.c` learns to **sample Live's own window pixels and paint the
menu bar to match**, gated twice so it can never affect other applications:

1. `use_ableton_live_menu_theme()` — the `ENCORE_ABLETON_MENU_THEME`
   environment variable must be set to a non-`0` value (the launcher defaults
   it to `1`), **and** the window's class name must start with the prefix
   `Ableton Live Window` (checked with `NtUserGetClassName` + `memcmp`).
2. Sampling must actually succeed; any failure leaves `theme_background =
   CLR_INVALID` and drawing falls back to stock colours.

### Sampling (`sample_ableton_live_menu_theme`)

On each `NtUserDrawMenuBarTemp` pass, the code takes a window DC
(`DCX_CACHE | DCX_WINDOW`) and reads pixels **just below the menu bar** — the
top strip of Live's own rendered content: seven columns across the width (at
1/8-multiples, centre first: `{6,1,2,3,4,5,7}`) × three rows at 10/12/14
logical pixels below `menu_rect->bottom`, DPI-scaled via `map_user_dpi`. The
**modal colour** (most frequent sample) wins, which makes the sample robust
against text glyphs or a highlighted control crossing one sample point. Live's
theme changes (light/dark, custom skins) are picked up automatically on the
next redraw because nothing is cached across draws beyond the menu struct
fields.

### Painting

- `struct menu` gains `theme_background` / `theme_text` (initialised to
  `CLR_INVALID` in `create_menu`).
- Text colour is chosen by `contrasting_text_color()` — ITU-R 601 luminance
  (`299·R + 587·G + 114·B ≥ 128000` → black text, else white).
- `NtUserDrawMenuBarTemp` and `draw_menu_item` fill with the stock `DC_BRUSH`
  set to the sampled colour (saving and restoring the DC brush colour), and use
  `theme_text` for both normal and highlighted items so hover states stay
  legible. Popup menus are untouched — only the bar is themed.

### The 4-pixel metric fix

Unrelated to colour but in the same file: `calc_menu_bar_size()` now adds
**4 logical pixels** (DPI-scaled) below the items when the owner window has
`WS_CAPTION | WS_THICKFRAME`, matching real Windows metrics for framed windows.
A new test, `test_menu_bar_height` (`dlls/user32/tests/menu.c`), pins this: the
non-client height must equal `AdjustWindowRectExForDpi` plus
`MulDiv(4, dpi, 96)`.

## Key files

| File | Role |
| --- | --- |
| `dlls/win32u/menu.c` | gate, sampler, contrast picker, themed drawing, +4px metric |
| `dlls/user32/tests/menu.c` | `test_menu_bar_height` |

## Runtime toggles

| Variable | Default | Effect |
| --- | --- | --- |
| `ENCORE_ABLETON_MENU_THEME` | `1` (launcher) | Enable sampling/theming for Ableton Live windows. Set `0` to get the stock grey bar. |

## Caveats

- Pixel sampling is inherently heuristic: it assumes the area directly below
  the menu bar shows Live's chrome. In practice Live's transport/toolbar strip
  sits there at every window size ENCORE allows (see the minimum-size hint in
  [windowing-and-hidpi.md](windowing-and-hidpi.md)).
- The class-prefix gate means plug-in windows and other apps in the prefix are
  never themed.

## How to verify

Launch Live with the default environment: the menu bar should match Live's
theme colour, with readable (auto-contrast) labels, including while hovering
items. Switch Live between light and dark themes: the bar follows after the
next redraw. `ENCORE_ABLETON_MENU_THEME=0 scripts/run-ableton.sh` restores the
stock bar. The Wine test `dlls/user32/tests/menu.c` covers the height metric.
