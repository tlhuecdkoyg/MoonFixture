///|
/// Stable JSON output uses declaration order instead of map iteration order.
pub fn Row::to_json_text(self : Row) -> String {
  let fields = self.cells.map(cell => {
    Json::string(cell.name).stringify() + ":" + cell.value.to_json().stringify()
  })
  "{" + fields.join(",") + "}"
}

///|
pub fn Table::to_json_text(self : Table) -> String {
  "{\"name\":" +
  Json::string(self.name).stringify() +
  ",\"rows\":[" +
  self.rows.map(r => r.to_json_text()).join(",") +
  "]}"
}

///|
pub fn Dataset::to_json_text(self : Dataset) -> String {
  "{\"format\":\"moonfixture.dataset.v1\",\"model\":" +
  Json::string(self.model).stringify() +
  ",\"seed\":" +
  Json::string(self.seed.to_string()).stringify() +
  ",\"algorithm\":" +
  Json::string(self.algorithm).stringify() +
  ",\"reference_time\":" +
  Json::string(self.reference_time).stringify() +
  ",\"tables\":[" +
  self.tables.map(t => t.to_json_text()).join(",") +
  "]}"
}

///|
pub fn Table::to_ndjson(self : Table) -> String {
  let out = StringBuilder()
  for row in self.rows {
    out.write_string(row.to_json_text())
    out.write_char('\n')
  }
  out.to_string()
}

///|
fn csv_cell(text : String) -> String {
  let out = StringBuilder()
  let quote = text.contains(",") ||
    text.contains("\"") ||
    text.contains("\n") ||
    text.contains("\r")
  if quote {
    out.write_char('"')
  }
  for c in text.iter() {
    if c == '"' {
      out.write_char('"')
    }
    out.write_char(c)
  }
  if quote {
    out.write_char('"')
  }
  out.to_string()
}

///|
/// CSV is an interchange representation; null and empty text both become empty.
pub fn Table::to_csv(self : Table, columns : Array[String]) -> String {
  let out = StringBuilder()
  out.write_string(columns.map(csv_cell).join(","))
  out.write_string("\r\n")
  for row in self.rows {
    let cells = columns.map(name => {
      match row.get(name) {
        Some(value) => csv_cell(value.display())
        None => ""
      }
    })
    out.write_string(cells.join(","))
    out.write_string("\r\n")
  }
  out.to_string()
}

///|
pub fn Table::batches(
  self : Table,
  size : Int,
) -> Result[Array[Array[Row]], Issue] {
  if size <= 0 {
    return Err(
      issue("invalid_batch_size", self.name, "Batch size must be positive"),
    )
  }
  let batches : Array[Array[Row]] = []
  let mut offset = 0
  while offset < self.rows.length() {
    let length = size.min(self.rows.length() - offset)
    batches.push(self.rows[offset:offset + length].to_owned())
    offset += length
  }
  Ok(batches)
}
