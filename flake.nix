{
  description = "Nyxt build toolchain (Electron renderer)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin"
      ];
    in {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Shared objects SBCL dlopens through CFFI at build and run time.
          # enchant is nominally optional (spellchecking), but cl-enchant
          # dlopens it at load time, so the build hard-fails without it.
          ffiLibs = with pkgs; [ libfixposix openssl sqlite enchant ];

          # Shared objects Electron dlopens at run time.
          electronLibs = with pkgs; [
            gtk3 nss nspr alsa-lib mesa expat
            xorg.libX11 xorg.libXext xorg.libXrandr xorg.libXdamage
            xorg.libXcomposite xorg.libXtst xorg.libXfixes xorg.libxcb
            atk at-spi2-atk at-spi2-core cups pango cairo glib dbus
          ];
        in {
          default = pkgs.mkShell {
            # Split matters: cffi-grovel shells out to pkg-config for
            # libfixposix's cflags, and nixpkgs' pkg-config setup hook only
            # adds the .pc files of buildInputs (not of nativeBuildInputs).
            nativeBuildInputs = with pkgs; [
              sbcl
              nodejs_20
              # node-gyp (bundled with synchronous-socket) still imports
              # distutils, which PEP 632 removed from the stdlib in Python
              # 3.12. setuptools ships distutils-precedence.pth, which restores
              # the import. A bare python3 fails `npm install` here.
              (python3.withPackages (ps: [ps.setuptools]))
              gnumake
              gcc
              git
              pkg-config
              xclip
            ];

            buildInputs = ffiLibs ++ electronLibs;

            # CFFI resolves libfixposix/openssl/sqlite by soname, so they must be
            # on the loader path — nix has no global /usr/lib to fall back on.
            LD_LIBRARY_PATH =
              nixpkgs.lib.makeLibraryPath (ffiLibs ++ electronLibs);
          };
        });
    };
}
