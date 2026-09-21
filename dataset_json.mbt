///|
fn decode_dataset(value : Json, limits : Limits) -> Dataset raise ConfigError {
  let root = object_fields(value, "dataset")
  reject_unknown(
    root,
    ["format", "model", "seed", "algorithm", "reference_time", "tables"],
    "dataset",
  )
  fn text(name : String) -> String raise ConfigError {
    text_value(required(root, name, "dataset"), "dataset." + name)
  }
  if text("format") != "moonfixture.dataset.v1" {
    raise InvalidConfig("dataset.format", "Unsupported dataset format")
  }
  let definitions = array_value(
    required(root, "tables", "dataset"),
    "dataset.tables",
  )
  if definitions.length() > limits.max_entities {
    raise InvalidConfig("dataset.tables", "Too many tables")
  }
  let tables : Array[Table] = []
  let mut rows_total = 0L
  let mut cells_total = 0L
  let mut text_total = 0L
  for ti in 0..<definitions.length() {
    let path = "dataset.tables[" + ti.to_string() + "]"
    let table = object_fields(definitions[ti], path)
    reject_unknown(table, ["name", "rows"], path)
    let name = text_value(required(table, "name", path), path + ".name")
    let objects = array_value(required(table, "rows", path), path + ".rows")
    rows_total += objects.length().to_int64()
    if rows_total > limits.max_rows.to_int64() {
      raise InvalidConfig(path, "Dataset row limit exceeded")
    }
    let rows : Array[Row] = []
    for ri in 0..<objects.length() {
      let row_path = path + ".rows[" + ri.to_string() + "]"
      let object = object_fields(objects[ri], row_path)
      if object.length() > limits.max_fields {
        raise InvalidConfig(row_path, "Too many fields")
      }
      cells_total += object.length().to_int64()
      if cells_total > limits.max_cells.to_int64() {
        raise InvalidConfig(row_path, "Dataset cell limit exceeded")
      }
      let names : Array[String] = []
      for name, _ in object {
        names.push(name)
      }
      names.sort()
      let cells : Array[Cell] = []
      for name in names {
        let value = scalar_value(
          object.get(name).unwrap(),
          row_path + "." + name,
        )
        if value is Text(text) {
          text_total += text.length().to_int64()
        }
        if text_total > limits.max_text_units.to_int64() {
          raise InvalidConfig(row_path, "Dataset text limit exceeded")
        }
        cells.push({ name, value, })
      }
      rows.push({ cells, })
    }
    tables.push({ name, rows, })
  }
  {
    model: text("model"),
    seed: unsigned_decimal(text("seed"), "dataset.seed"),
    algorithm: text("algorithm"),
    reference_time: text("reference_time"),
    tables,
  }
}

///|
/// Parsing does not imply validity against a model; call validate_dataset next.
/// Imported row fields are sorted; row/table array order is retained.
pub fn parse_dataset(
  text : String,
  max_units? : Int = 16777216,
  limits? : Limits = Limits::default(),
) -> Result[Dataset, Issue] {
  if max_units <= 0 || text.length() > max_units {
    return Err(
      issue("input_limit", "dataset", "Dataset input exceeds configured limit"),
    )
  }
  Ok(decode_dataset(@json.parse(text), limits)) catch {
    InvalidConfig(path, message) => Err(issue("invalid_dataset", path, message))
    _ => Err(issue("invalid_json", "dataset", "Invalid dataset JSON"))
  }
}
