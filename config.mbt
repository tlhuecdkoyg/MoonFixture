///|
pub suberror ConfigError {
  InvalidConfig(String, String)
} derive(Debug)

///|
pub extend ConfigError with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn object_fields(
  value : Json,
  path : String,
) -> Map[String, Json] raise ConfigError {
  match value {
    Object(fields) => fields
    _ => raise InvalidConfig(path, "Expected an object")
  }
}

///|
fn required(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> Json raise ConfigError {
  match fields.get(name) {
    Some(value) => value
    None =>
      raise InvalidConfig(path + "." + name, "Required property is missing")
  }
}

///|
fn text_value(value : Json, path : String) -> String raise ConfigError {
  match value {
    String(text) => text
    _ => raise InvalidConfig(path, "Expected a string")
  }
}

///|
fn integer_value(value : Json, path : String) -> Int raise ConfigError {
  match value {
    Number(number, ..) => {
      if number < -2147483648.0 || number > 2147483647.0 {
        raise InvalidConfig(path, "Integer outside Int32 bounds")
      }
      let result = number.to_int()
      if result.to_double() != number {
        raise InvalidConfig(path, "Expected an integer")
      }
      result
    }
    _ => raise InvalidConfig(path, "Expected a JSON number")
  }
}

///|
fn bool_value(value : Json, path : String) -> Bool raise ConfigError {
  match value {
    True => true
    False => false
    _ => raise InvalidConfig(path, "Expected a boolean")
  }
}

///|
fn array_value(value : Json, path : String) -> Array[Json] raise ConfigError {
  match value {
    Array(items) => items
    _ => raise InvalidConfig(path, "Expected an array")
  }
}

///|
fn scalar_value(value : Json, path : String) -> Value raise ConfigError {
  match value {
    Null => Null
    True => Boolean(true)
    False => Boolean(false)
    String(text) => Text(text)
    Number(_) => Integer(integer_value(value, path))
    _ => raise InvalidConfig(path, "Only scalar values are supported")
  }
}

///|
fn reject_unknown(
  fields : Map[String, Json],
  allowed : Array[String],
  path : String,
) -> Unit raise ConfigError {
  for name, _ in fields {
    if !allowed.contains(name) {
      raise InvalidConfig(path + "." + name, "Unknown property")
    }
  }
}

///|
fn parse_generator(value : Json, path : String) -> Generator raise ConfigError {
  let fields = object_fields(value, path)
  let kind = text_value(required(fields, "kind", path), path + ".kind")
  fn text(name : String) -> String raise ConfigError {
    text_value(required(fields, name, path), path + "." + name)
  }
  fn int(name : String) -> Int raise ConfigError {
    integer_value(required(fields, name, path), path + "." + name)
  }
  let allowed = match kind {
    "constant" => ["kind", "value"]
    "sequence" => ["kind", "start", "step"]
    "integer" => ["kind", "min", "max"]
    "date_offset" => ["kind", "min", "max"]
    "boolean" => ["kind", "chance"]
    "choice" => ["kind", "values"]
    "weighted_choice" => ["kind", "values"]
    "pattern" => ["kind", "alphabet", "length"]
    "reference" => ["kind", "entity", "key"]
    "copy" => ["kind", "field"]
    "add" | "multiply" => ["kind", "left", "right"]
    "concat" => ["kind", "fields", "separator"]
    "lookup" => ["kind", "field", "entity", "key", "value"]
    _ => raise InvalidConfig(path + ".kind", "Unknown generator: " + kind)
  }
  reject_unknown(fields, allowed, path)
  match kind {
    "constant" =>
      Constant(scalar_value(required(fields, "value", path), path + ".value"))
    "sequence" => Sequence(int("start"), int("step"))
    "integer" => IntegerRange(int("min"), int("max"))
    "date_offset" => DateOffset(int("min"), int("max"))
    "boolean" => BooleanChance(int("chance"))
    "choice" => {
      let items = array_value(
        required(fields, "values", path),
        path + ".values",
      )
      Choice(items.map(v => scalar_value(v, path + ".values")))
    }
    "weighted_choice" => {
      let items = array_value(
        required(fields, "values", path),
        path + ".values",
      )
      let values : Array[(Value, Int)] = []
      for index in 0..<items.length() {
        let item_path = path + ".values[" + index.to_string() + "]"
        let item = object_fields(items[index], item_path)
        reject_unknown(item, ["value", "weight"], item_path)
        values.push(
          (
            scalar_value(
              required(item, "value", item_path),
              item_path + ".value",
            ),
            integer_value(
              required(item, "weight", item_path),
              item_path + ".weight",
            ),
          ),
        )
      }
      WeightedChoice(values)
    }
    "pattern" => Pattern(text("alphabet"), int("length"))
    "reference" => Reference(text("entity"), text("key"))
    "copy" => Copy(text("field"))
    "add" => Add(text("left"), text("right"))
    "multiply" => Multiply(text("left"), text("right"))
    "concat" => {
      let names = array_value(
        required(fields, "fields", path),
        path + ".fields",
      )
      Concat(names.map(v => text_value(v, path + ".fields")), text("separator"))
    }
    _ => Lookup(text("field"), text("entity"), text("key"), text("value"))
  }
}

///|
fn parse_field(value : Json, path : String) -> Field raise ConfigError {
  let fields = object_fields(value, path)
  reject_unknown(
    fields,
    ["name", "generator", "unique", "primary", "null_per_mille"],
    path,
  )
  let name = text_value(required(fields, "name", path), path + ".name")
  let generator = parse_generator(
    required(fields, "generator", path),
    path + ".generator",
  )
  let unique = match fields.get("unique") {
    Some(v) => bool_value(v, path + ".unique")
    None => false
  }
  let primary = match fields.get("primary") {
    Some(v) => bool_value(v, path + ".primary")
    None => false
  }
  let null_per_mille = match fields.get("null_per_mille") {
    Some(v) => integer_value(v, path + ".null_per_mille")
    None => 0
  }
  Field::new(name, generator, unique~, primary~, null_per_mille~)
}

///|
fn decode_model(value : Json) -> Model raise ConfigError {
  let fields = object_fields(value, "model")
  reject_unknown(fields, ["name", "entities"], "model")
  let name = text_value(required(fields, "name", "model"), "model.name")
  let items = array_value(
    required(fields, "entities", "model"),
    "model.entities",
  )
  let entities : Array[Entity] = []
  for i in 0..<items.length() {
    let path = "model.entities[" + i.to_string() + "]"
    let entity = object_fields(items[i], path)
    reject_unknown(entity, ["name", "count", "fields"], path)
    let name = text_value(required(entity, "name", path), path + ".name")
    let count = integer_value(required(entity, "count", path), path + ".count")
    let definitions = array_value(
      required(entity, "fields", path),
      path + ".fields",
    )
    let entity_fields : Array[Field] = []
    for fi in 0..<definitions.length() {
      entity_fields.push(
        parse_field(definitions[fi], path + ".fields[" + fi.to_string() + "]"),
      )
    }
    entities.push({ name, count, fields: entity_fields, })
  }
  { name, entities, }
}

///|
pub fn parse_model(
  text : String,
  max_units? : Int = 1048576,
) -> Result[Model, Issue] {
  if guard_json(text, max_units, "model") is Err(error) {
    return Err(error)
  }
  if max_units <= 0 || text.length() > max_units {
    return Err(
      issue("config_limit", "model", "Model text exceeds configured size"),
    )
  }
  try {
    let value = @json.parse(text)
    Ok(decode_model(value))
  } catch {
    InvalidConfig(path, message) => Err(issue("invalid_config", path, message))
    _ => Err(issue("invalid_json", "model", "Invalid JSON syntax"))
  }
}
