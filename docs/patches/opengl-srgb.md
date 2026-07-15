# EGL sRGB-capable pixel formats (`dlls/win32u/opengl.c`, `dlls/winex11.drv/opengl.c`)

> Ported from **shibco/ableton-linux** `patches/0020` (a fix to LGPL-2.1+ Wine).
> The `win32u/opengl.c` and `include/wine/opengl_driver.h` hunks apply unchanged
> to wine-11.13; the `winex11.drv/opengl.c` hunk was **rebased by hand** (11.13's
> `x11drv_egl_surface_create` takes a `client_surface` and uses `surface->window`).
> Patch file: [`patches/wine/90-opengl-srgb.patch`](../../patches/wine/90-opengl-srgb.patch).

Makes Wine's EGL backend advertise and honor sRGB-capable pixel formats, so
plugin GUIs that require them can find a format instead of crashing their host.
Upstreaming candidate.

## Problem

Upstream Wine's EGL backend hard-codes `framebuffer_srgb_capable = GL_FALSE`
(with a `/* TODO: Support SRGB surfaces */`). Some plugin editor GUIs — notably
Rust **baseview**-based VST3 editors — call `wglChoosePixelFormatARB` requiring
`WGL_FRAMEBUFFER_SRGB_CAPABLE`. When no pixel format advertises that attribute,
the call returns **zero** matching formats; the GUI framework treats that as
fatal and takes the host (Live) down with it.

## What the patch does

- **Advertise it** (`dlls/win32u/opengl.c`, `describe_egl_config`): report
  `framebuffer_srgb_capable` for 8-bit RGB formats when the EGL display supports
  `EGL_KHR_gl_colorspace`. A new `has_EGL_KHR_gl_colorspace` flag on
  `struct egl_platform` (`include/wine/opengl_driver.h`) is set in
  `init_egl_platform()`.
- **Honor it** (`dlls/winex11.drv/opengl.c`, `x11drv_egl_surface_create`): create
  the X11 EGL window surface with `EGL_GL_COLORSPACE_SRGB_KHR` when the extension
  is present, **falling back** to the default colorspace if the driver rejects
  the combination for a given config.

sRGB encoding only actually happens while the app enables `GL_FRAMEBUFFER_SRGB`,
so advertising the capability is inert for apps that do not use it — it just lets
the pixel-format query succeed.

## Why the fallback is not a workaround

`EGL_KHR_gl_colorspace` support is per-driver and, in principle, per-config: a
conformant backend may accept the extension globally yet reject the sRGB
colorspace for a particular `EGLConfig`. Attempting the sRGB surface and
degrading to the default on failure is the standard EGL pattern for an optional
surface attribute, not an environment-specific shim.

## Verification

- Both translation units (and the transitive dependents of the changed header)
  compile warning-clean.
- With the patch, a plugin editor that requires `WGL_FRAMEBUFFER_SRGB_CAPABLE`
  obtains a pixel format and opens instead of crashing the host.
