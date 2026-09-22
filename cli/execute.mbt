///|
pub(all) struct Output {
  text : String
  diagnostics : Array[String]
  exit_code : Int
}

///|
fn success(text : String) -> Output {
  { text, diagnostics: [], exit_code: 0, }
}

///|
fn failure(issues : Array[@fixture.Issue]) -> Output {
  {
    text: "",
    diagnostics: issues.map(i => i.code + " at " + i.path + ": " + i.message),
    exit_code: 1,
  }
}

///|
pub fn execute(
  input : String,
  options : Options,
  model_text? : String = "",
) -> Output {
  if options.command == "help" {
    return success(help())
  }
  if options.command == "version" {
    return success("MoonFixture 0.1.1 (" + @fixture.algorithm_version() + ")")
  }
  if options.command == "replay" {
    return match @fixture.replay(input, max_units=options.max_input) {
      Ok(data) => success(data.to_json_text())
      Err(issues) => failure(issues)
    }
  }
  if options.command == "validate" {
    let model = match
      @fixture.parse_model(model_text, max_units=options.max_input) {
      Ok(model) => model
      Err(issue) => return failure([issue])
    }
    let data = match
      @fixture.parse_dataset(input, max_units=options.max_input) {
      Ok(data) => data
      Err(issue) => return failure([issue])
    }
    let report = @fixture.validate_dataset(model, data)
    return {
      text: report.to_json().stringify(),
      diagnostics: [],
      exit_code: if report.is_valid() {
        0
      } else {
        1
      },
    }
  }
  let model = match @fixture.parse_model(input, max_units=options.max_input) {
    Ok(model) => model
    Err(issue) => return failure([issue])
  }
  let context = @fixture.Context::new(
    options.seed,
    reference_time=options.reference_time,
  )
  let plan = match @fixture.compile(model, context~) {
    Ok(plan) => plan
    Err(issues) => return failure(issues)
  }
  if options.command == "plan" {
    return success(
      Json::object(
        Map([
          ("model", Json::string(model.name)),
          ("fingerprint", Json::string(model.fingerprint())),
          ("entity_order", Json::array(plan.entity_names().map(Json::string))),
        ]),
      ).stringify(),
    )
  }
  if options.command == "manifest" {
    return success(plan.replay_json())
  }
  let data = match plan.generate() {
    Ok(data) => data
    Err(issue) => return failure([issue])
  }
  match options.format {
    "json" => success(data.to_json_text())
    "sqlite" =>
      match @fixture.sqlite_bundle(model, data, batch_size=options.batch_size) {
        Ok(bundle) => success(bundle.to_json_text())
        Err(issues) => failure(issues)
      }
    "ndjson" | "csv" => {
      let name = match options.table {
        Some(name) => name
        None =>
          return {
            text: "",
            diagnostics: ["This format requires a table"],
            exit_code: 2,
          }
      }
      match data.table(name) {
        Some(table) =>
          if options.format == "ndjson" {
            success(table.to_ndjson())
          } else {
            success(
              table.to_csv(model.entity(name).unwrap().fields.map(f => f.name)),
            )
          }
        None =>
          { text: "", diagnostics: ["Unknown table: " + name], exit_code: 1, }
      }
    }
    _ => { text: "", diagnostics: ["Unsupported output format"], exit_code: 2, }
  }
}
