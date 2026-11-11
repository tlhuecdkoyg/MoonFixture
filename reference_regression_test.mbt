///|
test "unique references reject null parent keys like ordinary references" {
  for
    parent_generator in [
      @MoonFixture.Generator::Constant(Null),
      Copy("nullable"),
    ] {
    for unique in [false, true] {
      let model : @MoonFixture.Model = {
        name: "null_reference",
        entities: [
          {
            name: "parents",
            count: 1,
            fields: [
              @MoonFixture.Field::new("nullable", Constant(Null)),
              @MoonFixture.Field::new("key", parent_generator, unique=true),
            ],
          },
          {
            name: "children",
            count: 1,
            fields: [
              @MoonFixture.Field::new(
                "ref",
                Reference("parents", "key"),
                unique~,
              ),
            ],
          },
        ],
      }
      let plan = @MoonFixture.compile(model).unwrap()
      match plan.generate() {
        Err(error) => assert_eq(error.code, "invalid_reference_key")
        Ok(_) => fail("A non-null Reference must not emit a null parent key")
      }
    }
  }
}

///|
test "unique reference repair preserves nullable children and dense valid domains" {
  let model : @MoonFixture.Model = {
    name: "nullable_reference",
    entities: [
      {
        name: "parents",
        count: 1,
        fields: [@MoonFixture.Field::new("key", Constant(Null), unique=true)],
      },
      {
        name: "children",
        count: 3,
        fields: [
          @MoonFixture.Field::new(
            "ref",
            Reference("parents", "key"),
            unique=true,
            null_per_mille=1000,
          ),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(model).unwrap()
  assert_true(@MoonFixture.validate_dataset(model, data).is_valid())
  for row in data.table("children").unwrap().rows {
    assert_eq(row.get("ref"), Some(Null))
  }
  let valid : @MoonFixture.Model = {
    name: "dense_reference",
    entities: [
      {
        name: "parents",
        count: 8,
        fields: [@MoonFixture.Field::new("key", Sequence(1, 1), primary=true)],
      },
      {
        name: "children",
        count: 8,
        fields: [
          @MoonFixture.Field::new(
            "ref",
            Reference("parents", "key"),
            unique=true,
          ),
        ],
      },
    ],
  }
  let data = @MoonFixture.generate(
    valid,
    context=@MoonFixture.Context::new(1U, limits={
      ..@MoonFixture.Limits::default(),
      max_attempts: 1,
    }),
  ).unwrap()
  assert_true(@MoonFixture.validate_dataset(valid, data).is_valid())
  assert_eq(data.table("children").unwrap().profile().fields[0].distinct, 8)
}
