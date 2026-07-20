# Build toolchain for compiling Nyxt (Electron renderer) under Podman.
#
#   podman build -t nyxt-build -f Containerfile .
#   podman run --rm -v "$PWD":/nyxt -w /nyxt nyxt-build make all
#
# The repo is bind-mounted rather than COPYed so the compiled binary and the
# _build submodule tree persist on the host and rebuilds stay incremental.

FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# Toolchain: SBCL + the Lisp FFI deps, plus node/node-gyp for cl-electron's
# native modules (nan is compiled from source by electron-builder).
RUN apt-get update && apt-get install -y --no-install-recommends \
      sbcl \
      git \
      make \
      curl \
      ca-certificates \
      build-essential \
      python3 \
      # Debian trixie ships Python 3.13, which dropped distutils (PEP 632).
      # The node-gyp bundled with synchronous-socket still imports it;
      # setuptools ships distutils-precedence.pth, which restores the import.
      python3-setuptools \
      nodejs \
      npm \
      libfixposix-dev \
      libssl-dev \
      libsqlite3-dev \
      # Nominally optional (spellchecking), but cl-enchant dlopens
      # libenchant-2 at load time, so the build hard-fails without it.
      # Must be -dev: CFFI asks for the unversioned libenchant-2.so, and the
      # runtime package ships only libenchant-2.so.2.
      libenchant-2-dev \
    && rm -rf /var/lib/apt/lists/*

# Shared objects Electron dylinks at runtime. Not needed to produce the binary,
# but without them the result cannot actually be launched.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgtk-3-0 \
      libnss3 \
      libasound2 \
      libgbm1 \
      libxss1 \
      libxtst6 \
      libxrandr2 \
      libxdamage1 \
      libxcomposite1 \
      libatk1.0-0 \
      libatk-bridge2.0-0 \
      libcups2 \
      libpango-1.0-0 \
      libcairo2 \
      xclip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /nyxt
CMD ["make", "all"]
