///|
pub(all) struct BatchProgress {
  rows_accepted : Int
  batches_accepted : Int
  completed : Bool
}

///|
/// Visit copied batches without constructing an array of all batches. Returning
/// false declines the current batch and stops. Already accepted batches are not
/// rolled back. This bounds export buffering, not the retained dataset itself.
pub fn Table::visit_batches(
  self : Table,
  size : Int,
  consume : (Array[Row]) -> Bool,
  offset? : Int = 0,
) -> Result[BatchProgress, Issue] {
  if size <= 0 {
    return Err(
      issue("invalid_batch_size", self.name, "Batch size must be positive"),
    )
  }
  if offset < 0 || offset > self.rows.length() {
    return Err(
      issue(
        "invalid_batch_offset",
        self.name,
        "Offset must identify a row boundary",
      ),
    )
  }
  let mut position = offset
  let mut batches_accepted = 0
  while position < self.rows.length() {
    let count = size.min(self.rows.length() - position)
    let batch : Array[Row] = []
    for ri in position..<(position + count) {
      batch.push({ cells: self.rows[ri].cells.copy(), })
    }
    if !consume(batch) {
      return Ok({
        rows_accepted: position - offset,
        batches_accepted,
        completed: false,
      })
    }
    position += count
    batches_accepted += 1
  }
  Ok({ rows_accepted: position - offset, batches_accepted, completed: true, })
}

///|
/// Encode one NDJSON chunk per callback, supporting backpressure and resumption
/// by accepted row count. Callers are responsible for durable write semantics.
pub fn Table::visit_ndjson(
  self : Table,
  size : Int,
  consume : (String) -> Bool,
  offset? : Int = 0,
) -> Result[BatchProgress, Issue] {
  self.visit_batches(
    size,
    rows => {
      let out = StringBuilder()
      for row in rows {
        out.write_string(row.to_json_text())
        out.write_char('\n')
      }
      consume(out.to_string())
    },
    offset~,
  )
}

///|
/// A CSV batch contains a header only at offset zero. Later chunks can be
/// concatenated verbatim. Use the same projection and size when resuming.
pub fn Table::visit_csv(
  self : Table,
  columns : Array[String],
  size : Int,
  consume : (String) -> Bool,
  offset? : Int = 0,
) -> Result[BatchProgress, Issue] {
  let mut first = offset == 0
  if self.rows.is_empty() && offset == 0 && size > 0 {
    let accepted = consume(columns.map(csv_cell).join(",") + "\r\n")
    return Ok({
      rows_accepted: 0,
      batches_accepted: if accepted {
        1
      } else {
        0
      },
      completed: accepted,
    })
  }
  self.visit_batches(
    size,
    rows => {
      let out = StringBuilder()
      if first {
        out.write_string(columns.map(csv_cell).join(","))
        out.write_string("\r\n")
      }
      for row in rows {
        let cells = columns.map(name => {
          match row.get(name) {
            Some(value) => csv_cell(value.display())
            None => ""
          }
        })
        out.write_string(cells.join(","))
        out.write_string("\r\n")
      }
      let accepted = consume(out.to_string())
      if accepted {
        first = false
      }
      accepted
    },
    offset~,
  )
}
