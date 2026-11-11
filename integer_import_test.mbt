///|
fn model_with_integer_token(token : String) -> String {
  "{\"name\":\"integer\",\"entities\":[{\"name\":\"items\",\"count\":1,\"fields\":[{\"name\":\"id\",\"generator\":{\"kind\":\"constant\",\"value\":" +
  token +
  "}}]}]}"
}

///|
test "integer model import accepts exact decimal and exponent integers" {
  for
    (token, expected) in [
      ("1.0", 1),
      ("1e2", 100),
      ("100e-2", 1),
      ("0.00100e3", 1),
      ("-0.000e-999999999999999999999", 0),
      ("0e999999999999999999999999999", 0),
      ("1e00000000000000000000000000", 1),
      ("2147483647.000", 2147483647),
      ("-2147483648.0", -2147483648),
      ("214748364700000000000e-11", 2147483647),
    ] {
    let model = @MoonFixture.parse_model(model_with_integer_token(token)).unwrap()
    let data = @MoonFixture.generate(model).unwrap()
    assert_eq(data.tables[0].rows[0].get("id"), Some(Integer(expected)))
  }
}

///|
test "integer imports reject rounded fractions malformed numbers and huge exponents" {
  for
    token in [
      "1e-400", "-1e-400", "1.0000000000000001", "2147483647.00000001", "-2147483648.00000001",
      "0.00001", "2147483648", "-2147483649", "1e999999999999999999999999999", "1e-999999999999999999999999999",
      "01", "+1", "1.", "1e", ".1",
    ] {
    assert_true(
      @MoonFixture.parse_model(model_with_integer_token(token)) is Err(_),
    )
  }
  let source = model_with_integer_token("1").replace_all(
    old="\"count\":1",
    new="\"count\":1e-400",
  )
  assert_true(@MoonFixture.parse_model(source) is Err(_))
  let zeros = StringBuilder()
  for _ in 0..<2048 {
    zeros.write_char('0')
  }
  let suffix = zeros.to_string()
  assert_true(
    @MoonFixture.parse_model(
      model_with_integer_token("1e" + suffix + "99999999999999999999"),
    )
    is Err(_),
  )
  let exact = @MoonFixture.parse_model(
    model_with_integer_token("1" + suffix + "e-2048"),
  ).unwrap()
  assert_eq(
    @MoonFixture.generate(exact).unwrap().tables[0].rows[0].get("id"),
    Some(Integer(1)),
  )
}

///|
test "dataset and replay integer imports preserve exact number text" {
  let model = @MoonFixture.parse_model(model_with_integer_token("1")).unwrap()
  let plan = @MoonFixture.compile(model).unwrap()
  let text = plan.generate().unwrap().to_json_text()
  for token in ["1e-400", "1.0000000000000001", "2147483647.00000001"] {
    assert_true(
      @MoonFixture.parse_dataset(
        text.replace_all(old="\"id\":1", new="\"id\":" + token),
      )
      is Err(_),
    )
  }
  let valid = @MoonFixture.parse_dataset(
    text.replace_all(old="\"id\":1", new="\"id\":1.00e0"),
  ).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, valid).is_valid())
  let manifest = plan.replay_json()
  assert_true(
    @MoonFixture.replay(
      manifest.replace_all(
        old="\"count\":1",
        new="\"count\":1.0000000000000001",
      ),
    )
    is Err(_),
  )
  assert_true(
    @MoonFixture.replay(
      manifest.replace_all(
        old="\"max_attempts\":256",
        new="\"max_attempts\":256.0000000000000001",
      ),
    )
    is Err(_),
  )
}
