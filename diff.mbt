///|
pub(all) struct Difference {
  kind : String
  table : String
  row_key : String
  field : String
  before : Value?
  after : Value?
}

///|
pub(all) struct Comparison {
  differences : Array[Difference]
  truncated : Bool
}

///|
pub fn Comparison::equal(self : Comparison) -> Bool {
  self.differences.is_empty() && !self.truncated
}

///|
fn primary_field(entity : Entity) -> String? {
  for field in entity.fields {
    if field.primary {
      return Some(field.name)
    }
  }
  None
}

///|
fn keyed_rows(table : Table, key : String?) -> Result[Map[String, Row], Issue] {
  let rows : Map[String, Row] = Map([])
  for index in 0..<table.rows.length() {
    let row = table.rows[index]
    let identity = match key {
      None => "index:" + index.to_string()
      Some(name) =>
        match row.get(name) {
          Some(Null) | None =>
            return Err(
              issue(
                "diff_missing_key",
                table.name,
                "Row key is missing or null",
              ),
            )
          Some(value) => value.key()
        }
    }
    if rows.contains(identity) {
      return Err(
        issue("diff_duplicate_key", table.name, "Row identity is not unique"),
      )
    }
    let names : Map[String, Bool] = Map([])
    for cell in row.cells {
      if names.contains(cell.name) {
        return Err(
          issue(
            "diff_duplicate_cell",
            table.name,
            "Row contains duplicate field names",
          ),
        )
      }
      names[cell.name] = true
    }
    rows[identity] = row
  }
  Ok(rows)
}

///|
fn unique_tables(data : Dataset) -> Result[Map[String, Table], Issue] {
  let tables : Map[String, Table] = Map([])
  for table in data.tables {
    if tables.contains(table.name) {
      return Err(
        issue("diff_duplicate_table", table.name, "Table names must be unique"),
      )
    }
    tables[table.name] = table
  }
  Ok(tables)
}

///|
/// Compare fixture content by declared primary keys, otherwise by row position.
/// Metadata is intentionally separate from content, allowing cross-seed analysis.
pub fn compare_datasets(
  model : Model,
  before : Dataset,
  after : Dataset,
  max_differences? : Int = 100,
) -> Result[Comparison, Issue] {
  if compile(model) is Err(errors) {
    return Err(errors[0])
  }
  if max_differences <= 0 {
    return Err(
      issue("diff_limit", "comparison", "Difference limit must be positive"),
    )
  }
  let old_tables = match unique_tables(before) {
    Ok(tables) => tables
    Err(error) => return Err(error)
  }
  let new_tables = match unique_tables(after) {
    Ok(tables) => tables
    Err(error) => return Err(error)
  }
  let names : Array[String] = []
  for table in before.tables {
    names.push(table.name)
  }
  for table in after.tables {
    if !names.contains(table.name) {
      names.push(table.name)
    }
  }
  names.sort()
  let differences : Array[Difference] = []
  let mut truncated = false
  fn add(
    kind : String,
    table : String,
    row_key : String,
    field : String,
    before : Value?,
    after : Value?,
  ) -> Unit {
    if differences.length() >= max_differences {
      truncated = true
    } else {
      differences.push({ kind, table, row_key, field, before, after, })
    }
  }
  for name in names {
    let key = match model.entity(name) {
      Some(entity) => primary_field(entity)
      None => None
    }
    let (old_table, new_table) = match
      (old_tables.get(name), new_tables.get(name)) {
      (None, Some(_)) => {
        add("table_added", name, "", "", None, None)
        continue
      }
      (Some(_), None) => {
        add("table_removed", name, "", "", None, None)
        continue
      }
      (Some(a), Some(b)) => (a, b)
      _ => continue
    }
    let old_rows = match keyed_rows(old_table, key) {
      Ok(rows) => rows
      Err(error) => return Err(error)
    }
    let new_rows = match keyed_rows(new_table, key) {
      Ok(rows) => rows
      Err(error) => return Err(error)
    }
    let identities : Array[String] = []
    for id, _ in old_rows {
      identities.push(id)
    }
    for id, _ in new_rows {
      if !old_rows.contains(id) {
        identities.push(id)
      }
    }
    identities.sort()
    for id in identities {
      let (old_row, new_row) = match (old_rows.get(id), new_rows.get(id)) {
        (None, Some(_)) => {
          add("row_added", name, id, "", None, None)
          continue
        }
        (Some(_), None) => {
          add("row_removed", name, id, "", None, None)
          continue
        }
        (Some(a), Some(b)) => (a, b)
        _ => continue
      }
      let fields : Array[String] = old_row.cells.map(cell => cell.name)
      for cell in new_row.cells {
        if !fields.contains(cell.name) {
          fields.push(cell.name)
        }
      }
      fields.sort()
      for field in fields {
        let old = old_row.get(field)
        let new = new_row.get(field)
        if old != new {
          add("cell_changed", name, id, field, old, new)
        }
      }
    }
  }
  Ok({ differences, truncated, })
}

///|
pub fn Difference::to_json(self : Difference) -> Json {
  Json::object(
    Map([
      ("kind", Json::string(self.kind)),
      ("table", Json::string(self.table)),
      ("row_key", Json::string(self.row_key)),
      ("field", Json::string(self.field)),
      ("before_present", Json::boolean(self.before is Some(_))),
      ("after_present", Json::boolean(self.after is Some(_))),
      (
        "before",
        match self.before {
          Some(value) => value.to_json()
          None => Json::null()
        },
      ),
      (
        "after",
        match self.after {
          Some(value) => value.to_json()
          None => Json::null()
        },
      ),
    ]),
  )
}

///|
pub fn Comparison::to_json(self : Comparison) -> Json {
  Json::object(
    Map([
      ("equal", Json::boolean(self.equal())),
      ("truncated", Json::boolean(self.truncated)),
      ("differences", Json::array(self.differences.map(diff => diff.to_json()))),
    ]),
  )
}
