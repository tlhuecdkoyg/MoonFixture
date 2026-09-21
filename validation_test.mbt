///|
fn shop() -> @MoonFixture.Model {
  {
    name: "shop",
    entities: [
      {
        name: "users",
        count: 3,
        fields: [@MoonFixture.Field::new("id", Sequence(1, 1), primary=true)],
      },
      {
        name: "orders",
        count: 5,
        fields: [
          @MoonFixture.Field::new("id", Sequence(100, 1), primary=true),
          @MoonFixture.Field::new("user_id", Reference("users", "id")),
          @MoonFixture.Field::new("quantity", IntegerRange(1, 10)),
          @MoonFixture.Field::new("price", Constant(Integer(200))),
          @MoonFixture.Field::new("total", Multiply("quantity", "price")),
        ],
      },
    ],
  }
}

///|
test "independent validation detects corrupted foreign and derived values" {
  let model = shop()
  let data = @MoonFixture.generate(model).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  data.tables[1].rows[0].cells[1] = { name: "user_id", value: Integer(999), }
  data.tables[1].rows[0].cells[4] = { name: "total", value: Integer(-1), }
  let report = @MoonFixture.validate_dataset(model, data)
  assert_true(report.issues.any(i => i.code == "foreign_key"))
  assert_true(report.issues.any(i => i.code == "derived_value"))
  assert_eq(report.checked_rows, 8)
  let bounded = @MoonFixture.validate_dataset(model, data, max_issues=1)
  assert_eq(bounded.issues.length(), 1)
  assert_true(bounded.truncated)
}

///|
test "full manifest replay and model serialization preserve output" {
  let model = shop()
  assert_eq(@MoonFixture.parse_model(model.to_json_text()).unwrap(), model)
  let plan = @MoonFixture.compile(
    model,
    context=@MoonFixture.Context::new(4294967295U),
  ).unwrap()
  assert_eq(
    @MoonFixture.replay(plan.replay_json()).unwrap().to_json_text(),
    plan.generate().unwrap().to_json_text(),
  )
  assert_true(@MoonFixture.replay("{}") is Err(_))
}

///|
test "named scenarios and recorded mutations keep originals unchanged" {
  let model = shop()
  let empty = model
    .with_scenario({ name: "empty", overrides: [Count("orders", 0)], })
    .unwrap()
  assert_eq(@MoonFixture.generate(empty).unwrap().tables[1].rows.length(), 0)
  let data = @MoonFixture.generate(model).unwrap()
  let changed = data
    .mutate(model, [
      SetCell("orders", 0, "user_id", Integer(999)),
      DuplicateRow("users", 0),
    ])
    .unwrap()
  assert_true(!changed.report.is_valid())
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  assert_eq(changed.operations.length(), 2)
  assert_true(data.mutate(model, [DeleteRow("orders", 99)]) is Err(_))
}
