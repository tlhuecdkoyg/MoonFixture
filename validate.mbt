///|
pub(all) struct ValidationReport {
  issues : Array[Issue]
  checked_rows : Int
  truncated : Bool
}

///|
pub fn ValidationReport::is_valid(self : ValidationReport) -> Bool {
  self.issues.is_empty() && !self.truncated
}

///|
fn validation_path(entity : String, index : Int, field : String) -> String {
  entity + "[" + index.to_string() + "]." + field
}

///|
fn value_matches(generator : Generator, value : Value, index : Int) -> Bool {
  match (generator, value) {
    (Constant(expected), actual) => expected == actual
    (Sequence(start, step), Integer(actual)) =>
      actual.to_int64() == start.to_int64() + index.to_int64() * step.to_int64()
    (IntegerRange(min, max), Integer(actual)) => actual >= min && actual <= max
    (BooleanChance(0), Boolean(actual)) => !actual
    (BooleanChance(1000), Boolean(actual)) => actual
    (BooleanChance(_), Boolean(_)) => true
    (Choice(values), actual) => values.contains(actual)
    (Pattern(alphabet, length), Text(actual)) => {
      let chars = actual.to_array()
      chars.length() == length &&
      chars.all(c => alphabet.to_array().contains(c))
    }
    (
      Reference(_, _)
      | Copy(_)
      | Add(_, _)
      | Multiply(_, _)
      | Concat(_, _)
      | Lookup(_, _, _, _)
      | DateOffset(_, _),
      _,
    ) => true
    _ => false
  }
}

///|
fn derived_matches(generator : Generator, row : Row, value : Value) -> Bool {
  match generator {
    Copy(name) => row.get(name) == Some(value)
    Add(left, right) | Multiply(left, right) =>
      match (row.get(left), row.get(right), value) {
        (Some(Integer(a)), Some(Integer(b)), Integer(actual)) => {
          let expected = if generator is Add(_, _) {
            a.to_int64() + b.to_int64()
          } else {
            a.to_int64() * b.to_int64()
          }
          actual.to_int64() == expected
        }
        _ => false
      }
    Concat(names, separator) => {
      let parts : Array[String] = []
      for name in names {
        match row.get(name) {
          Some(v) => parts.push(v.display())
          None => return false
        }
      }
      value == Text(parts.join(separator))
    }
    _ => true
  }
}

