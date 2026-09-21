///|
pub(all) struct Date {
  year : Int
  month : Int
  day : Int
} derive(Eq, Debug)

///|
pub extend Date with Eq::{equal, not_equal}

///|
pub extend Date with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn month_days(year : Int, month : Int) -> Int {
  match month {
    2 => if leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
pub fn Date::new(year : Int, month : Int, day : Int) -> Result[Date, Issue] {
  if year < 1 || year > 9999 || month < 1 || month > 12 {
    return Err(
      issue("invalid_date", "date", "Year must be 1..9999 and month 1..12"),
    )
  }
  if day < 1 || day > month_days(year, month) {
    return Err(
      issue("invalid_date", "date", "Day does not exist in this month"),
    )
  }
  Ok({ year, month, day, })
}

///|
fn decimal_digits(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let mut number = 0
  for c in text.iter() {
    if c < '0' || c > '9' {
      return None
    }
    number = number * 10 + c.to_int() - 48
  }
  Some(number)
}

///|
pub fn parse_date(text : String) -> Result[Date, Issue] {
  if text.length() != 10 || text[4] != 45 || text[7] != 45 {
    return Err(issue("invalid_date", "date", "Expected YYYY-MM-DD"))
  }
  match
    (
      decimal_digits(text[0:4].to_owned()),
      decimal_digits(text[5:7].to_owned()),
      decimal_digits(text[8:10].to_owned()),
    ) {
    (Some(year), Some(month), Some(day)) => Date::new(year, month, day)
    _ => Err(issue("invalid_date", "date", "Expected decimal date components"))
  }
}

///|
fn pad_decimal(number : Int, width : Int) -> String {
  let text = number.to_string()
  let out = StringBuilder()
  for _ in 0..<(width - text.length()).max(0) {
    out.write_char('0')
  }
  out.write_string(text)
  out.to_string()
}

///|
pub fn Date::to_string(self : Date) -> String {
  pad_decimal(self.year, 4) +
  "-" +
  pad_decimal(self.month, 2) +
  "-" +
  pad_decimal(self.day, 2)
}

///|
fn days_before_year(year : Int) -> Int {
  let previous = year - 1
  previous * 365 + previous / 4 - previous / 100 + previous / 400
}

///|
pub fn Date::ordinal(self : Date) -> Result[Int, Issue] {
  match Date::new(self.year, self.month, self.day) {
    Err(error) => Err(error)
    Ok(_) => {
      let mut days = days_before_year(self.year) + self.day - 1
      for month in 1..<self.month {
        days += month_days(self.year, month)
      }
      Ok(days)
    }
  }
}

///|
pub fn Date::add_days(self : Date, delta : Int) -> Result[Date, Issue] {
  let ordinal = match self.ordinal() {
    Ok(n) => n.to_int64() + delta.to_int64()
    Err(error) => return Err(error)
  }
  if ordinal < 0L || ordinal >= days_before_year(10000).to_int64() {
    return Err(
      issue("date_overflow", "date", "Date offset exceeds years 1..9999"),
    )
  }
  let target = ordinal.to_int()
  let mut low = 1
  let mut high = 10000
  while low + 1 < high {
    let middle = low + (high - low) / 2
    if days_before_year(middle) <= target {
      low = middle
    } else {
      high = middle
    }
  }
  let mut rest = target - days_before_year(low)
  let mut month = 1
  while rest >= month_days(low, month) {
    rest -= month_days(low, month)
    month += 1
  }
  Ok({ year: low, month, day: rest + 1, })
}

///|
/// UTC reference timestamps have second precision, no leap seconds or offsets.
fn reference_date(text : String) -> Result[Date, Issue] {
  if text.length() != 20 ||
    text[10] != 84 ||
    text[13] != 58 ||
    text[16] != 58 ||
    text[19] != 90 {
    return Err(
      issue(
        "invalid_reference_time", "reference_time", "Expected YYYY-MM-DDTHH:MM:SSZ",
      ),
    )
  }
  match
    (
      decimal_digits(text[11:13].to_owned()),
      decimal_digits(text[14:16].to_owned()),
      decimal_digits(text[17:19].to_owned()),
    ) {
    (Some(hour), Some(minute), Some(second)) =>
      if hour > 23 || minute > 59 || second > 59 {
        return Err(
          issue(
            "invalid_reference_time", "reference_time", "Invalid UTC clock components",
          ),
        )
      }
    _ =>
      return Err(
        issue(
          "invalid_reference_time", "reference_time", "Expected numeric UTC clock components",
        ),
      )
  }
  parse_date(text[0:10].to_owned())
}
