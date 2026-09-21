///|
pub(all) enum JoinMode {
  Inner
  Left
}

///|
/// Materialize an assertion oracle using a unique parent key. A left join uses
/// explicit Null values for the requested parent columns when no match exists.
pub fn Table::join_parent(
  self : Table,
  parent : Table,
  local_field : String,
  parent_key : String,
  columns : Array[String],
  prefix? : String = "parent_",
  mode? : JoinMode = Inner,
) -> Result[Table, Issue] {
  let seen : Map[String, Bool] = Map([])
  for name in columns {
    if seen.contains(name) {
      return Err(
        issue(
          "join_duplicate_column", name, "Parent projection contains duplicate names",
        ),
      )
    }
    seen[name] = true
  }
  let index : Map[String, Row] = Map([])
  for row in parent.rows {
    let key = match row.get(parent_key) {
      None | Some(Null) =>
        return Err(
          issue(
            "join_parent_key",
            parent.name,
            "Parent key must be present and non-null",
          ),
        )
      Some(value) => value.key()
    }
    if index.contains(key) {
      return Err(
        issue("join_duplicate_key", parent.name, "Parent key must be unique"),
      )
    }
    for name in columns {
      if row.get(name) is None {
        return Err(
          issue(
            "join_parent_column",
            parent.name + "." + name,
            "Projected parent column is missing",
          ),
        )
      }
    }
    index[key] = row
  }
  let rows : Array[Row] = []
  for ri in 0..<self.rows.length() {
    let child = self.rows[ri]
    let value = match child.get(local_field) {
      Some(value) => value
      None =>
        return Err(
          issue(
            "join_local_field",
            validation_path(self.name, ri, local_field),
            "Local join field is missing",
          ),
        )
    }
    for column in columns {
      if child.get(prefix + column) is Some(_) {
        return Err(
          issue(
            "join_collision",
            prefix + column,
            "Projected name collides with a child field",
          ),
        )
      }
    }
    let parent_row = if value == Null { None } else { index.get(value.key()) }
    if parent_row is None && mode is Inner {
      continue
    }
    let cells = child.cells.copy()
    for column in columns {
      let value = match parent_row {
        Some(row) => row.get(column).unwrap()
        None => Null
      }
      cells.push({ name: prefix + column, value, })
    }
    rows.push({ cells, })
  }
  Ok({ name: self.name, rows, })
}

///|
/// Return an independent row/field snapshot suitable for pagination assertions.
pub fn Table::page(
  self : Table,
  offset : Int,
  limit : Int,
) -> Result[Table, Issue] {
  if offset < 0 || limit < 0 {
    return Err(
      issue("invalid_page", self.name, "Offset and limit cannot be negative"),
    )
  }
  let start = offset.min(self.rows.length())
  let count = limit.min(self.rows.length() - start)
  Ok({
    name: self.name,
    rows: self.rows[start:start + count]
    .iter()
    .map(row => { cells: row.cells.copy(), })
    .collect(),
  })
}

///|
/// Equality is type-aware: integer 1 does not match text "1" or boolean true.
pub fn Table::where_equal(self : Table, field : String, value : Value) -> Table {
  {
    name: self.name,
    rows: self.rows
    .filter(row => row.get(field) == Some(value))
    .map(row => { cells: row.cells.copy(), }),
  }
}

///|
pub fn Table::project(
  self : Table,
  columns : Array[String],
) -> Result[Table, Issue] {
  let names : Map[String, Bool] = Map([])
  for name in columns {
    if names.contains(name) {
      return Err(
        issue(
          "duplicate_projection", name, "Projection contains duplicate names",
        ),
      )
    }
    names[name] = true
  }
  let rows : Array[Row] = []
  for ri in 0..<self.rows.length() {
    let cells : Array[Cell] = []
    for name in columns {
      match self.rows[ri].get(name) {
        Some(value) => cells.push({ name, value, })
        None =>
          return Err(
            issue(
              "missing_projection",
              validation_path(self.name, ri, name),
              "Projected field does not exist",
            ),
          )
      }
    }
    rows.push({ cells, })
  }
  Ok({ name: self.name, rows, })
}

///|
pub(all) struct GroupSummary {
  key : Value
  count : Int
  integer_count : Int
  null_count : Int
  sum : Int64
  min : Int?
  max : Int?
}

///|
/// Group order follows first occurrence, not map traversal. Null amounts are
/// excluded from numeric aggregates; text/boolean amounts are errors.
pub fn Table::group_sum(
  self : Table,
  key_field : String,
  amount_field : String,
) -> Result[Array[GroupSummary], Issue] {
  let groups : Array[GroupSummary] = []
  let indexes : Map[String, Int] = Map([])
  for ri in 0..<self.rows.length() {
    let row = self.rows[ri]
    let key = match row.get(key_field) {
      Some(value) => value
      None =>
        return Err(
          issue(
            "group_key",
            validation_path(self.name, ri, key_field),
            "Group field is missing",
          ),
        )
    }
    let amount = match row.get(amount_field) {
      Some(value) => value
      None =>
        return Err(
          issue(
            "group_amount",
            validation_path(self.name, ri, amount_field),
            "Amount field is missing",
          ),
        )
    }
    let index = match indexes.get(key.key()) {
      Some(index) => index
      None => {
        let index = groups.length()
        indexes[key.key()] = index
        groups.push({
          key,
          count: 0,
          integer_count: 0,
          null_count: 0,
          sum: 0L,
          min: None,
          max: None,
        })
        index
      }
    }
    let old = groups[index]
    groups[index] = match amount {
      Null => { ..old, count: old.count + 1, null_count: old.null_count + 1, }
      Integer(value) =>
        {
          ..old,
          count: old.count + 1,
          integer_count: old.integer_count + 1,
          sum: old.sum + value.to_int64(),
          min: minimum(old.min, value),
          max: maximum(old.max, value),
        }
      _ =>
        return Err(
          issue(
            "group_type",
            validation_path(self.name, ri, amount_field),
            "Group sums accept only integers and null",
          ),
        )
    }
  }
  Ok(groups)
}

///|
pub fn GroupSummary::to_json(self : GroupSummary) -> Json {
  Json::object(
    Map([
      ("key", self.key.to_json()),
      ("count", Json::number(self.count.to_double())),
      ("integer_count", Json::number(self.integer_count.to_double())),
      ("null_count", Json::number(self.null_count.to_double())),
      ("sum", Json::string(self.sum.to_string())),
      ("min", optional_number(self.min)),
      ("max", optional_number(self.max)),
    ]),
  )
}
