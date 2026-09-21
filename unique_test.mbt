///|
test "finite unique domains fill without rejection even with one attempt" {
  for
    generator in [
      @MoonFixture.IntegerRange(-5, 4),
      Pattern("0123456789", 1),
      Choice([
        Integer(0),
        Integer(1),
        Integer(2),
        Integer(3),
        Integer(4),
        Integer(5),
        Integer(6),
        Integer(7),
        Integer(8),
        Integer(9),
      ]),
    ] {
    let model : @MoonFixture.Model = {
      name: "dense",
      entities: [
        {
          name: "items",
          count: 10,
          fields: [@MoonFixture.Field::new("id", generator, primary=true)],
        },
      ],
    }
    let limits = { ..@MoonFixture.Limits::default(), max_attempts: 1, }
    let data = @MoonFixture.generate(
      model,
      context=@MoonFixture.Context::new(20U, limits~),
    ).unwrap()
    let keys : Map[String, Bool] = Map([])
    for row in data.tables[0].rows {
      keys[row.get("id").unwrap().key()] = true
    }
    assert_eq(keys.length(), 10)
  }
}

///|
test "compiled plan owns nested arrays" {
  let values = [@MoonFixture.Integer(1)]
  let fields = [@MoonFixture.Field::new("id", Choice(values))]
  let model : @MoonFixture.Model = {
    name: "snapshot",
    entities: [{ name: "items", count: 1, fields, }],
  }
  let plan = @MoonFixture.compile(model).unwrap()
  values[0] = Integer(999)
  fields.clear()
  model.entities.clear()
  plan.model().entities.clear()
  assert_eq(
    plan.generate().unwrap().tables[0].rows[0].get("id"),
    Some(Integer(1)),
  )
}
