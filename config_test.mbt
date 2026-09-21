///|
test "strict model parsing generates relational fixtures" {
  let source =
    #|{"name":"shop","entities":[{"name":"users","count":2,"fields":[{"name":"id","primary":true,"generator":{"kind":"sequence","start":1,"step":1}}]}]}
  let model = @MoonFixture.parse_model(source).unwrap()
  let data = @MoonFixture.generate(model).unwrap()
  assert_eq(data.tables[0].to_ndjson(), "{\"id\":1}\n{\"id\":2}\n")
  assert_eq(data.tables[0].to_csv(["id"]), "id\r\n1\r\n2\r\n")
  assert_eq(data.tables[0].batches(1).unwrap().length(), 2)
  assert_true(data.tables[0].batches(0) is Err(_))
  assert_true(@MoonFixture.parse_model(source, max_units=10) is Err(_))
}

///|
test "config rejects unknown properties fractional integers and nested constants" {
  for
    source in [
      "{\"name\":\"a\",\"entities\":[],\"typo\":1}", "{\"name\":\"a\",\"entities\":[{\"name\":\"b\",\"count\":1.5,\"fields\":[]}]}",
      "{\"name\":\"a\",\"entities\":[{\"name\":\"b\",\"count\":1,\"fields\":[{\"name\":\"x\",\"generator\":{\"kind\":\"constant\",\"value\":[]}}]}]}",
      "not json",
    ] {
    assert_true(@MoonFixture.parse_model(source) is Err(_))
  }
}

///|
test "csv and json escape multiline unicode data" {
  let table : @MoonFixture.Table = {
    name: "quoted",
    rows: [{ cells: [{ name: "text", value: Text("a,\"b\"\n中文"), }], }],
  }
  assert_eq(table.to_csv(["text"]), "text\r\n\"a,\"\"b\"\"\n中文\"\r\n")
  assert_eq(table.to_ndjson(), "{\"text\":\"a,\\\"b\\\"\\n中文\"}\n")
}
