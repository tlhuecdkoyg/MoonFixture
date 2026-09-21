///|
pub(all) enum Generator {
  Constant(Value)
  Sequence(Int, Int)
  IntegerRange(Int, Int)
  BooleanChance(Int)
  Choice(Array[Value])
  WeightedChoice(Array[(Value, Int)])
  Pattern(String, Int)
  DateOffset(Int, Int)
  Reference(String, String)
  Copy(String)
  Add(String, String)
  Multiply(String, String)
  Concat(Array[String], String)
  Lookup(String, String, String, String)
} derive(Eq, Debug)

///|
pub(all) struct Field {
  name : String
  generator : Generator
  unique : Bool
  primary : Bool
  null_per_mille : Int
} derive(Eq, Debug)

///|
pub fn Field::new(
  name : String,
  generator : Generator,
  unique? : Bool = false,
  primary? : Bool = false,
  null_per_mille? : Int = 0,
) -> Field {
  { name, generator, unique: unique || primary, primary, null_per_mille, }
}

///|
pub(all) struct Entity {
  name : String
  count : Int
  fields : Array[Field]
} derive(Eq, Debug)

///|
pub(all) struct Model {
  name : String
  entities : Array[Entity]
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_entities : Int
  max_fields : Int
  max_rows : Int
  max_cells : Int
  max_attempts : Int
  max_text_units : Int
} derive(Eq, Debug)

///|
pub fn Limits::default() -> Limits {
  {
    max_entities: 128,
    max_fields: 256,
    max_rows: 1000000,
    max_cells: 5000000,
    max_attempts: 256,
    max_text_units: 10000000,
  }
}

///|
pub(all) struct Context {
  seed : UInt
  reference_time : String
  limits : Limits
} derive(Eq, Debug)

///|
pub fn Context::new(
  seed : UInt,
  reference_time? : String = "2026-01-01T00:00:00Z",
  limits? : Limits = Limits::default(),
) -> Context {
  { seed, reference_time, limits, }
}

///|
pub(all) struct Table {
  name : String
  rows : Array[Row]
} derive(Eq, Debug)

///|
pub(all) struct Dataset {
  model : String
  seed : UInt
  algorithm : String
  reference_time : String
  tables : Array[Table]
} derive(Eq, Debug)

///|
pub fn Dataset::table(self : Dataset, name : String) -> Table? {
  for table in self.tables {
    if table.name == name {
      return Some(table)
    }
  }
  None
}

///|
pub fn Model::entity(self : Model, name : String) -> Entity? {
  for entity in self.entities {
    if entity.name == name {
      return Some(entity)
    }
  }
  None
}

///|
pub fn Entity::field(self : Entity, name : String) -> Field? {
  for field in self.fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
pub fn Generator::field_dependencies(self : Generator) -> Array[String] {
  match self {
    Copy(name) => [name]
    Add(a, b) | Multiply(a, b) => [a, b]
    Concat(names, _) => names.copy()
    Lookup(local_field, _, _, _) => [local_field]
    _ => []
  }
}

///|
pub fn Generator::entity_dependency(self : Generator) -> String? {
  match self {
    Reference(entity, _) | Lookup(_, entity, _, _) => Some(entity)
    _ => None
  }
}

///|
fn issue(code : String, path : String, message : String) -> Issue {
  { code, path, message, }
}

///|
fn valid_name(name : String) -> Bool {
  if name.is_empty() || name.length() > 128 {
    return false
  }
  for c in name.iter() {
    let n = c.to_int()
    if !((n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 95) {
      return false
    }
  }
  true
}

///|
pub extend Generator with Eq::{not_equal, equal}

///|
pub extend Generator with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Field with Eq::{not_equal, equal}

///|
pub extend Field with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Entity with Eq::{not_equal, equal}

///|
pub extend Entity with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Model with Eq::{not_equal, equal}

///|
pub extend Model with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{not_equal, equal}

///|
pub extend Limits with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Context with Eq::{not_equal, equal}

///|
pub extend Context with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Table with Eq::{not_equal, equal}

///|
pub extend Table with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Dataset with Eq::{not_equal, equal}

///|
pub extend Dataset with @moonbitlang/core/debug.Debug::{to_repr}
