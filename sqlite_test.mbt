///|
test "sqlite binds adversarial text and preserves topological insertion order" {
  let text = "Robert'); DROP TABLE users;--"
  let model : @MoonFixture.Model = {
    name: "db",
    entities: [
      {
        name: "children",
        count: 3,
        fields: [@MoonFixture.Field::new("owner", Reference("users", "id"))],
      },
      {
        name: "users",
        count: 2,
        fields: [
          @MoonFixture.Field::new("id", Sequence(1, 1), primary=true),
          @MoonFixture.Field::new("name", Constant(Text(text))),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  let bundle = @MoonFixture.sqlite_bundle(model, data, batch_size=1).unwrap()
  assert_eq(bundle.batches.length(), 5)
  assert_eq(bundle.batches[0].table, "users")
  assert_true(!bundle.batches[0].sql.contains(text))
  assert_eq(bundle.batches[0].parameters[0][1], Text(text))
  let imported = @MoonFixture.parse_dataset(data.to_json_text()).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, imported).is_valid())
  assert_true(@MoonFixture.sqlite_bundle(model, data, batch_size=0) is Err(_))
}

///|
test "sqlite rejects type erasure in mixed boolean integer columns" {
  let model : @MoonFixture.Model = {
    name: "mixed",
    entities: [
      {
        name: "items",
        count: 2,
        fields: [
          @MoonFixture.Field::new(
            "id",
            Choice([Boolean(true), Integer(1)]),
            primary=true,
          ),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  assert_true(@MoonFixture.sqlite_bundle(model, data) is Err(_))
}

///|
test "dataset parser limits and nested values are rejected" {
  assert_true(@MoonFixture.parse_dataset("{}") is Err(_))
  let data = @MoonFixture.generate({ name: "empty", entities: [], }).unwrap()
  assert_true(
    @MoonFixture.parse_dataset(data.to_json_text(), max_units=1) is Err(_),
  )
  assert_eq(@MoonFixture.parse_dataset(data.to_json_text()).unwrap(), data)
}
