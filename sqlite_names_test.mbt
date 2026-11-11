///|
test "SQLite export rejects case collisions without restricting JSON models" {
  let models : Array[@MoonFixture.Model] = [
    {
      name: "table_names",
      entities: [
        {
          name: "Users",
          count: 1,
          fields: [@MoonFixture.Field::new("id", Constant(Integer(1)))],
        },
        {
          name: "users",
          count: 1,
          fields: [@MoonFixture.Field::new("id", Constant(Integer(2)))],
        },
      ],
    },
    {
      name: "column_names",
      entities: [
        {
          name: "records",
          count: 1,
          fields: [
            @MoonFixture.Field::new("id", Constant(Integer(1))),
            @MoonFixture.Field::new("ID", Constant(Integer(2))),
          ],
        },
      ],
    },
  ]
  for index in 0..<models.length() {
    let model = models[index]
    let parsed = @MoonFixture.parse_model(model.to_json_text()).unwrap()
    let data = @MoonFixture.generate(parsed).unwrap()
    assert_true(@MoonFixture.validate_dataset(parsed, data).is_valid())
    match @MoonFixture.sqlite_bundle(parsed, data) {
      Err(issues) =>
        assert_eq(
          issues[0].code,
          if index == 0 {
            "sqlite_duplicate_table"
          } else {
            "sqlite_duplicate_column"
          },
        )
      Ok(_) => fail("SQLite must reject names that collide ignoring ASCII case")
    }
  }
}

///|
test "SQLite export reserves only engine table prefix and keeps valid references" {
  for name in ["sqlite_records", "SQLITE_records", "Sqlite_"] {
    let model : @MoonFixture.Model = {
      name: "reserved",
      entities: [
        {
          name,
          count: 1,
          fields: [@MoonFixture.Field::new("id", Constant(Integer(1)))],
        },
      ],
    }
    let data = @MoonFixture.generate(model).unwrap()
    assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
    match @MoonFixture.sqlite_bundle(model, data) {
      Err(issues) => assert_eq(issues[0].code, "sqlite_reserved_name")
      Ok(_) => fail("sqlite_ table prefix belongs to SQLite")
    }
  }
  let model : @MoonFixture.Model = {
    name: "valid_names",
    entities: [
      {
        name: "sqliteX",
        count: 1,
        fields: [
          @MoonFixture.Field::new("sqlite_id", Sequence(1, 1), primary=true),
        ],
      },
      {
        name: "Children",
        count: 2,
        fields: [
          @MoonFixture.Field::new("Parent", Reference("sqliteX", "sqlite_id")),
          @MoonFixture.Field::new("Nullable", Constant(Null), unique=true),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  let bundle = @MoonFixture.sqlite_bundle(model, data).unwrap()
  assert_true(
    bundle.schema[1].contains("REFERENCES \"sqliteX\" (\"sqlite_id\")"),
  )
  assert_eq(bundle.batches[1].parameters[0][1], Null)
}
