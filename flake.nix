{
  description = "camlwm — an xmonad-style tiling window manager in OCaml";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Pin to OCaml 5.3. Bump here when we want a newer compiler.
        ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_3;

        # Build/runtime libs we link against from OCaml.
        ocamlDeps = with ocamlPackages; [
          ocaml
          dune_3
          findlib
          ctypes
          ctypes-foreign
        ];

        # Test + dev-only OCaml tooling.
        devTools = with ocamlPackages; [
          alcotest
          ocaml-lsp
          ocamlformat
          utop
          merlin
          odoc
        ];

        # System libraries the FFI bindings link against.
        systemLibs = with pkgs; [
          pkg-config
          libx11
          libx11.dev
        ];

        # Tools for running and exercising the WM.
        runtimeTools = with pkgs; [
          xorgserver        # provides Xephyr binary
          xinit
          xterm             # something to launch inside the nested X server
          xdotool           # simulate input events for smoke tests
        ];

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "camlwm";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = ocamlDeps ++ [ ocamlPackages.alcotest pkgs.pkg-config ];
          buildInputs = [ pkgs.libx11 ];

          buildPhase = ''
            dune build
          '';

          checkPhase = ''
            dune runtest
          '';
          doCheck = true;

          installPhase = ''
            install -Dm755 _build/default/bin/main.exe $out/bin/camlwm
            dune install --prefix=$out --libdir=$out/lib/ocaml 2>/dev/null || true
          '';
        };

        devShells.default = pkgs.mkShell {
          name = "camlwm-dev";

          packages = ocamlDeps ++ devTools ++ systemLibs ++ runtimeTools;

          shellHook = ''
            # Strip any opam-managed bins so we don't shadow nix's
            # ocaml/dune/etc. (happens when the user's shell init puts
            # ~/.opam/default/bin on PATH unconditionally).
            export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "/\.opam/" | paste -sd:)

            echo "camlwm dev shell"
            echo "  ocaml   : $(ocaml -version 2>&1 | head -1)"
            echo "  dune    : $(dune --version)"
            echo
            echo "  build   : dune build"
            echo "  test    : dune runtest"
            echo "  Xephyr  : Xephyr :1 -screen 1024x768 &"
            echo "            DISPLAY=:1 dune exec camlwm"
          '';
        };

        # Convenience formatter target: `nix fmt`
        formatter = pkgs.nixpkgs-fmt;
      });
}