///|
/// Validate external or deliberately mutated data independently of generation.
/// No random numbers are consumed; probabilities are not exact quotas.
pub fn validate_dataset(
  model : Model,
  data : Dataset,
  max_issues? : Int = 100,
  check_counts? : Bool = true,
) -> ValidationReport {
  let issues : Array[Issue] = []
  let mut checked_rows = 0
  let mut truncated = false
  let budget = max_issues.max(1)
  fn add(code : String, path : String, message : String) -> Unit {
    if issues.length() < budget {
      issues.push(issue(code, path, message))
    } else {
      truncated = true
    }
  }
  match
    compile(
      model,
      context=Context::new(data.seed, reference_time=data.reference_time),
    ) {
    Err(errors) => {
      for error in errors {
        add(error.code, error.path, error.message)
      }
      return { issues, checked_rows, truncated, }
    }
    Ok(_) => ()
  }
  if data.model != model.name {
    add("model_mismatch", "model", "Dataset belongs to another model")
  }
  let tables : Map[String, Table] = Map([])
  for table in data.tables {
    if tables.contains(table.name) {
      add("duplicate_table", table.name, "Duplicate table name")
    }
    if model.entity(table.name) is None {
      add("unknown_table", table.name, "Table is not declared by model")
    }
    tables[table.name] = table
  }
  // Typed keys distinguish integer 1, boolean true and string "1".
  let indexes : Map[String, Map[String, Row]] = Map([])
  for entity in model.entities {
    if tables.get(entity.name) is Some(table) {
      for field in entity.fields {
        if field.unique || field.primary {
          let entries : Map[String, Row] = Map([])
          for row in table.rows {
            if row.get(field.name) is Some(value) && value != Null {
              entries[value.key()] = row
            }
          }
          indexes[entity.name + "." + field.name] = entries
        }
      }
    }
  }
  for entity in model.entities {
    let table = match tables.get(entity.name) {
      Some(table) => table
      None => {
        add("missing_table", entity.name, "Declared table is absent")
        continue
      }
    }
    if check_counts && table.rows.length() != entity.count {
      add("row_count", entity.name, "Row count differs from the model")
    }
    let unique : Array[Map[String, Bool]] = entity.fields.map(_ => Map([]))
    for ri in 0..<table.rows.length() {
      let row = table.rows[ri]
      checked_rows += 1
      let names : Map[String, Bool] = Map([])
      for cell in row.cells {
        let path = validation_path(entity.name, ri, cell.name)
        if names.contains(cell.name) {
          add("duplicate_cell", path, "Row has duplicate field names")
        }
        names[cell.name] = true
        if entity.field(cell.name) is None {
          add("unknown_cell", path, "Field is not declared")
        }
      }
      for fi in 0..<entity.fields.length() {
        let field = entity.fields[fi]
        let path = validation_path(entity.name, ri, field.name)
        let value = match row.get(field.name) {
          Some(value) => value
          None => {
            add("missing_cell", path, "Required field is absent")
            continue
          }
        }
        if value == Null {
          if field.primary {
            add("null_primary", path, "Primary key is null")
          }
          let inherited_null = match field.generator {
            Constant(Null) => true
            Copy(name) => row.get(name) == Some(Null)
            Lookup(local_field, target, key, value_field) =>
              match (row.get(local_field), indexes.get(target + "." + key)) {
                (Some(selected), Some(index)) =>
                  match index.get(selected.key()) {
                    Some(parent) => parent.get(value_field) == Some(Null)
                    None => false
                  }
                _ => false
              }
            _ => false
          }
          if field.null_per_mille == 0 && !inherited_null {
            add("unexpected_null", path, "Field does not permit null")
          }
          // Copy and constant may intentionally produce null without sampling.
          if field.null_per_mille == 0 &&
            !derived_matches(field.generator, row, value) {
            add(
              "derived_value", path, "Derived null does not match its dependency",
            )
          }
          continue
        }
        if field.null_per_mille == 1000 {
          add("expected_null", path, "Field is configured to always be null")
        }
        if field.unique || field.primary {
          if unique[fi].contains(value.key()) {
            add("duplicate_key", path, "Unique value is repeated")
          }
          unique[fi][value.key()] = true
        }
        if !value_matches(field.generator, value, ri) {
          add("value_domain", path, "Value is outside the generator domain")
        }
        if !derived_matches(field.generator, row, value) {
          add("derived_value", path, "Value does not match its dependencies")
        }
        match field.generator {
          DateOffset(min, max) => {
            let valid = match value {
              Text(text) =>
                match parse_date(text) {
                  Ok(date) => {
                    let delta = date.ordinal().unwrap() -
                      reference_date(data.reference_time)
                      .unwrap()
                      .ordinal()
                      .unwrap()
                    delta >= min && delta <= max
                  }
                  Err(_) => false
                }
              _ => false
            }
            if !valid {
              add(
                "date_domain", path, "Date is outside the reference-relative range",
              )
            }
          }
          Reference(target, key) => {
            let found = match indexes.get(target + "." + key) {
              Some(index) => index.contains(value.key())
              None => false
            }
            if !found {
              add("foreign_key", path, "Referenced parent key does not exist")
            }
          }
          Lookup(local_field, target, key, value_field) => {
            let parent = match
              (row.get(local_field), indexes.get(target + "." + key)) {
              (Some(selected), Some(index)) => index.get(selected.key())
              _ => None
            }
            match parent {
              Some(parent) =>
                if parent.get(value_field) != Some(value) {
                  add("lookup_value", path, "Value differs from parent lookup")
                }
              None => add("lookup_key", path, "Lookup cannot find the parent")
            }
          }
          _ => ()
        }
      }
    }
  }
  { issues, checked_rows, truncated, }
}

///|
pub fn ValidationReport::to_json(self : ValidationReport) -> Json {
  Json::object(
    Map([
      ("valid", Json::boolean(self.is_valid())),
      ("checked_rows", Json::number(self.checked_rows.to_double())),
      ("truncated", Json::boolean(self.truncated)),
      ("issues", Json::array(self.issues.map(i => i.to_json()))),
    ]),
  )
}
