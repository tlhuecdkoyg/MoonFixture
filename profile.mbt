///|
pub(all) struct FieldProfile {
  name : String
  present : Int
  missing : Int
  nulls : Int
  booleans : Int
  true_values : Int
  integers : Int
  texts : Int
  distinct : Int
  min_integer : Int?
  max_integer : Int?
  sum_integer : Int64
  min_text_length : Int?
  max_text_length : Int?
}

///|
pub(all) struct TableProfile {
  name : String
  rows : Int
  fields : Array[FieldProfile]
}

///|
fn minimum(current : Int?, value : Int) -> Int? {
  Some(
    match current {
      Some(old) => old.min(value)
      None => value
    },
  )
}

///|
fn maximum(current : Int?, value : Int) -> Int? {
  Some(
    match current {
      Some(old) => old.max(value)
      None => value
    },
  )
}

///|
/// Distinct counts include null; missing cells are counted separately.
pub fn Table::profile(self : Table) -> TableProfile {
  let names : Array[String] = []
  for row in self.rows {
    for cell in row.cells {
      if !names.contains(cell.name) {
        names.push(cell.name)
      }
    }
  }
  names.sort()
  let fields : Array[FieldProfile] = []
  for name in names {
    let mut present = 0
    let mut missing = 0
    let mut nulls = 0
    let mut booleans = 0
    let mut true_values = 0
    let mut integers = 0
    let mut texts = 0
    let mut min_integer : Int? = None
    let mut max_integer : Int? = None
    let mut sum_integer = 0L
    let mut min_text_length : Int? = None
    let mut max_text_length : Int? = None
    let distinct : Map[String, Bool] = Map([])
    for row in self.rows {
      match row.get(name) {
        None => missing += 1
        Some(value) => {
          present += 1
          distinct[value.key()] = true
          match value {
            Null => nulls += 1
            Boolean(value) => {
              booleans += 1
              if value {
                true_values += 1
              }
            }
            Integer(value) => {
              integers += 1
              min_integer = minimum(min_integer, value)
              max_integer = maximum(max_integer, value)
              sum_integer += value.to_int64()
            }
            Text(text) => {
              texts += 1
              let length = text.to_array().length()
              min_text_length = minimum(min_text_length, length)
              max_text_length = maximum(max_text_length, length)
            }
          }
        }
      }
    }
    fields.push({
      name,
      present,
      missing,
      nulls,
      booleans,
      true_values,
      integers,
      texts,
      distinct: distinct.length(),
      min_integer,
      max_integer,
      sum_integer,
      min_text_length,
      max_text_length,
    })
  }
  { name: self.name, rows: self.rows.length(), fields, }
}

///|
fn optional_number(value : Int?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
pub fn FieldProfile::to_json(self : FieldProfile) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("present", Json::number(self.present.to_double())),
      ("missing", Json::number(self.missing.to_double())),
      ("nulls", Json::number(self.nulls.to_double())),
      ("booleans", Json::number(self.booleans.to_double())),
      ("true_values", Json::number(self.true_values.to_double())),
      ("integers", Json::number(self.integers.to_double())),
      ("texts", Json::number(self.texts.to_double())),
      ("distinct", Json::number(self.distinct.to_double())),
      ("min_integer", optional_number(self.min_integer)),
      ("max_integer", optional_number(self.max_integer)),
      ("sum_integer", Json::string(self.sum_integer.to_string())),
      ("min_text_length", optional_number(self.min_text_length)),
      ("max_text_length", optional_number(self.max_text_length)),
    ]),
  )
}

///|
pub fn TableProfile::to_json(self : TableProfile) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("rows", Json::number(self.rows.to_double())),
      ("fields", Json::array(self.fields.map(field => field.to_json()))),
    ]),
  )
}

///|
pub fn Dataset::profile_json(self : Dataset) -> Json {
  Json::object(
    Map([
      ("model", Json::string(self.model)),
      (
        "tables",
        Json::array(self.tables.map(table => table.profile().to_json())),
      ),
    ]),
  )
}
