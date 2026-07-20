# Building Nyxt on macOS (Apple Silicon)

A fork of [Nyxt](https://github.com/atlas-engineer/nyxt) carrying a reproducible
build for Apple Silicon Macs. Upstream's own documentation is in
[README.org](README.org); this file only covers building.

Nyxt's macOS download link points at a Docker image that installs a prebuilt
2.2.4 `amd64` `.deb` and compiles nothing. This builds current Nyxt (4.x,
Electron renderer) from source instead.

Both paths produce a **Linux** binary. Nyxt does not build natively on macOS
here, and it cannot be cross-compiled — see [Why not cross-compile?](#why-not-cross-compile).

## Prerequisites

- [Nix](https://nixos.org/download/)
- [Podman](https://podman.io/) (for the container path)

The Podman VM needs more than its default memory, because the makefile asks
SBCL for a 3 GiB dynamic space:

```bash
podman machine init --memory 8192 --cpus 6 --disk-size 100
podman machine start
```

## Get the source

```bash
git clone --recurse-submodules https://github.com/morph-k/nyxt
cd nyxt
```

If submodule init fails on `closer-mop`, see [Known issues](#known-issues).

## Build with Podman

```bash
podman build -t nyxt-nix -f Containerfile.nix .
podman run --rm -v "$PWD":/nyxt -w /nyxt nyxt-nix
./nyxt --version   # Nyxt version 4
```

Nix runs *inside* the container rather than on the host: an `aarch64-darwin`
machine with no Linux builder cannot realise `aarch64-linux` derivations.
Running it in the container pins the whole toolchain through `flake.lock`
without needing a builder VM.

`Containerfile` (plain Debian) is kept as a fallback. It is **not** verified
end to end.

## Build on a Linux VM

If you already have an `aarch64-linux` machine or VM:

```bash
nix develop --command make all
```

`flake.nix` provides the pinned toolchain (SBCL, Node, and the libraries SBCL
dlopens through CFFI).

## Why not cross-compile?

Nix cross-compilation cannot produce this binary, for a reason no toolchain
configuration gets around.

SBCL does not link executables the way a C compiler does. It produces them with
[`save-lisp-and-die`](https://www.sbcl.org/manual/#Saving-a-Core-Image), which
dumps *the currently running Lisp image* and fuses it with the runtime.
Building Nyxt therefore means loading Nyxt into a live SBCL and dumping that
process — so producing a Linux binary requires *executing* a Linux SBCL.

Cross-compilation generates code for a machine you are not running on, which is
precisely what this build cannot do. A container or VM supplies the Linux
execution environment; a cross-compiler does not. (nix.dev also
[states](https://nix.dev/tutorials/cross-compilation.html) that Darwin can only
cross-compile to Darwin.)

SBCL *does* have a cross-compilation story for porting to new architectures,
but even that syncs to a running target to finish the build.

## Known issues

**`closer-mop` submodule is dead upstream.** `.gitmodules` points at
`github.com/pcostanza/closer-mop`, which now 404s, so a recursive submodule
clone fails. No git mirror carries the pinned commit
`7b86f2add029208ebc74ec6a41c2ccfd3c382dbc`. Recover the exact tree from
[Software Heritage](https://archive.softwareheritage.org/):

```bash
curl -sL "https://archive.softwareheritage.org/api/1/vault/flat/\
swh:1:dir:a586e6df8e167a401cc5632a03cd040ee896aa81/raw/" -o cmop.tar.gz
mkdir -p _build/closer-mop
tar xzf cmop.tar.gz --strip-components=1 -C _build/closer-mop
```

Verify with `git -C _build/closer-mop write-tree`; it must print
`a586e6df8e167a401cc5632a03cd040ee896aa81`, the tree of the pinned commit.

**Submodules can report clean while being empty.** If a `submodule update` run
aborts partway, the remaining submodules are cloned but never checked out.
`git submodule status` only compares recorded commits, so it reports them as
fine, and the failure surfaces much later as an ASDF error such as
`Component ASDF/USER::CALISPEL not found`. Fix with:

```bash
git submodule update --init --recursive --force
```

**enchant is required despite being documented as optional.** `cl-enchant`
dlopens `libenchant-2` at load time, so the build fails without it. On Debian
it must be the `-dev` package: CFFI asks for the unversioned
`libenchant-2.so`, and the runtime package ships only `libenchant-2.so.2`.

## Running it

Building and running are separate problems. `./nyxt --version` succeeds long
before the browser can actually launch, because it never starts Electron — so
a green build says nothing about whether the GUI works.

### On NixOS: nix-ld is required

npm ships Electron as a **generic-Linux prebuilt**, whose ELF interpreter is
`/lib/ld-linux-aarch64.so.1`. NixOS has no such loader, so launching fails
with:

```
Could not start dynamically linked executable: .../electron/dist/electron
NixOS cannot run dynamically linked executables intended for generic
linux environments out of the box.
```

`programs.nix-ld` supplies a loader and a library path. Chromium's set is
large; note that `libgbm.so.1` is **not** in `mesa` any more and must be listed
separately as `libgbm`, or you get
`libgbm.so.1: cannot open shared object file`.

A working configuration is in
[morph-k/nix](https://github.com/morph-k/nix/blob/main/modules/utm-builder.nix).

### Displaying it from macOS

No XQuartz needed. Run a headless X server in the guest and view it over VNC
through an SSH tunnel:

```bash
# in the guest
Xvfb :99 -screen 0 1600x1000x24 &
x11vnc -display :99 -rfbport 5999 -localhost -forever -nopw &
DISPLAY=:99 ./nyxt --electron-opts='--no-sandbox --disable-gpu --disable-dev-shm-usage'

# on macOS
ssh -N -L 5999:127.0.0.1:5999 user@guest
open vnc://127.0.0.1:5999
```

Note the `=` in `--electron-opts=...`. Nyxt's option parser reads a
space-separated value beginning with `--` as the *next* flag, so
`--electron-opts '--no-sandbox …'` fails with `missing arg for option`.

`--disable-gpu` is what silences
`ANGLE Display::initialize error 12289: GLX is not present`. Chromium
software-renders fine on a headless aarch64 guest. Keep `-localhost` and tunnel
over SSH rather than exposing the VNC port.

If a relaunch produces no window while logging *"Nyxt started, opening new
window"*, an earlier instance still holds `/run/user/$UID/nyxt/nyxt.socket` and
the new process delegated to it and exited. The tell is a missing "Listening to
socket" line. Kill the old process and remove the socket directory.

Verified end to end this way: Nyxt 4 rendering under Xvfb on aarch64 NixOS,
viewed from macOS, no XQuartz involved.
