///|
test "Gregorian leap boundaries and full supported range" {
  assert_eq(
    @MoonFixture.parse_date("2000-02-28")
    .unwrap()
    .add_days(1)
    .unwrap()
    .to_string(),
    "2000-02-29",
  )
  assert_eq(
    @MoonFixture.parse_date("1900-02-28")
    .unwrap()
    .add_days(1)
    .unwrap()
    .to_string(),
    "1900-03-01",
  )
  assert_eq(
    @MoonFixture.parse_date("2026-01-01")
    .unwrap()
    .add_days(-1)
    .unwrap()
    .to_string(),
    "2025-12-31",
  )
  assert_true(@MoonFixture.parse_date("2026-02-29") is Err(_))
  assert_true(
    @MoonFixture.parse_date("0001-01-01").unwrap().add_days(-1) is Err(_),
  )
  assert_true(
    @MoonFixture.parse_date("9999-12-31").unwrap().add_days(1) is Err(_),
  )
  let first = @MoonFixture.parse_date("0001-01-01").unwrap()
  for offset in [0, 365, 1460, 100000, 3652058] {
    assert_eq(first.add_days(offset).unwrap().ordinal().unwrap(), offset)
  }
}

///|
test "date generation uses explicit reference time and survives replay" {
  let model : @MoonFixture.Model = {
    name: "dates",
    entities: [
      {
        name: "events",
        count: 20,
        fields: [@MoonFixture.Field::new("day", DateOffset(-2, 2))],
      },
    ],
  }
  let plan = @MoonFixture.compile(
    model,
    context=@MoonFixture.Context::new(
      42U,
      reference_time="2000-03-01T23:59:59Z",
    ),
  ).unwrap()
  let data = plan.generate().unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  assert_eq(@MoonFixture.replay(plan.replay_json()).unwrap(), data)
  assert_true(
    @MoonFixture.compile(
      model,
      context=@MoonFixture.Context::new(1U, reference_time="today"),
    )
    is Err(_),
  )
}
