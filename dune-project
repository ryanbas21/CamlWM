(lang dune 3.19)

(name camlwm)

(generate_opam_files true)

(source
 (github batman/camlwm))

(authors "batman")

(maintainers "batman")

(license MIT)

(package
 (name camlwm)
 (synopsis "An xmonad-style tiling window manager for X11, written in OCaml")
 (description
  "camlwm is a dynamic tiling window manager modelled on xmonad. \
   It uses Xlib via ctypes, exposes a compiled OCaml configuration model, \
   and is structured around a pure StackSet core plus functorised layouts.")
 (depends
  (ocaml
   (>= 5.2))
  (dune
   (>= 3.19))
  (ctypes
   (>= 0.23))
  (ctypes-foreign
   (>= 0.23))
  conf-libX11
  (alcotest :with-test)))
