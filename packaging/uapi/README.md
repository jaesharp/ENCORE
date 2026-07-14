# Vendored Linux UAPI header

`linux/ntsync.h` is copied without modification from the Linux 6.14 UAPI:

https://github.com/torvalds/linux/blob/v6.14/include/uapi/linux/ntsync.h

SHA-256: `006437ee52a3e04f921df77081eb5c21c44c71f598b10ac534c6ef9e78296262`

Its SPDX license identifier is `GPL-2.0 WITH Linux-syscall-note`. The header is
included so Wine can compile optional NTSync support while the release keeps an
Ubuntu 22.04 glibc baseline. It does not make `/dev/ntsync` mandatory at runtime.
The exact upstream license and exception texts are included under `LICENSES/`.
