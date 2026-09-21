///|
/// Assertions over finished fixtures, independent of the generation model.
pub(all) enum Expectation {
  RowCount(String, Int, Int)
  NonNull(String, String)
  IntegerBounds(String, String, Int, Int)
  TextLength(String, String, Int, Int)
  LessEqual(String, String, String)
  SumEquals(String, String, Int64)
  RelatedCount(String, String, String, String, Int, Int)
}

///|
/// checked_rows counts row visits across assertions. Multiple rules may examine
/// the same row. A failure cap truncates diagnostics, not assertion evaluation.
pub fn check_expectations(
  data : Dataset,
  expectations : Array[Expectation],
  max_issues? : Int = 100,
) -> ValidationReport {
  let issues : Array[Issue] = []
  let mut truncated = false
  let mut checked_rows = 0
  fn add(code : String, path : String, message : String) -> Unit {
    if issues.length() >= max_issues.max(1) {
      truncated = true
    } else {
      issues.push(issue(code, path, message))
    }
  }
  for expectation in expectations {
    let name = match expectation {
      RowCount(name, _, _)
      | NonNull(name, _)
      | IntegerBounds(name, _, _, _)
      | TextLength(name, _, _, _)
      | LessEqual(name, _, _)
      | SumEquals(name, _, _)
      | RelatedCount(name, _, _, _, _, _) => name
    }
    let table = match data.table(name) {
      Some(table) => table
      None => {
        add("expectation_table", name, "Assertion table is missing")
        continue
      }
    }
    match expectation {
      RowCount(_, min, max) =>
        if min < 0 || min > max {
          add("invalid_expectation", name, "Row count bounds are invalid")
        } else if table.rows.length() < min || table.rows.length() > max {
          add(
            "expected_row_count", name, "Row count falls outside asserted bounds",
          )
        }
      NonNull(_, field) =>
        for ri in 0..<table.rows.length() {
          checked_rows += 1
          if table.rows[ri].get(field) == None ||
            table.rows[ri].get(field) == Some(Null) {
            add(
              "expected_non_null",
              validation_path(name, ri, field),
              "Expected a present non-null value",
            )
          }
        }
      IntegerBounds(_, field, min, max) => {
        if min > max {
          add(
            "invalid_expectation",
            name + "." + field,
            "Integer bounds are reversed",
          )
          continue
        }
        for ri in 0..<table.rows.length() {
          checked_rows += 1
          let valid = match table.rows[ri].get(field) {
            Some(Integer(value)) => value >= min && value <= max
            _ => false
          }
          if !valid {
            add(
              "expected_integer_bounds",
              validation_path(name, ri, field),
              "Expected an integer within bounds",
            )
          }
        }
      }
      TextLength(_, field, min, max) => {
        if min < 0 || min > max {
          add(
            "invalid_expectation",
            name + "." + field,
            "Text length bounds are invalid",
          )
          continue
        }
        for ri in 0..<table.rows.length() {
          checked_rows += 1
          let valid = match table.rows[ri].get(field) {
            Some(Text(text)) => {
              let length = text.to_array().length()
              length >= min && length <= max
            }
            _ => false
          }
          if !valid {
            add(
              "expected_text_length",
              validation_path(name, ri, field),
              "Expected text within Unicode scalar length bounds",
            )
          }
        }
      }
      LessEqual(_, left, right) =>
        for ri in 0..<table.rows.length() {
          checked_rows += 1
          let valid = match
            (table.rows[ri].get(left), table.rows[ri].get(right)) {
            (Some(Integer(a)), Some(Integer(b))) => a <= b
            _ => false
          }
          if !valid {
            add(
              "expected_order",
              validation_path(name, ri, left),
              "Expected two integers with left <= right",
            )
          }
        }
      SumEquals(_, field, expected) => {
        let mut sum = 0L
        let mut valid = true
        for ri in 0..<table.rows.length() {
          checked_rows += 1
          match table.rows[ri].get(field) {
            Some(Integer(value)) => sum += value.to_int64()
            _ => {
              valid = false
              add(
                "expected_sum_type",
                validation_path(name, ri, field),
                "Sum expects non-null integers",
              )
            }
          }
        }
        if valid && sum != expected {
          add(
            "expected_sum",
            name + "." + field,
            "Integer sum differs from the expected value",
          )
        }
      }
      RelatedCount(_, foreign_key, parent_name, parent_key, min, max) => {
        if min < 0 || min > max {
          add("invalid_expectation", name, "Related count bounds are invalid")
          continue
        }
        let parent = match data.table(parent_name) {
          Some(table) => table
          None => {
            add(
              "expectation_table", parent_name, "Parent assertion table is missing",
            )
            continue
          }
        }
        let counts : Map[String, Int] = Map([])
        for ri in 0..<parent.rows.length() {
          checked_rows += 1
          match parent.rows[ri].get(parent_key) {
            Some(Null) | None =>
              add(
                "expectation_parent_key",
                validation_path(parent_name, ri, parent_key),
                "Parent key must be non-null",
              )
            Some(value) => {
              if counts.contains(value.key()) {
                add(
                  "expectation_parent_key",
                  validation_path(parent_name, ri, parent_key),
                  "Parent key must be unique",
                )
              }
              counts[value.key()] = 0
            }
          }
        }
        for ri in 0..<table.rows.length() {
          checked_rows += 1
          match table.rows[ri].get(foreign_key) {
            Some(Null) => ()
            None =>
              add(
                "expectation_foreign_key",
                validation_path(name, ri, foreign_key),
                "Foreign key field is missing",
              )
            Some(value) =>
              match counts.get(value.key()) {
                Some(count) => counts[value.key()] = count + 1
                None =>
                  add(
                    "expectation_foreign_key",
                    validation_path(name, ri, foreign_key),
                    "No parent matches this foreign key",
                  )
              }
          }
        }
        // Report in parent row order, not hash-map iteration order.
        for ri in 0..<parent.rows.length() {
          if parent.rows[ri].get(parent_key) is Some(value) && value != Null {
            let count = counts.get(value.key()).unwrap_or(0)
            if count < min || count > max {
              add(
                "expected_related_count",
                validation_path(parent_name, ri, parent_key),
                "Child count falls outside asserted bounds",
              )
            }
          }
        }
      }
    }
  }
  { issues, checked_rows, truncated, }
}
