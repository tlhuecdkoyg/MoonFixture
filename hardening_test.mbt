///|
test "large derived text is rejected before concatenation allocation" {
  let model : @MoonFixture.Model = {
    name: "budget",
    entities: [
      {
        name: "items",
        count: 1,
        fields: [
          @MoonFixture.Field::new("a", Constant(Text("0123456789"))),
          @MoonFixture.Field::new("b", Concat(["a", "a", "a"], "")),
        ],
      },
    ],
  }
  let context = @MoonFixture.Context::new(1U, limits={
    ..@MoonFixture.Limits::default(),
    max_text_units: 20,
  })
  match @MoonFixture.generate(model, context~) {
    Err(issues) => assert_eq(issues[0].code, "text_limit")
    Ok(_) => fail("Expected concatenation budget failure")
  }
}

///|
test "left join produces null projection and refuses ambiguous parent keys" {
  let child : @MoonFixture.Table = {
    name: "child",
    rows: [{ cells: [{ name: "owner", value: Integer(9), }], }],
  }
  let parent : @MoonFixture.Table = {
    name: "parent",
    rows: [{ cells: [{ name: "id", value: Integer(1), }], }],
  }
  let result = child
    .join_parent(parent, "owner", "id", ["id"], mode=Left)
    .unwrap()
  assert_eq(result.rows[0].get("parent_id"), Some(Null))
  assert_eq(
    child.join_parent(parent, "owner", "id", ["id"]).unwrap().rows.length(),
    0,
  )
  parent.rows.push(parent.rows[0])
  assert_true(child.join_parent(parent, "owner", "id", ["id"]) is Err(_))
}
