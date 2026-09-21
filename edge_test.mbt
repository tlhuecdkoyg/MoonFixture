///|
test "randomized relational models validate across 64 fixed seeds" {
  for seed in 0..<64 {
    let model : @MoonFixture.Model = {
      name: "property",
      entities: [
        {
          name: "parents",
          count: 13,
          fields: [
            @MoonFixture.Field::new("id", IntegerRange(-10, 10), primary=true),
            @MoonFixture.Field::new("price", IntegerRange(1, 99)),
          ],
        },
        {
          name: "children",
          count: 50,
          fields: [
            @MoonFixture.Field::new("parent", Reference("parents", "id")),
            @MoonFixture.Field::new(
              "price",
              Lookup("parent", "parents", "id", "price"),
            ),
            @MoonFixture.Field::new("quantity", IntegerRange(0, 9)),
            @MoonFixture.Field::new("total", Multiply("price", "quantity")),
            @MoonFixture.Field::new(
              "note",
              Pattern("ab中😀", 5),
              null_per_mille=300,
            ),
          ],
        },
      ],
    }
    let context = @MoonFixture.Context::new(seed.reinterpret_as_uint())
    let data = @MoonFixture.generate(model, context~).unwrap()
    assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
    assert_eq(data, @MoonFixture.generate(model, context~).unwrap())
  }
}

///|
test "batch backpressure resumes without duplicating accepted rows" {
  let model : @MoonFixture.Model = {
    name: "batch",
    entities: [
      {
        name: "items",
        count: 7,
        fields: [@MoonFixture.Field::new("id", Sequence(1, 1))],
      },
    ],
  }
  let table = @MoonFixture.generate(model).unwrap().tables[0]
  let out = StringBuilder()
  let mut calls = 0
  let first = table
    .visit_ndjson(2, text => {
      calls += 1
      if calls == 2 {
        false
      } else {
        out.write_string(text)
        true
      }
    })
    .unwrap()
  assert_eq(first.rows_accepted, 2)
  assert_true(!first.completed)
  let rest = table
    .visit_ndjson(
      2,
      text => {
        out.write_string(text)
        true
      },
      offset=first.rows_accepted,
    )
    .unwrap()
  assert_true(rest.completed)
  assert_eq(out.to_string(), table.to_ndjson())
  let csv = StringBuilder()
  table
  .visit_csv(["id"], 3, text => {
    csv.write_string(text)
    true
  })
  .unwrap()
  |> ignore
  assert_eq(csv.to_string(), table.to_csv(["id"]))
  assert_true(table.visit_batches(0, _ => true) is Err(_))
  table
  .visit_batches(2, rows => {
    rows[0].cells.clear()
    true
  })
  .unwrap()
  |> ignore
  assert_eq(table.rows[0].get("id"), Some(Integer(1)))
}

///|
test "resource caps sequence overflow and cyclic entities fail early" {
  let simple : @MoonFixture.Model = {
    name: "limits",
    entities: [
      {
        name: "items",
        count: 3,
        fields: [@MoonFixture.Field::new("id", Sequence(2147483647, 1))],
      },
    ],
  }
  assert_true(@MoonFixture.compile(simple) is Err(_))
  let long_text : @MoonFixture.Model = {
    name: "limits",
    entities: [
      {
        name: "items",
        count: 3,
        fields: [@MoonFixture.Field::new("text", Pattern("a", 10))],
      },
    ],
  }
  let context = @MoonFixture.Context::new(1U, limits={
    ..@MoonFixture.Limits::default(),
    max_text_units: 5,
  })
  assert_true(@MoonFixture.generate(long_text, context~) is Err(_))
  let cyclic : @MoonFixture.Model = {
    name: "cycle",
    entities: [
      {
        name: "a",
        count: 1,
        fields: [
          @MoonFixture.Field::new("id", Sequence(1, 1), primary=true),
          @MoonFixture.Field::new("b", Reference("b", "id")),
        ],
      },
      {
        name: "b",
        count: 1,
        fields: [
          @MoonFixture.Field::new("id", Sequence(1, 1), primary=true),
          @MoonFixture.Field::new("a", Reference("a", "id")),
        ],
      },
    ],
  }
  assert_true(@MoonFixture.compile(cyclic) is Err(_))
}

///|
test "unique dates fill an entire leap-boundary domain with one attempt" {
  let model : @MoonFixture.Model = {
    name: "dates",
    entities: [
      {
        name: "items",
        count: 5,
        fields: [@MoonFixture.Field::new("day", DateOffset(-2, 2), unique=true)],
      },
    ],
  }
  let context = @MoonFixture.Context::new(
    1U,
    reference_time="2000-03-01T00:00:00Z",
    limits={ ..@MoonFixture.Limits::default(), max_attempts: 1, },
  )
  let data = @MoonFixture.generate(model, context~).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  assert_eq(data.tables[0].profile().fields[0].distinct, 5)
}

///|
test "unrelated field insertion preserves independent random streams" {
  let original : @MoonFixture.Model = {
    name: "stable",
    entities: [
      {
        name: "items",
        count: 12,
        fields: [@MoonFixture.Field::new("value", IntegerRange(-50, 50))],
      },
    ],
  }
  let extended = original.snapshot()
  extended.entities[0].fields.push(
    @MoonFixture.Field::new("other", Pattern("abc", 20)),
  )
  let before = @MoonFixture.generate(original).unwrap()
  let after = @MoonFixture.generate(extended).unwrap()
  for index in 0..<12 {
    assert_eq(
      before.tables[0].rows[index].get("value"),
      after.tables[0].rows[index].get("value"),
    )
  }
}
