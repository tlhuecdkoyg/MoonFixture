///|
pub(all) struct FieldPlan {
  name : String
  evaluation_index : Int
  unique : Bool
  primary : Bool
  finite_capacity : String?
  local_dependencies : Array[String]
  parent_entity : String?
}

///|
pub(all) struct EntityPlan {
  name : String
  rows : Int
  cells : Int64
  fields : Array[FieldPlan]
}

///|
pub(all) struct PlanReport {
  model : String
  fingerprint : String
  rows : Int64
  cells : Int64
  entities : Array[EntityPlan]
  notes : Array[String]
}

///|
/// Estimates count stored values, not heap bytes; variable strings and indexes
/// prevent translating cell counts into a portable exact memory budget.
pub fn Plan::report(self : Plan) -> PlanReport {
  let entities : Array[EntityPlan] = []
  let notes : Array[String] = []
  let mut rows = 0L
  let mut cells = 0L
  for ei in self.entity_order {
    let entity = self.model.entities[ei]
    let entity_cells = entity.count.to_int64() *
      entity.fields.length().to_int64()
    rows += entity.count.to_int64()
    cells += entity_cells
    let fields : Array[FieldPlan] = []
    for order in 0..<self.field_orders[ei].length() {
      let field = entity.fields[self.field_orders[ei][order]]
      let capacity = finite_capacity(field.generator)
      if (field.unique || field.primary) && capacity is None {
        notes.push(
          entity.name +
          "." +
          field.name +
          ": uniqueness may depend on generation state or the attempt budget",
        )
      }
      if field.null_per_mille > 0 && field.null_per_mille < 1000 {
        notes.push(
          entity.name +
          "." +
          field.name +
          ": nullability is a probability, not a fixed quota",
        )
      }
      fields.push({
        name: field.name,
        evaluation_index: order,
        unique: field.unique || field.primary,
        primary: field.primary,
        finite_capacity: capacity.map(n => n.to_string()),
        local_dependencies: field.generator.field_dependencies(),
        parent_entity: field.generator.entity_dependency(),
      })
    }
    entities.push({
      name: entity.name,
      rows: entity.count,
      cells: entity_cells,
      fields,
    })
  }
  {
    model: self.model.name,
    fingerprint: self.model.fingerprint(),
    rows,
    cells,
    entities,
    notes,
  }
}

///|
pub fn FieldPlan::to_json(self : FieldPlan) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("evaluation_index", Json::number(self.evaluation_index.to_double())),
      ("unique", Json::boolean(self.unique)),
      ("primary", Json::boolean(self.primary)),
      (
        "finite_capacity",
        match self.finite_capacity {
          Some(value) => Json::string(value)
          None => Json::null()
        },
      ),
      (
        "local_dependencies",
        Json::array(self.local_dependencies.map(Json::string)),
      ),
      (
        "parent_entity",
        match self.parent_entity {
          Some(value) => Json::string(value)
          None => Json::null()
        },
      ),
    ]),
  )
}

///|
pub fn EntityPlan::to_json(self : EntityPlan) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("rows", Json::number(self.rows.to_double())),
      ("cells", Json::string(self.cells.to_string())),
      ("fields", Json::array(self.fields.map(field => field.to_json()))),
    ]),
  )
}

///|
pub fn PlanReport::to_json(self : PlanReport) -> Json {
  Json::object(
    Map([
      ("model", Json::string(self.model)),
      ("fingerprint", Json::string(self.fingerprint)),
      ("rows", Json::string(self.rows.to_string())),
      ("cells", Json::string(self.cells.to_string())),
      ("entities", Json::array(self.entities.map(entity => entity.to_json()))),
      ("notes", Json::array(self.notes.map(Json::string))),
    ]),
  )
}
