///|
fn compatibility_model_for_dates(
  min : Int32,
  max : Int32,
) -> @MoonFixture.Model {
  {
    name: "semantic_combinations",
    entities: [
      {
        name: "children",
        count: 9,
        fields: [
          @MoonFixture.Field::new("total", Multiply("amount", "one")),
          @MoonFixture.Field::new("id", Sequence(100, 1), primary=true),
          @MoonFixture.Field::new(
            "description",
            Concat(["tag", "day", "total"], "|"),
          ),
          @MoonFixture.Field::new(
            "tag",
            Lookup("parent", "parents", "id", "tag"),
          ),
          @MoonFixture.Field::new(
            "day",
            Lookup("parent", "parents", "id", "day"),
          ),
          @MoonFixture.Field::new(
            "amount",
            Lookup("parent", "parents", "id", "amount"),
          ),
          @MoonFixture.Field::new("parent", Reference("parents", "id")),
          @MoonFixture.Field::new("one", Constant(Integer(1))),
          @MoonFixture.Field::new(
            "note",
            WeightedChoice([(Text("a,\"中\n🙂"), 1), (Text(""), 3)]),
            null_per_mille=250,
          ),
          @MoonFixture.Field::new("copy", Copy("note")),
        ],
      },
      {
        name: "parents",
        count: 5,
        fields: [
          @MoonFixture.Field::new("copied_day", Copy("day")),
          @MoonFixture.Field::new("id", Sequence(-2147483648, 1), primary=true),
          @MoonFixture.Field::new("day", DateOffset(min, max), unique=true),
          @MoonFixture.Field::new(
            "tag",
            Pattern("中🙂,\n\"", 2),
            unique=true,
          ),
          @MoonFixture.Field::new(
            "amount",
            IntegerRange(-2147483648, -2147483644),
          ),
        ],
      },
    ],
  }
}

///|
fn check_compatibility_combination(
  reference : String,
  expected : Array[String],
  min : Int32,
  max : Int32,
  seed : UInt32,
) -> Unit raise {
  let model = compatibility_model_for_dates(min, max)
  let context = @MoonFixture.Context::new(seed, reference_time=reference)
  let plan = @MoonFixture.compile(model, context~).unwrap()
  let data = plan.generate().unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  assert_eq(@MoonFixture.replay(plan.replay_json()).unwrap(), data)
  assert_eq(plan.generate().unwrap(), data)
  assert_eq(@MoonFixture.parse_model(model.to_json_text()).unwrap(), model)
  let imported = @MoonFixture.parse_dataset(data.to_json_text()).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, imported).is_valid())
  assert_true(
    @MoonFixture.compare_datasets(model, data, imported).unwrap().equal(),
  )
  let parents = data.table("parents").unwrap()
  let days : Map[String, Bool] = Map([])
  for row in parents.rows {
    assert_eq(row.get("copied_day"), row.get("day"))
    match row.get("day") {
      Some(Text(day)) => {
        assert_true(expected.contains(day))
        days[day] = true
      }
      _ => fail("Date field must be text")
    }
  }
  assert_eq(days.length(), 5)
  let children = data.table("children").unwrap()
  for row in children.rows {
    assert_eq(row.get("total"), row.get("amount"))
    assert_eq(row.get("copy"), row.get("note"))
    let parent_rows = parents.where_equal("id", row.get("parent").unwrap()).rows
    assert_eq(parent_rows.length(), 1)
    assert_eq(parent_rows[0].get("day"), row.get("day"))
    assert_eq(parent_rows[0].get("tag"), row.get("tag"))
    assert_eq(parent_rows[0].get("amount"), row.get("amount"))
  }
  for table in data.tables {
    let ndjson = StringBuilder()
    table
    .visit_ndjson(2, text => {
      ndjson.write_string(text)
      true
    })
    .unwrap()
    |> ignore
    assert_eq(ndjson.to_string(), table.to_ndjson())
    let columns = model.entity(table.name).unwrap().fields.map(field => {
      field.name
    })
    let csv = StringBuilder()
    let mut calls = 0
    let first = table
      .visit_csv(columns, 2, text => {
        calls += 1
        if calls == 2 {
          false
        } else {
          csv.write_string(text)
          true
        }
      })
      .unwrap()
    let rest = table
      .visit_csv(
        columns,
        2,
        text => {
          csv.write_string(text)
          true
        },
        offset=first.rows_accepted,
      )
      .unwrap()
    assert_true(rest.completed)
    assert_eq(csv.to_string(), table.to_csv(columns))
  }
  assert_true(@MoonFixture.sqlite_bundle(model, data, batch_size=2) is Ok(_))
  let changed = data
    .mutate(model, [SetCell("children", 0, "total", Integer(0))])
    .unwrap()
  assert_false(changed.report.is_valid())
  assert_true(changed.report.issues.any(issue => issue.code == "derived_value"))
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  let empty = model
    .with_scenario({ name: "empty", overrides: [Count("children", 0)], })
    .unwrap()
  let empty_data = @MoonFixture.generate(empty, context~).unwrap()
  assert_eq(empty_data.table("children").unwrap().rows.length(), 0)
  assert_true(@MoonFixture.validate_dataset(empty, empty_data).is_valid())
  let nullable = model
    .with_scenario({
      name: "nullable",
      overrides: [Nullable("children", "note", 1000)],
    })
    .unwrap()
  let null_data = @MoonFixture.generate(nullable, context~).unwrap()
  assert_true(@MoonFixture.validate_dataset(nullable, null_data).is_valid())
  for row in null_data.table("children").unwrap().rows {
    assert_eq(row.get("note"), Some(Null))
    assert_eq(row.get("copy"), Some(Null))
  }
}

///|
test "maintained SDK semantic compatibility matrix" {
  let cases : Array[(String, Array[String], Int32, Int32)] = [
    (
      "0001-01-01T00:00:00Z",
      ["0001-01-01", "0001-01-02", "0001-01-03", "0001-01-04", "0001-01-05"],
      0,
      4,
    ),
    (
      "9999-12-31T23:59:59Z",
      ["9999-12-27", "9999-12-28", "9999-12-29", "9999-12-30", "9999-12-31"],
      -4,
      0,
    ),
    (
      "1900-03-01T00:00:00Z",
      ["1900-02-27", "1900-02-28", "1900-03-01", "1900-03-02", "1900-03-03"],
      -2,
      2,
    ),
    (
      "2000-03-01T00:00:00Z",
      ["2000-02-28", "2000-02-29", "2000-03-01", "2000-03-02", "2000-03-03"],
      -2,
      2,
    ),
    (
      "2100-03-01T00:00:00Z",
      ["2100-02-27", "2100-02-28", "2100-03-01", "2100-03-02", "2100-03-03"],
      -2,
      2,
    ),
    (
      "2026-12-31T00:00:00Z",
      ["2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"],
      -2,
      2,
    ),
  ]
  for (reference, expected, min, max) in cases {
    for seed in 1..<4 {
      check_compatibility_combination(
        reference,
        expected,
        min,
        max,
        seed.reinterpret_as_uint(),
      )
    }
  }
}
