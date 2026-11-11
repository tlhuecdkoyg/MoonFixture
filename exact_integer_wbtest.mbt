///|
test "integer decoder accepts programmatic integers and rejects inconsistent repr" {
  assert_eq(integer_value(Json::number(1.0), "number"), 1)
  assert_eq(integer_value(Json::number(-2147483648.0), "number"), -2147483648)
  assert_eq(integer_value(Json::number(100.0, repr="1e2"), "number"), 100)
  assert_eq(integer_value(Json::number(-0.0, repr="0.00"), "number"), 0)
  for
    number in [
      Json::number(1.5),
      Json::number(1.0, repr="2"),
      Json::number(1.0, repr="01"),
    ] {
    let rejected = try {
      let _ = integer_value(number, "number")
      false
    } catch {
      InvalidConfig(_, _) => true
    }
    assert_true(rejected)
  }
}
