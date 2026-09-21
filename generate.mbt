///|
fn checked_integer(value : Int64, path : String) -> Result[Value, Issue] {
  if value < -2147483648L || value > 2147483647L {
    Err(issue("arithmetic_overflow", path, "Derived integer exceeds Int32"))
  } else {
    Ok(Integer(value.to_int()))
  }
}

///|
fn generate_value(
  generator : Generator,
  rng : Random,
  index : Int,
  row : Row,
  tables : Map[String, Table],
  path : String,
  reference_time : String,
) -> Result[Value, Issue] {
  match generator {
    Constant(value) => Ok(value)
    Sequence(start, step) =>
      checked_integer(
        start.to_int64() + index.to_int64() * step.to_int64(),
        path,
      )
    IntegerRange(min, max) => {
      let width = (max.to_int64() - min.to_int64() + 1L).to_int()
      Ok(Integer(min + rng.below(width).unwrap()))
    }
    BooleanChance(chance) => Ok(Boolean(rng.below(1000).unwrap() < chance))
    DateOffset(min, max) => {
      let delta = min + rng.below(max - min + 1).unwrap()
      match reference_date(reference_time).unwrap().add_days(delta) {
        Ok(date) => Ok(Text(date.to_string()))
        Err(error) => Err(error)
      }
    }
    Choice(values) => Ok(values[rng.below(values.length()).unwrap()])
    Pattern(alphabet, length) => {
      let chars = alphabet.to_array()
      let result = StringBuilder()
      for _ in 0..<length {
        result.write_char(chars[rng.below(chars.length()).unwrap()])
      }
      Ok(Text(result.to_string()))
    }
    Reference(target, key) => {
      let parent = tables.get(target).unwrap()
      if parent.rows.is_empty() {
        return Err(issue("empty_reference", path, "No parent rows"))
      }
      match parent.rows[rng.below(parent.rows.length()).unwrap()].get(key) {
        Some(Null) | None =>
          Err(
            issue(
              "invalid_reference_key", path, "Parent key is missing or null",
            ),
          )
        Some(value) => Ok(value)
      }
    }
    Copy(name) =>
      match row.get(name) {
        Some(value) => Ok(value)
        None =>
          Err(
            issue(
              "missing_dependency",
              path,
              "Dependency is unavailable: " + name,
            ),
          )
      }
    Add(a, b) | Multiply(a, b) =>
      match (row.get(a), row.get(b)) {
        (Some(Integer(left)), Some(Integer(right))) => {
          let value = if generator is Add(_, _) {
            left.to_int64() + right.to_int64()
          } else {
            left.to_int64() * right.to_int64()
          }
          checked_integer(value, path)
        }
        _ =>
          Err(
            issue(
              "invalid_operand", path, "Arithmetic requires two non-null integers",
            ),
          )
      }
    Concat(names, separator) => {
      let parts : Array[String] = []
      for name in names {
        match row.get(name) {
          Some(value) => parts.push(value.display())
          None =>
            return Err(
              issue("missing_dependency", path, "Unknown concat field: " + name),
            )
        }
      }
      Ok(Text(parts.join(separator)))
    }
    Lookup(local_field, target, key, value_field) => {
      let selected = row.get(local_field)
      if selected == None || selected == Some(Null) {
        return Err(
          issue("invalid_lookup", path, "Lookup key is missing or null"),
        )
      }
      for parent in tables.get(target).unwrap().rows {
        if parent.get(key) == selected {
          return match parent.get(value_field) {
            Some(value) => Ok(value)
            None =>
              Err(issue("missing_lookup", path, "Lookup value is missing"))
          }
        }
      }
      Err(
        issue("unmatched_lookup", path, "No parent row matches the local key"),
      )
    }
  }
}

///|
fn finite_capacity(generator : Generator) -> Int64? {
  match generator {
    Constant(_) => Some(1L)
    BooleanChance(0 | 1000) => Some(1L)
    BooleanChance(_) => Some(2L)
    IntegerRange(min, max) | DateOffset(min, max) =>
      Some(max.to_int64() - min.to_int64() + 1L)
    Choice(values) => {
      let keys : Map[String, Bool] = Map([])
      for value in values {
        keys[value.key()] = true
      }
      Some(keys.length().to_int64())
    }
    Sequence(_, 0) => Some(1L)
    Pattern(alphabet, length) => {
      let chars : Map[Char, Bool] = Map([])
      for c in alphabet.iter() {
        chars[c] = true
      }
      let mut total = 1L
      for _ in 0..<length {
        if total > 2147483647L / chars.length().to_int64() {
          return None
        }
        total *= chars.length().to_int64()
      }
      Some(total)
    }
    _ => None
  }
}

