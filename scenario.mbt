///|
pub(all) enum Override {
  Count(String, Int)
  Generator(String, String, Generator)
  Nullable(String, String, Int)
} derive(Eq, Debug)

///|
pub extend Override with Eq::{equal, not_equal}

///|
pub extend Override with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub(all) struct Scenario {
  name : String
  overrides : Array[Override]
}

///|
/// Apply explicit overrides to a copy. Dependencies are revalidated afterwards.
pub fn Model::with_scenario(
  self : Model,
  scenario : Scenario,
) -> Result[Model, Array[Issue]] {
  if !valid_name(scenario.name) {
    return Err([issue("invalid_name", "scenario", "Invalid scenario name")])
  }
  let model = self.snapshot()
  let seen : Map[String, Bool] = Map([])
  for change in scenario.overrides {
    let (entity_name, field_name, property) = match change {
      Count(entity, _) => (entity, None, "count")
      Generator(entity, field, _) => (entity, Some(field), "generator")
      Nullable(entity, field, _) => (entity, Some(field), "nullable")
    }
    let path = entity_name +
      (match field_name {
        Some(field) => "." + field
        None => ""
      })
    let identity = path + ":" + property
    if seen.contains(identity) {
      return Err([
        issue(
          "duplicate_override", path, "Scenario overrides the same property twice",
        ),
      ])
    }
    seen[identity] = true
    let mut found = false
    for ei in 0..<model.entities.length() {
      let entity = model.entities[ei]
      if entity.name != entity_name {
        continue
      }
      match change {
        Count(_, count) => {
          model.entities[ei] = { ..entity, count, }
          found = true
        }
        Generator(_, name, generator) =>
          for fi in 0..<entity.fields.length() {
            if entity.fields[fi].name == name {
              entity.fields[fi] = {
                ..entity.fields[fi],
                generator: generator.snapshot(),
              }
              found = true
            }
          }
        Nullable(_, name, chance) =>
          for fi in 0..<entity.fields.length() {
            if entity.fields[fi].name == name {
              entity.fields[fi] = {
                ..entity.fields[fi],
                null_per_mille: chance,
              }
              found = true
            }
          }
      }
    }
    if !found {
      return Err([
        issue("unknown_override", path, "Scenario target does not exist"),
      ])
    }
  }
  match compile(model) {
    Ok(_) => Ok(model)
    Err(errors) => Err(errors)
  }
}

///|
pub(all) enum Mutation {
  SetCell(String, Int, String, Value)
  RemoveCell(String, Int, String)
  DeleteRow(String, Int)
  DuplicateRow(String, Int)
} derive(Eq, Debug)

///|
pub extend Mutation with Eq::{equal, not_equal}

///|
pub extend Mutation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub(all) struct MutationResult {
  dataset : Dataset
  operations : Array[Mutation]
  report : ValidationReport
}

///|
/// Mutations are ordered. Row indices refer to the state after preceding edits.
/// The original remains unchanged even when a later operation fails.
pub fn Dataset::mutate(
  self : Dataset,
  model : Model,
  operations : Array[Mutation],
) -> Result[MutationResult, Issue] {
  let data = self.snapshot()
  for operation in operations {
    let (name, index) = match operation {
      SetCell(name, index, _, _)
      | RemoveCell(name, index, _)
      | DeleteRow(name, index)
      | DuplicateRow(name, index) => (name, index)
    }
    let table = match data.table(name) {
      Some(table) => table
      None =>
        return Err(
          issue("mutation_table", name, "Mutation table does not exist"),
        )
    }
    if index < 0 || index >= table.rows.length() {
      return Err(issue("mutation_row", name, "Mutation row is out of range"))
    }
    match operation {
      SetCell(_, _, field, _) | RemoveCell(_, _, field) => {
        let row = table.rows[index]
        if row.get(field) is None {
          return Err(
            issue(
              "mutation_field",
              name + "." + field,
              "Mutation field does not exist",
            ),
          )
        }
        let cells : Array[Cell] = []
        for cell in row.cells {
          if cell.name != field {
            cells.push(cell)
          } else {
            match operation {
              SetCell(_, _, _, value) => cells.push({ name: field, value, })
              _ => ()
            }
          }
        }
        table.rows[index] = { cells, }
      }
      DeleteRow(_, _) => {
        let rows : Array[Row] = []
        for i in 0..<table.rows.length() {
          if i != index {
            rows.push(table.rows[i])
          }
        }
        table.rows.clear()
        for row in rows {
          table.rows.push(row)
        }
      }
      DuplicateRow(_, _) =>
        table.rows.push({ cells: table.rows[index].cells.copy(), })
    }
  }
  Ok({
    dataset: data,
    operations: operations.copy(),
    report: validate_dataset(model, data),
  })
}
