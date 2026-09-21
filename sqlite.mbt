///|
pub(all) struct SqlBatch {
  table : String
  sql : String
  parameters : Array[Array[Value]]
}

///|
pub(all) struct SqliteBundle {
  schema : Array[String]
  batches : Array[SqlBatch]
}

///|
fn sql_identifier(name : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in name.iter() {
    if c == '"' {
      out.write_char('"')
    }
    out.write_char(c)
  }
  out.write_char('"')
  out.to_string()
}

///|
fn sqlite_create(entity : Entity) -> Result[String, Issue] {
  if entity.fields.is_empty() {
    return Err(
      issue(
        "sqlite_empty_columns",
        entity.name,
        "SQLite tables require at least one column",
      ),
    )
  }
  let columns : Array[String] = []
  let references : Array[String] = []
  for field in entity.fields {
    let constraint = if field.primary {
      " PRIMARY KEY NOT NULL"
    } else if field.unique {
      " UNIQUE"
    } else {
      ""
    }
    // No affinity: preserve JSON string "1" separately from integer 1.
    columns.push(sql_identifier(field.name) + constraint)
    if field.generator is Reference(target, key) {
      references.push(
        "FOREIGN KEY (" +
        sql_identifier(field.name) +
        ") REFERENCES " +
        sql_identifier(target) +
        " (" +
        sql_identifier(key) +
        ")",
      )
    }
  }
  for reference in references {
    columns.push(reference)
  }
  Ok(
    "CREATE TABLE " +
    sql_identifier(entity.name) +
    " (" +
    columns.join(", ") +
    ")",
  )
}

///|
/// Build driver-neutral SQLite statements. Bind parameters; never interpolate them.
/// The caller enables foreign_keys before starting a transaction and rolls back
/// all statements if any insertion fails. This function performs no database I/O.
pub fn sqlite_bundle(
  model : Model,
  data : Dataset,
  batch_size? : Int = 500,
) -> Result[SqliteBundle, Array[Issue]] {
  if batch_size <= 0 {
    return Err([
      issue("invalid_batch_size", "sqlite", "Batch size must be positive"),
    ])
  }
  let report = validate_dataset(model, data)
  if !report.is_valid() {
    return Err(report.issues)
  }
  let plan = match
    compile(
      model,
      context=Context::new(data.seed, reference_time=data.reference_time),
    ) {
    Ok(plan) => plan
    Err(errors) => return Err(errors)
  }
  let schema : Array[String] = []
  let batches : Array[SqlBatch] = []
  for ei in plan.entity_order {
    let entity = model.entities[ei]
    match sqlite_create(entity) {
      Ok(sql) => schema.push(sql)
      Err(error) => return Err([error])
    }
    let table = data.table(entity.name).unwrap()
    for field in entity.fields {
      let mut boolean = false
      let mut integer = false
      for row in table.rows {
        match row.get(field.name) {
          Some(Boolean(_)) => boolean = true
          Some(Integer(_)) => integer = true
          _ => ()
        }
      }
      if boolean && integer {
        return Err([
          issue(
            "sqlite_mixed_numeric",
            entity.name + "." + field.name,
            "SQLite cannot preserve a mixed boolean/integer column",
          ),
        ])
      }
    }
    let columns = entity.fields.map(f => sql_identifier(f.name)).join(", ")
    let placeholders = entity.fields.map(_ => "?").join(", ")
    let sql = "INSERT INTO " +
      sql_identifier(entity.name) +
      " (" +
      columns +
      ") VALUES (" +
      placeholders +
      ")"
    for rows in table.batches(batch_size).unwrap() {
      let parameters = rows.map(row => {
        entity.fields.map(field => row.get(field.name).unwrap())
      })
      batches.push({ table: entity.name, sql, parameters, })
    }
  }
  Ok({ schema, batches, })
}

///|
pub fn SqliteBundle::to_json(self : SqliteBundle) -> Json {
  Json::object(
    Map([
      ("format", Json::string("moonfixture.sqlite.v1")),
      ("foreign_keys", Json::boolean(true)),
      ("schema", Json::array(self.schema.map(Json::string))),
      (
        "batches",
        Json::array(
          self.batches.map(batch => {
            Json::object(
              Map([
                ("table", Json::string(batch.table)),
                ("sql", Json::string(batch.sql)),
                (
                  "parameters",
                  Json::array(
                    batch.parameters.map(row => {
                      Json::array(row.map(v => v.to_json()))
                    }),
                  ),
                ),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}

///|
pub fn SqliteBundle::to_json_text(self : SqliteBundle) -> String {
  canonical_json(self.to_json())
}