///|
/// Construct a dataset. On failure no partial dataset is returned.
pub fn Plan::generate(self : Plan) -> Result[Dataset, Issue] {
  let tables : Map[String, Table] = Map([])
  let result : Array[Table] = []
  let mut text_units = 0L
  for ei in self.entity_order {
    let entity = self.model.entities[ei]
    let sets : Array[Map[String, Bool]] = entity.fields.map(_ => Map([]))
    let domains = entity.fields.map(field => {
      if field.unique || field.primary {
        unique_domain(field.generator, tables)
      } else {
        None
      }
    })
    for field in entity.fields {
      if (field.unique || field.primary) && field.null_per_mille == 0 {
        if finite_capacity(field.generator) is Some(capacity) &&
          entity.count.to_int64() > capacity {
          return Err(
            issue(
              "unsatisfiable_unique",
              entity.name + "." + field.name,
              "Requested rows exceed the finite unique domain",
            ),
          )
        }
      }
    }
    let rows : Array[Row] = []
    for index in 0..<entity.count {
      let cells : Array[Cell] = []
      let row : Row = { cells, }
      for fi in self.field_orders[ei] {
        let field = entity.fields[fi]
        let path = entity.name + "[" + index.to_string() + "]." + field.name
        let mut accepted : Value? = None
        for attempt in 0..<self.context.limits.max_attempts {
          let rng = stream(
            self.context.seed,
            entity.name,
            field.name,
            index,
            attempt~,
          )
          let value = if field.null_per_mille > 0 &&
            rng.below(1000).unwrap() < field.null_per_mille {
            Null
          } else {
            match domains[fi] {
              Some(domain) =>
                match domain.draw(rng) {
                  Some(value) => value
                  None =>
                    return Err(
                      issue(
                        "unsatisfiable_unique", path, "Unique domain has no remaining non-null values",
                      ),
                    )
                }
              None =>
                match
                  generate_value(
                    field.generator,
                    rng,
                    index,
                    row,
                    tables,
                    path,
                    self.context.reference_time,
                  ) {
                  Ok(value) => value
                  Err(error) => return Err(error)
                }
            }
          }
          if field.primary && value == Null {
            return Err(
              issue("null_primary", path, "Primary keys cannot be null"),
            )
          }
          // Like SQL UNIQUE, multiple null values are permitted.
          if value != Null && (field.unique || field.primary) {
            let key = value.key()
            if sets[fi].contains(key) {
              continue
            }
            sets[fi][key] = true
          }
          accepted = Some(value)
          break
        }
        match accepted {
          None =>
            return Err(
              issue(
                "attempt_budget", path, "Unique generation exhausted its attempt budget",
              ),
            )
          Some(value) => {
            if value is Text(text) {
              text_units += text.length().to_int64()
              if text_units > self.context.limits.max_text_units.to_int64() {
                return Err(
                  issue("text_limit", path, "Generated text exceeds the limit"),
                )
              }
            }
            cells.push({ name: field.name, value, })
          }
        }
      }
      // Output is in declaration order, regardless of evaluation order.
      rows.push({
        cells: entity.fields.map(f => {
          name: f.name,
          value: row.get(f.name).unwrap(),
        }),
      })
    }
    let table : Table = { name: entity.name, rows, }
    tables[entity.name] = table
    result.push(table)
  }
  Ok({
    model: self.model.name,
    seed: self.context.seed,
    algorithm: algorithm_version(),
    reference_time: self.context.reference_time,
    tables: result,
  })
}

///|
pub fn generate(
  model : Model,
  context? : Context = Context::new(1U),
) -> Result[Dataset, Array[Issue]] {
  match compile(model, context~) {
    Err(errors) => Err(errors)
    Ok(plan) =>
      match plan.generate() {
        Ok(dataset) => Ok(dataset)
        Err(error) => Err([error])
      }
  }
}
