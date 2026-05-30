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
          xorg.libX11
          xorg.libX11.dev
        ];

        # Tools for running and exercising the WM.
        runtimeTools = with pkgs; [
          xorg.xorgserver   # provides Xephyr binary
          xorg.xinit
          xterm             # something to launch inside the nested X server
          xdotool           # simulate input events for smoke tests
        ];

      in {
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
