///|
/// A plan owns a deep snapshot of its validated model.
pub struct Plan {
  model : Model
  context : Context
  entity_order : Array[Int]
  field_orders : Array[Array[Int]]
} derive(Debug)

///|
pub fn Plan::entity_names(self : Plan) -> Array[String] {
  self.entity_order.map(i => self.model.entities[i].name)
}

///|
fn ordered_nodes(
  names : Array[String],
  dependencies : Array[Array[String]],
  path : String,
) -> Result[Array[Int], Array[Issue]] {
  let order : Array[Int] = []
  let visited : Map[String, Bool] = Map([])
  while order.length() < names.length() {
    let before = order.length()
    for i in 0..<names.length() {
      if visited.contains(names[i]) {
        continue
      }
      if dependencies[i].all(name => visited.contains(name)) {
        order.push(i)
        visited[names[i]] = true
      }
    }
    if before == order.length() {
      let blocked = names.filter(name => !visited.contains(name))
      return Err([
        issue(
          "dependency_cycle",
          path,
          "Unresolved cyclic dependencies: " + blocked.join(", "),
        ),
      ])
    }
  }
  Ok(order)
}

///|
fn check_generator(generator : Generator, path : String) -> Array[Issue] {
  let errors : Array[Issue] = []
  match generator {
    IntegerRange(min, max) | DateOffset(min, max) => {
      let width = max.to_int64() - min.to_int64() + 1L
      if width <= 0L || width > 2147483647L {
        errors.push(
          issue(
            "invalid_range", path, "Range must contain 1..2147483647 values",
          ),
        )
      }
    }
    BooleanChance(chance) =>
      if chance < 0 || chance > 1000 {
        errors.push(
          issue("invalid_probability", path, "Probability must be in 0..1000"),
        )
      }
    Choice(values) => {
      if values.is_empty() {
        errors.push(
          issue("empty_choice", path, "Choice requires at least one value"),
        )
      }
      if values.any(v => v == Null) {
        errors.push(
          issue(
            "null_choice", path, "Use null_per_mille to express nullable values",
          ),
        )
      }
    }
    Pattern(alphabet, length) =>
      if alphabet.is_empty() || length < 0 || length > 65536 {
        errors.push(
          issue(
            "invalid_pattern", path, "Pattern requires an alphabet and length in 0..65536",
          ),
        )
      }
    Concat(names, _) =>
      if names.is_empty() {
        errors.push(issue("empty_concat", path, "Concat requires fields"))
      }
    _ => ()
  }
  errors
}

