///|
test "CLI validates numbers commands repeated and incompatible options" {
  for
    args in [
      ["generate"],
      ["generate", "a.json", "--seed", "4294967296"],
      ["generate", "a.json", "--seed", "1", "--seed", "2"],
      ["generate", "a.json", "--format", "csv"],
      ["validate", "a.json"],
      ["replay", "a.json", "--seed", "2"],
      ["generate", "a.json", "--batch-size", "0"],
      ["generate", "a.json", "--wat"],
      ["generate", "a.json", "b.json"],
    ] {
    assert_true(@cli.parse_args(args) is Err(_))
  }
  assert_eq(
    @cli.parse_args(["generate", "-", "--seed", "4294967295"]).unwrap().seed,
    4294967295U,
  )
  assert_eq(@cli.parse_args([]).unwrap().command, "help")
}

///|
test "pure CLI execution returns actionable errors and supports replay" {
  let source = "{\"name\":\"empty\",\"entities\":[]}"
  let options = @cli.parse_args(["generate", "-"]).unwrap()
  assert_eq(@cli.execute(source, options).exit_code, 0)
  assert_eq(@cli.execute("invalid", options).exit_code, 1)
  let manifest = @cli.execute(
    source,
    @cli.parse_args(["manifest", "-"]).unwrap(),
  )
  let replayed = @cli.execute(
    manifest.text,
    @cli.parse_args(["replay", "-"]).unwrap(),
  )
  assert_eq(replayed.text, @cli.execute(source, options).text)
}
