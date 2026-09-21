///|
/// Deep-copy mutable arrays so compiled plans cannot be changed by their caller.
pub fn Generator::snapshot(self : Generator) -> Generator {
  match self {
    Choice(values) => Choice(values.copy())
    WeightedChoice(values) => WeightedChoice(values.copy())
    Concat(names, separator) => Concat(names.copy(), separator)
    _ => self
  }
}

///|
pub fn Model::snapshot(self : Model) -> Model {
  {
    name: self.name,
    entities: self.entities.map(entity => {
      name: entity.name,
      count: entity.count,
      fields: entity.fields.map(field => {
        name: field.name,
        generator: field.generator.snapshot(),
        unique: field.unique,
        primary: field.primary,
        null_per_mille: field.null_per_mille,
      }),
    }),
  }
}

///|
pub fn Dataset::snapshot(self : Dataset) -> Dataset {
  {
    ..self,
    tables: self.tables.map(table => {
      name: table.name,
      rows: table.rows.map(row => { cells: row.cells.copy(), }),
    }),
  }
}

///|
pub fn Plan::model(self : Plan) -> Model {
  self.model.snapshot()
}

///|
pub fn Plan::context(self : Plan) -> Context {
  self.context
}
