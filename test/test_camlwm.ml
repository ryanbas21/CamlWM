let () =
  Alcotest.run "camlwm"
    [
      "Stack_set", Test_stack_set.suite;
      "Layout",    Test_layout.suite;
      "Tall",      Test_tall.suite;
      "Wide",      Test_wide.suite;
      "Full",      Test_full.suite;
      "Fullscreen", Test_fullscreen.suite;
      "Keybinding", Test_keybinding.suite;
    ]
