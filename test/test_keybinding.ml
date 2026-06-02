let lock_mask = 0x02 lor 0x10

let strip_locks modifiers = modifiers land lnot lock_mask

let test_no_locks () =
  Alcotest.(check int) "no locks" 0x40 (strip_locks 0x40)

let test_numlock () =
  Alcotest.(check int) "numlock stripped" 0x40 (strip_locks 0x50)

let test_capslock () =
  Alcotest.(check int) "capslock stripped" 0x40 (strip_locks 0x42)

let test_both_locks () =
  Alcotest.(check int) "both stripped" 0x40 (strip_locks 0x52)

let test_shift_preserved () =
  Alcotest.(check int) "shift kept" 0x41 (strip_locks 0x41)

let test_shift_plus_numlock () =
  Alcotest.(check int) "shift+numlock" 0x41 (strip_locks 0x51)

let suite =
  [
    "no locks", `Quick, test_no_locks;
    "numlock", `Quick, test_numlock;
    "capslock", `Quick, test_capslock;
    "both locks", `Quick, test_both_locks;
    "shift preserved", `Quick, test_shift_preserved;
    "shift + numlock", `Quick, test_shift_plus_numlock;
  ]