///|
/// Validate names, cardinalities, references and DAGs before generating rows.
pub fn compile(
  model : Model,
  context? : Context = Context::new(1U),
) -> Result[Plan, Array[Issue]] {
  let errors : Array[Issue] = []
  let limits = context.limits
  let reference = match reference_date(context.reference_time) {
    Ok(date) => date
    Err(error) => return Err([error])
  }
  if limits.max_entities <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_rows <= 0 ||
    limits.max_cells <= 0 ||
    limits.max_attempts <= 0 ||
    limits.max_text_units <= 0 {
    return Err([
      issue("invalid_limits", "limits", "All limits must be positive"),
    ])
  }
  if !valid_name(model.name) {
    errors.push(
      issue(
        "invalid_name", "model", "Expected 1..128 ASCII identifier characters",
      ),
    )
  }
  if model.entities.length() > limits.max_entities {
    return Err([issue("entity_limit", "entities", "Too many entities")])
  }
  let entities : Map[String, Entity] = Map([])
  let mut total_rows = 0L
  let mut total_cells = 0L
  for entity in model.entities {
    if !valid_name(entity.name) {
      errors.push(issue("invalid_name", entity.name, "Invalid entity name"))
    }
    if entities.contains(entity.name) {
      errors.push(
        issue("duplicate_entity", entity.name, "Entity names must be unique"),
      )
    }
    entities[entity.name] = entity
    if entity.count < 0 {
      errors.push(
        issue("negative_count", entity.name, "Row count cannot be negative"),
      )
    }
    total_rows += entity.count.max(0).to_int64()
    total_cells += entity.count.max(0).to_int64() *
      entity.fields.length().to_int64()
    if entity.fields.length() > limits.max_fields {
      errors.push(issue("field_limit", entity.name, "Too many fields"))
    }
    let fields : Map[String, Bool] = Map([])
    let mut primary_count = 0
    for field in entity.fields {
      let path = entity.name + "." + field.name
      if !valid_name(field.name) {
        errors.push(issue("invalid_name", path, "Invalid field name"))
      }
      if fields.contains(field.name) {
        errors.push(
          issue("duplicate_field", path, "Field names must be unique"),
        )
      }
      fields[field.name] = true
      if field.primary {
        primary_count += 1
      }
      if field.null_per_mille < 0 ||
        field.null_per_mille > 1000 ||
        (field.primary && field.null_per_mille != 0) {
        errors.push(
          issue(
            "invalid_nullable", path, "Nullable probability must be 0..1000; primary keys cannot be nullable",
          ),
        )
      }
      for error in check_generator(field.generator, path) {
        errors.push(error)
      }
      if field.generator is DateOffset(min, max) {
        if reference.add_days(min) is Err(_) ||
          reference.add_days(max) is Err(_) {
          errors.push(
            issue("date_overflow", path, "Date offset exceeds years 1..9999"),
          )
        }
      }
      if field.generator is Sequence(start, step) && entity.count > 0 {
        let end = start.to_int64() +
          (entity.count - 1).to_int64() * step.to_int64()
        if end < -2147483648L || end > 2147483647L {
          errors.push(
            issue("sequence_overflow", path, "Sequence exceeds Int32 bounds"),
          )
        }
      }
    }
    if primary_count > 1 {
      errors.push(
        issue("multiple_primary", entity.name, "Use one primary key field"),
      )
    }
    for field in entity.fields {
      for dep in field.generator.field_dependencies() {
        if !fields.contains(dep) {
          errors.push(
            issue(
              "missing_field",
              entity.name + "." + field.name,
              "Unknown dependency: " + dep,
            ),
          )
        }
      }
    }
  }
  if total_rows > limits.max_rows.to_int64() {
    errors.push(issue("row_limit", "entities", "Total rows exceed the limit"))
  }
  if total_cells > limits.max_cells.to_int64() {
    errors.push(issue("cell_limit", "entities", "Total cells exceed the limit"))
  }
  for entity in model.entities {
    for field in entity.fields {
      let path = entity.name + "." + field.name
      let reference = match field.generator {
        Reference(target, key) => Some((target, key, None))
        Lookup(_, target, key, value) => Some((target, key, Some(value)))
        _ => None
      }
      if reference is Some((target, key, value)) {
        match entities.get(target) {
          None =>
            errors.push(
              issue("missing_entity", path, "Unknown entity: " + target),
            )
          Some(parent) => {
            match parent.field(key) {
              None =>
                errors.push(
                  issue("missing_key", path, "Unknown reference key: " + key),
                )
              Some(key_field) => {
                if !key_field.unique && !key_field.primary {
                  errors.push(
                    issue(
                      "nonunique_reference", path, "References require a unique key",
                    ),
                  )
                }
                if key_field.null_per_mille != 0 {
                  errors.push(
                    issue(
                      "nullable_reference_key", path, "Reference key cannot be nullable",
                    ),
                  )
                }
              }
            }
            if value is Some(name) && parent.field(name) is None {
              errors.push(
                issue("missing_lookup", path, "Unknown lookup field: " + name),
              )
            }
            if parent.count == 0 &&
              entity.count > 0 &&
              field.null_per_mille < 1000 {
              errors.push(
                issue(
                  "empty_reference", path, "Nonempty child requires parent rows",
                ),
              )
            }
          }
        }
      }
    }
  }
  if !errors.is_empty() {
    return Err(errors)
  }
  let names = model.entities.map(e => e.name)
  let deps = model.entities.map(e => {
    let result : Array[String] = []
    for field in e.fields {
      if field.generator.entity_dependency() is Some(name) {
        result.push(name)
      }
    }
    result
  })
  let entity_order = match ordered_nodes(names, deps, "entities") {
    Ok(order) => order
    Err(errors) => return Err(errors)
  }
  let field_orders : Array[Array[Int]] = []
  for entity in model.entities {
    match
      ordered_nodes(
        entity.fields.map(f => f.name),
        entity.fields.map(f => f.generator.field_dependencies()),
        entity.name,
      ) {
      Ok(order) => field_orders.push(order)
      Err(errors) => return Err(errors)
    }
  }
  Ok({ model: model.snapshot(), context, entity_order, field_orders, })
}

///|
pub extend Plan with @moonbitlang/core/debug.Debug::{to_repr}
