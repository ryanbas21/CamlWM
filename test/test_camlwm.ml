let () =
  Alcotest.run "camlwm"
    [
      ("Stack_set", Test_stack_set.suite);
      ("Tall",      Test_tall.suite);
    ]
