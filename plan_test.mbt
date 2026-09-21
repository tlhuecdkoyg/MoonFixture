///|
test "dependency plan orders parent tables and rejects cycles" {
  let model : @MoonFixture.Model = {
    name: "demo",
    entities: [
      {
        name: "orders",
        count: 5,
        fields: [@MoonFixture.Field::new("user", Reference("users", "id"))],
      },
      {
        name: "users",
        count: 3,
        fields: [@MoonFixture.Field::new("id", Sequence(1, 1), primary=true)],
      },
    ],
  }
  let plan = @MoonFixture.compile(model).unwrap()
  assert_eq(plan.entity_names(), ["users", "orders"])
  let data = plan.generate().unwrap()
  assert_eq(data.table("orders").unwrap().rows.length(), 5)
  let bad : @MoonFixture.Model = {
    name: "cycle",
    entities: [
      {
        name: "a",
        count: 1,
        fields: [
          @MoonFixture.Field::new("x", Copy("y")),
          @MoonFixture.Field::new("y", Copy("x")),
        ],
      },
    ],
  }
  assert_true(@MoonFixture.compile(bad) is Err(_))
}

///|
test "unique domain exhaustion is distinguished from attempt exhaustion" {
  let model : @MoonFixture.Model = {
    name: "unique",
    entities: [
      {
        name: "a",
        count: 3,
        fields: [@MoonFixture.Field::new("id", BooleanChance(500), unique=true)],
      },
    ],
  }
  match @MoonFixture.generate(model) {
    Err(errors) => assert_eq(errors[0].code, "unsatisfiable_unique")
    Ok(_) => fail("Expected finite-domain failure")
  }
}

///|
test "derived values follow dependencies even when declared before operands" {
  let model : @MoonFixture.Model = {
    name: "derived",
    entities: [
      {
        name: "a",
        count: 2,
        fields: [
          @MoonFixture.Field::new("total", Multiply("quantity", "price")),
          @MoonFixture.Field::new("quantity", Constant(Integer(3))),
          @MoonFixture.Field::new("price", Constant(Integer(50))),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  assert_eq(data.tables[0].rows[0].get("total"), Some(Integer(150)))
  assert_eq(data, @MoonFixture.generate(model).unwrap())
}
