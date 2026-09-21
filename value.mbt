///|
/// Supported scalar values. Integers are restricted to portable signed Int32.
pub(all) enum Value {
  Null
  Boolean(Bool)
  Integer(Int)
  Text(String)
} derive(Eq, Debug)

///|
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Boolean(value) => Json::boolean(value)
    Integer(value) => value.to_json()
    Text(value) => Json::string(value)
  }
}

///|
pub fn Value::display(self : Value) -> String {
  match self {
    Null => ""
    Boolean(value) => value.to_string()
    Integer(value) => value.to_string()
    Text(value) => value
  }
}

///|
/// Type-prefixed key: text "1" differs from integer 1 and null from empty text.
pub fn Value::key(self : Value) -> String {
  match self {
    Null => "n:"
    Boolean(value) => "b:" + value.to_string()
    Integer(value) => "i:" + value.to_string()
    Text(value) => "s:" + value
  }
}

///|
pub(all) struct Cell {
  name : String
  value : Value
} derive(Eq, Debug)

///|
pub(all) struct Row {
  cells : Array[Cell]
} derive(Eq, Debug)

///|
pub fn Row::get(self : Row, name : String) -> Value? {
  for cell in self.cells {
    if cell.name == name {
      return Some(cell.value)
    }
  }
  None
}

///|
pub fn Row::to_json(self : Row) -> Json {
  let fields : Map[String, Json] = Map([])
  for cell in self.cells {
    fields[cell.name] = cell.value.to_json()
  }
  Json::object(fields)
}

///|
pub(all) struct Issue {
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
pub fn Issue::to_json(self : Issue) -> Json {
  Json::object({
    "code": Json::string(self.code),
    "path": Json::string(self.path),
    "message": Json::string(self.message),
  })
}

///|
pub extend Value with Eq::{not_equal, equal}

///|
pub extend Value with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Cell with Eq::{not_equal, equal}

///|
pub extend Cell with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Row with Eq::{not_equal, equal}

///|
pub extend Row with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Issue with Eq::{not_equal, equal}

///|
pub extend Issue with @moonbitlang/core/debug.Debug::{to_repr}
