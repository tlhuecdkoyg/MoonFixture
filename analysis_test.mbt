///|
test "profiles preserve typed distinct values and Unicode lengths" {
  let table : @MoonFixture.Table = {
    name: "items",
    rows: [
      {
        cells: [
          { name: "value", value: Integer(1), },
          { name: "text", value: Text("😀中"), },
        ],
      },
      {
        cells: [
          { name: "value", value: Boolean(true), },
          { name: "text", value: Null, },
        ],
      },
      { cells: [{ name: "value", value: Text("1"), }], },
    ],
  }
  let profile = table.profile()
  assert_eq(profile.rows, 3)
  assert_eq(profile.fields[0].name, "text")
  assert_eq(profile.fields[0].max_text_length, Some(2))
  assert_eq(profile.fields[0].missing, 1)
  assert_eq(profile.fields[1].distinct, 3)
  assert_eq(profile.fields[1].sum_integer, 1L)
}

///|
test "keyed comparison ignores row order but distinguishes missing and null" {
  let model : @MoonFixture.Model = {
    name: "diff",
    entities: [
      {
        name: "items",
        count: 2,
        fields: [
          @MoonFixture.Field::new("id", Sequence(1, 1), primary=true),
          @MoonFixture.Field::new("note", Constant(Null)),
        ],
      },
    ],
  }
  let before = @MoonFixture.generate(model).unwrap()
  let after = before.snapshot()
  let first = after.tables[0].rows[0]
  after.tables[0].rows[0] = after.tables[0].rows[1]
  after.tables[0].rows[1] = first
  assert_true(
    @MoonFixture.compare_datasets(model, before, after).unwrap().equal(),
  )
  after.tables[0].rows[0].cells.pop() |> ignore
  let result = @MoonFixture.compare_datasets(model, before, after).unwrap()
  assert_eq(result.differences.length(), 1)
  assert_eq(result.differences[0].before, Some(Null))
  assert_eq(result.differences[0].after, None)
}

///|
test "joins paging projection grouping and fixture expectations" {
  let model : @MoonFixture.Model = {
    name: "oracle",
    entities: [
      {
        name: "parents",
        count: 2,
        fields: [@MoonFixture.Field::new("id", Sequence(1, 1), primary=true)],
      },
      {
        name: "children",
        count: 4,
        fields: [
          @MoonFixture.Field::new("parent_id", Reference("parents", "id")),
          @MoonFixture.Field::new("amount", Constant(Integer(3))),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  let parent = data.table("parents").unwrap()
  let child = data.table("children").unwrap()
  let joined = child
    .join_parent(parent, "parent_id", "id", ["id"], prefix="owner_")
    .unwrap()
  assert_eq(joined.rows.length(), 4)
  for row in joined.rows {
    assert_eq(row.get("parent_id"), row.get("owner_id"))
  }
  assert_eq(child.page(3, 10).unwrap().rows.length(), 1)
  assert_eq(child.page(99, 10).unwrap().rows.length(), 0)
  assert_true(child.page(-1, 1) is Err(_))
  assert_eq(child.project(["amount"]).unwrap().rows[0].cells.length(), 1)
  let groups = child.group_sum("parent_id", "amount").unwrap()
  let mut sum = 0L
  for group in groups {
    sum += group.sum
  }
  assert_eq(sum, 12L)
  let report = @MoonFixture.check_expectations(data, [
    RowCount("children", 4, 4),
    SumEquals("children", "amount", 12L),
    IntegerBounds("children", "amount", 1, 10),
    RelatedCount("children", "parent_id", "parents", "id", 0, 4),
  ])
  assert_true(report.is_valid())
  assert_true(
    !@MoonFixture.check_expectations(data, [
      SumEquals("children", "amount", 999L),
    ]).is_valid(),
  )
  assert_eq(@MoonFixture.compile(model).unwrap().report().cells, 10L)
}

///|
test "weighted choices reject bad weights and replay mixed domains" {
  let model : @MoonFixture.Model = {
    name: "weights",
    entities: [
      {
        name: "items",
        count: 100,
        fields: [
          @MoonFixture.Field::new(
            "priority",
            WeightedChoice([(Text("low"), 1), (Text("high"), 9)]),
          ),
        ],
      },
    ],
  }
  let plan = @MoonFixture.compile(model).unwrap()
  let data = plan.generate().unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  assert_eq(@MoonFixture.replay(plan.replay_json()).unwrap(), data)
  assert_true(
    data.tables[0].where_equal("priority", Text("high")).rows.length() > 50,
  )
  let bad = model.with_scenario({
    name: "bad",
    overrides: [
      Generator("items", "priority", WeightedChoice([(Integer(1), 0)])),
    ],
  })
  assert_true(bad is Err(_))
}

///|
test "null unique values and inherited nulls remain valid" {
  let model : @MoonFixture.Model = {
    name: "nulls",
    entities: [
      {
        name: "items",
        count: 5,
        fields: [
          @MoonFixture.Field::new("x", Constant(Null), unique=true),
          @MoonFixture.Field::new("y", Copy("x")),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
}

///|
test "JSON depth guard ignores quoted delimiters and rejects deep input" {
  let out = StringBuilder()
  for _ in 0..<65 {
    out.write_char('[')
  }
  for _ in 0..<65 {
    out.write_char(']')
  }
  match @MoonFixture.parse_model(out.to_string()) {
    Err(error) => assert_eq(error.code, "nesting_limit")
    Ok(_) => fail("Expected bounded nesting")
  }
}
