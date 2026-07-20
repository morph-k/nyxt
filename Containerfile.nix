# Nix-based build toolchain for Nyxt, for use with Podman.
#
#   podman build -t nyxt-nix -f Containerfile.nix .
#   podman run --rm -v "$PWD":/nyxt -w /nyxt nyxt-nix
#
# Nix runs *inside* the container rather than on the host: this machine is
# aarch64-darwin with no Linux builder configured, so the host cannot realise
# aarch64-linux derivations. Running it in the container sidesteps that while
# still pinning the whole toolchain through flake.lock.

FROM docker.io/nixos/nix:2.28.3

RUN mkdir -p /etc/nix && \
    printf 'experimental-features = nix-command flakes\nfilter-syscalls = false\n' \
      >> /etc/nix/nix.conf

WORKDIR /nyxt

# Warm the store at image-build time so `podman run` doesn't refetch the
# toolchain on every invocation. Only the flake files are copied, so edits to
# Nyxt sources don't invalidate this layer.
COPY flake.nix flake.lock* /tmp/toolchain/
# --profile writes a persistent GC root, so the realised toolchain survives in
# the image layer and later runs resolve it without touching the network.
RUN cd /tmp/toolchain && \
    nix flake lock && \
    nix develop --profile /nix/var/nix/profiles/nyxt-toolchain --command true

# The flake ref must be explicit: with no ref, nix develop resolves the flake
# from the working directory, i.e. the bind-mounted repo, where flake.nix is
# untracked by git and therefore invisible to nix.
CMD ["nix", "develop", "/tmp/toolchain", "--command", "make", "all"]
