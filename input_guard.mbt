///|
/// Bound nesting before invoking the JSON parser. Delimiters inside quoted text
/// do not count. Syntax and escape validity remain the JSON parser's job.
fn guard_json(
  text : String,
  max_units : Int,
  path : String,
) -> Result[Unit, Issue] {
  if max_units <= 0 || text.length() > max_units {
    return Err(
      issue("input_limit", path, "JSON input exceeds the configured size"),
    )
  }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for c in text.iter() {
    if quoted {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
      continue
    }
    match c {
      '"' => quoted = true
      '{' | '[' => {
        depth += 1
        if depth > 64 {
          return Err(
            issue("nesting_limit", path, "JSON nesting exceeds 64 levels"),
          )
        }
      }
      '}' | ']' => depth -= 1
      _ => ()
    }
  }
  Ok(())
}
