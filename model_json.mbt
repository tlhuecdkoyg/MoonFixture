///|
pub fn Generator::to_json(self : Generator) -> Json {
  let fields : Map[String, Json] = Map([])
  fn kind(name : String) -> Unit {
    fields["kind"] = Json::string(name)
  }
  fn text(name : String, value : String) -> Unit {
    fields[name] = Json::string(value)
  }
  fn number(name : String, value : Int) -> Unit {
    fields[name] = Json::number(value.to_double())
  }
  match self {
    Constant(value) => {
      kind("constant")
      fields["value"] = value.to_json()
    }
    Sequence(start, step) => {
      kind("sequence")
      number("start", start)
      number("step", step)
    }
    IntegerRange(min, max) => {
      kind("integer")
      number("min", min)
      number("max", max)
    }
    BooleanChance(chance) => {
      kind("boolean")
      number("chance", chance)
    }
    DateOffset(min, max) => {
      kind("date_offset")
      number("min", min)
      number("max", max)
    }
    Choice(values) => {
      kind("choice")
      fields["values"] = Json::array(values.map(v => v.to_json()))
    }
    WeightedChoice(values) => {
      kind("weighted_choice")
      fields["values"] = Json::array(
        values.map(pair => {
          Json::object(
            Map([
              ("value", pair.0.to_json()),
              ("weight", Json::number(pair.1.to_double())),
            ]),
          )
        }),
      )
    }
    Pattern(alphabet, length) => {
      kind("pattern")
      text("alphabet", alphabet)
      number("length", length)
    }
    Reference(entity, key) => {
      kind("reference")
      text("entity", entity)
      text("key", key)
    }
    Copy(field) => {
      kind("copy")
      text("field", field)
    }
    Add(left, right) | Multiply(left, right) => {
      kind(if self is Add(_, _) { "add" } else { "multiply" })
      text("left", left)
      text("right", right)
    }
    Concat(names, separator) => {
      kind("concat")
      fields["fields"] = Json::array(names.map(Json::string))
      text("separator", separator)
    }
    Lookup(field, entity, key, value) => {
      kind("lookup")
      text("field", field)
      text("entity", entity)
      text("key", key)
      text("value", value)
    }
  }
  Json::object(fields)
}

///|
pub fn Field::to_json(self : Field) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("generator", self.generator.to_json()),
      ("unique", Json::boolean(self.unique)),
      ("primary", Json::boolean(self.primary)),
      ("null_per_mille", Json::number(self.null_per_mille.to_double())),
    ]),
  )
}

///|
pub fn Model::to_json(self : Model) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      (
        "entities",
        Json::array(
          self.entities.map(entity => {
            Json::object(
              Map([
                ("name", Json::string(entity.name)),
                ("count", Json::number(entity.count.to_double())),
                (
                  "fields",
                  Json::array(entity.fields.map(field => field.to_json())),
                ),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}

///|
/// Canonical object-key ordering is explicit, independent of hash-map iteration.
fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let names : Array[String] = []
      for name, _ in fields {
        names.push(name)
      }
      names.sort()
      "{" +
      names
      .map(name => {
        Json::string(name).stringify() +
        ":" +
        canonical_json(fields.get(name).unwrap())
      })
      .join(",") +
      "}"
    }
    Array(values) => "[" + values.map(canonical_json).join(",") + "]"
    _ => value.stringify()
  }
}

///|
pub fn Model::to_json_text(self : Model) -> String {
  canonical_json(self.to_json())
}

///|
/// Non-cryptographic identity for regression reports, not an integrity signature.
pub fn Model::fingerprint(self : Model) -> String {
  mix_name(2166136261U, self.to_json_text()).to_string()
}

///|
pub fn Limits::to_json(self : Limits) -> Json {
  Json::object(
    Map([
      ("max_entities", Json::number(self.max_entities.to_double())),
      ("max_fields", Json::number(self.max_fields.to_double())),
      ("max_rows", Json::number(self.max_rows.to_double())),
      ("max_cells", Json::number(self.max_cells.to_double())),
      ("max_attempts", Json::number(self.max_attempts.to_double())),
      ("max_text_units", Json::number(self.max_text_units.to_double())),
    ]),
  )
}

///|
fn decode_limits(value : Json, path : String) -> Limits raise ConfigError {
  let fields = object_fields(value, path)
  reject_unknown(
    fields,
    [
      "max_entities", "max_fields", "max_rows", "max_cells", "max_attempts", "max_text_units",
    ],
    path,
  )
  fn number(name : String) -> Int raise ConfigError {
    integer_value(required(fields, name, path), path + "." + name)
  }
  {
    max_entities: number("max_entities"),
    max_fields: number("max_fields"),
    max_rows: number("max_rows"),
    max_cells: number("max_cells"),
    max_attempts: number("max_attempts"),
    max_text_units: number("max_text_units"),
  }
}

///|
fn unsigned_decimal(text : String, path : String) -> UInt raise ConfigError {
  if text.is_empty() || text.length() > 10 {
    raise InvalidConfig(path, "Expected an unsigned 32-bit decimal string")
  }
  let mut result = 0UL
  for c in text.iter() {
    if c < '0' || c > '9' {
      raise InvalidConfig(path, "Expected decimal digits")
    }
    result = result * 10UL + (c.to_int() - 48).to_uint64()
    if result > 4294967295UL {
      raise InvalidConfig(path, "Seed exceeds UInt32")
    }
  }
  result.to_uint()
}

///|
/// Full input manifest; replay also checks algorithm identity and resource limits.
pub fn Plan::replay_json(self : Plan) -> String {
  canonical_json(
    Json::object(
      Map([
        ("format", Json::string("moonfixture.replay.v1")),
        ("algorithm", Json::string(algorithm_version())),
        ("seed", Json::string(self.context.seed.to_string())),
        ("reference_time", Json::string(self.context.reference_time)),
        ("limits", self.context.limits.to_json()),
        ("model", self.model.to_json()),
      ]),
    ),
  )
}

///|
pub fn replay(
  text : String,
  max_units? : Int = 1048576,
) -> Result[Dataset, Array[Issue]] {
  if guard_json(text, max_units, "replay") is Err(error) {
    return Err([error])
  }
  if max_units <= 0 || text.length() > max_units {
    return Err([issue("config_limit", "replay", "Replay exceeds input limit")])
  }
  try {
    let fields = object_fields(@json.parse(text), "replay")
    reject_unknown(
      fields,
      ["format", "algorithm", "seed", "reference_time", "limits", "model"],
      "replay",
    )
    fn text(name : String) -> String raise ConfigError {
      text_value(required(fields, name, "replay"), "replay." + name)
    }
    if text("format") != "moonfixture.replay.v1" {
      raise InvalidConfig("replay.format", "Unsupported replay format")
    }
    if text("algorithm") != algorithm_version() {
      raise InvalidConfig("replay.algorithm", "Algorithm version mismatch")
    }
    let context : Context = {
      seed: unsigned_decimal(text("seed"), "replay.seed"),
      reference_time: text("reference_time"),
      limits: decode_limits(
        required(fields, "limits", "replay"),
        "replay.limits",
      ),
    }
    generate(decode_model(required(fields, "model", "replay")), context~)
  } catch {
    InvalidConfig(path, message) =>
      Err([issue("invalid_replay", path, message)])
    _ => Err([issue("invalid_json", "replay", "Invalid JSON syntax")])
  }
}
