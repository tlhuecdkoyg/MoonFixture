///|
pub(all) struct Options {
  command : String
  input : String
  output : String?
  model_file : String?
  seed : UInt
  reference_time : String
  format : String
  table : String?
  batch_size : Int
  max_input : Int
  overwrite : Bool
}

///|
pub fn help() -> String {
  (
    #|MoonFixture 0.1.1 — reproducible relational test data
    #|Usage: moonfixture <command> <input.json|-> [options]
    #|Commands:
    #|  generate  Build a dataset from a model
    #|  plan      Validate a model and show dependency order
    #|  manifest  Save complete reproducible generation inputs
    #|  replay    Regenerate a dataset from a manifest
    #|  validate  Validate a dataset against --model <model.json>
    #|Options:
    #|  --seed <0..4294967295>           Default: 1
    #|  --reference-time <UTC>          Default: 2026-01-01T00:00:00Z
    #|  --format <json|ndjson|csv|sqlite> Default: json
    #|  --table <name>                  Required for NDJSON/CSV
    #|  --output <path|->               Default: stdout
    #|  --model <path>                  Validation model
    #|  --batch-size <positive int>     SQLite rows per batch; default 500
    #|  --max-input <bytes>             Per input; default 16777216
    #|  --force                         Allow overwriting an output file
    #|  --help | --version
    #|Exit codes: 0 success; 1 model/data failure; 2 usage/I/O failure.
  )
}

///|
fn unsigned(text : String) -> UInt? {
  if text.is_empty() || text.length() > 10 {
    return None
  }
  let mut result = 0L
  for c in text.iter() {
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10L + (c.to_int() - 48).to_int64()
    if result > 4294967295L {
      return None
    }
  }
  Some(result.to_int().reinterpret_as_uint())
}

///|
fn positive(text : String) -> Int? {
  match unsigned(text) {
    Some(number) =>
      if number > 0U && number <= 2147483647U {
        Some(number.reinterpret_as_int())
      } else {
        None
      }
    None => None
  }
}

///|
pub fn parse_args(args : Array[String]) -> Result[Options, String] {
  let mut command = "help"
  let mut input = ""
  let mut output : String? = None
  let mut model_file : String? = None
  let mut seed = 1U
  let mut reference_time = "2026-01-01T00:00:00Z"
  let mut format = "json"
  let mut table : String? = None
  let mut batch_size = 500
  let mut max_input = 16777216
  let mut overwrite = false
  let seen : Map[String, Bool] = Map([])
  let mut index = 0
  if !args.is_empty() {
    command = match args[0] {
      "--help" => "help"
      "--version" => "version"
      other => other
    }
    index = 1
  }
  if !["help", "version", "generate", "plan", "manifest", "replay", "validate"].contains(
      command,
    ) {
    return Err("Unknown command: " + command)
  }
  while index < args.length() {
    let arg = args[index]
    index += 1
    if !arg.has_prefix("--") {
      if !input.is_empty() {
        return Err("Only one input path is allowed")
      }
      input = arg
      continue
    }
    if seen.contains(arg) {
      return Err("Repeated option: " + arg)
    }
    seen[arg] = true
    if arg == "--force" {
      overwrite = true
      continue
    }
    if ![
        "--output", "--model", "--seed", "--reference-time", "--format", "--table",
        "--batch-size", "--max-input",
      ].contains(arg) {
      return Err("Unknown option: " + arg)
    }
    if index >= args.length() {
      return Err("Missing value for " + arg)
    }
    let value = args[index]
    index += 1
    match arg {
      "--output" => output = Some(value)
      "--model" => model_file = Some(value)
      "--seed" =>
        match unsigned(value) {
          Some(number) => seed = number
          None => return Err("Seed must be a UInt32 decimal")
        }
      "--reference-time" => reference_time = value
      "--format" => format = value
      "--table" => table = Some(value)
      "--batch-size" =>
        match positive(value) {
          Some(number) => batch_size = number
          None => return Err("Batch size must be a positive Int32")
        }
      "--max-input" =>
        match positive(value) {
          Some(number) => max_input = number
          None => return Err("Input limit must be a positive Int32")
        }
      _ => ()
    }
  }
  if command == "help" || command == "version" {
    if !input.is_empty() || !seen.is_empty() {
      return Err("Help/version take no other arguments")
    }
  } else if input.is_empty() {
    return Err("Input path is required; use - for stdin")
  }
  if !["json", "ndjson", "csv", "sqlite"].contains(format) {
    return Err("Unsupported output format")
  }
  if (format == "ndjson" || format == "csv") && table is None {
    return Err("This format requires --table")
  }
  if command == "validate" && model_file is None {
    return Err("Validation requires --model")
  }
  if model_file == Some("-") {
    return Err("--model must name a file")
  }
  if command != "validate" && model_file is Some(_) {
    return Err("--model applies only to validate")
  }
  if command != "generate" &&
    (
      seen.contains("--format") ||
      seen.contains("--table") ||
      seen.contains("--batch-size")
    ) {
    return Err("Format, table and batch-size apply only to generate")
  }
  if command == "replay" || command == "validate" {
    if seen.contains("--seed") || seen.contains("--reference-time") {
      return Err("Seed and reference time are read from the input")
    }
  }
  if table is Some(_) && format != "ndjson" && format != "csv" {
    return Err("--table applies only to NDJSON or CSV")
  }
  Ok({
    command,
    input,
    output,
    model_file,
    seed,
    reference_time,
    format,
    table,
    batch_size,
    max_input,
    overwrite,
  })
}
