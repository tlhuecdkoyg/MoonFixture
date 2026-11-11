///|
/// Parse a JSON number's mathematical integer value without Double rounding.
/// Exponents saturate above the input length plus ten: no nonzero coefficient
/// of this length can cancel that exponent into the Int32 range. Work is linear
/// in the bounded input text, with no expansion of exponent-sized zero strings.
fn exact_json_integer(text : String, path : String) -> Int32 raise ConfigError {
  let size = text.length()
  if size == 0 {
    raise InvalidConfig(path, "Expected a JSON number")
  }
  let negative = text[0] == 45
  let mut index = if negative { 1 } else { 0 }
  let coefficient_start = index
  if index >= size || text[index] < 48 || text[index] > 57 {
    raise InvalidConfig(path, "Expected a JSON number")
  }
  if text[index] == 48 {
    index += 1
  } else {
    while index < size && text[index] >= 48 && text[index] <= 57 {
      index += 1
    }
  }
  let mut fraction_digits = 0L
  if index < size && text[index] == 46 {
    index += 1
    let start = index
    while index < size && text[index] >= 48 && text[index] <= 57 {
      index += 1
    }
    if index == start {
      raise InvalidConfig(
        path, "Expected decimal digits after the decimal point",
      )
    }
    fraction_digits = (index - start).to_int64()
  }
  let coefficient_end = index
  let mut exponent = 0L
  if index < size && (text[index] == 69 || text[index] == 101) {
    index += 1
    let exponent_negative = index < size && text[index] == 45
    if index < size && (text[index] == 43 || text[index] == 45) {
      index += 1
    }
    let start = index
    let cap = size.to_int64() + 10L
    while index < size && text[index] >= 48 && text[index] <= 57 {
      let digit = (text[index].to_int() - 48).to_int64()
      exponent = if exponent > (cap - digit) / 10L {
        cap
      } else {
        exponent * 10L + digit
      }
      index += 1
    }
    if index == start {
      raise InvalidConfig(path, "Expected decimal exponent digits")
    }
    if exponent_negative {
      exponent = -exponent
    }
  }
  if index != size {
    raise InvalidConfig(path, "Expected a JSON number")
  }
  let mut digits = 0
  let mut first = -1
  let mut last = -1
  for index in coefficient_start..<coefficient_end {
    let digit = text[index]
    if digit == 46 {
      continue
    }
    if digit != 48 {
      if first == -1 {
        first = digits
      }
      last = digits
    }
    digits += 1
  }
  if first == -1 {
    return 0
  }
  let trailing_zeros = (digits - last - 1).to_int64()
  let power = exponent - fraction_digits + trailing_zeros
  if power < 0L {
    raise InvalidConfig(path, "Expected an integer")
  }
  if (last - first + 1).to_int64() + power > 10L {
    raise InvalidConfig(path, "Integer outside Int32 bounds")
  }
  let mut position = 0
  let mut magnitude = 0L
  for index in coefficient_start..<coefficient_end {
    if text[index] == 46 {
      continue
    }
    if position >= first && position <= last {
      magnitude = magnitude * 10L + (text[index].to_int() - 48).to_int64()
    }
    position += 1
  }
  for _ in 0..<power.to_int() {
    magnitude *= 10L
  }
  let value = if negative { -magnitude } else { magnitude }
  if value < -2147483648L || value > 2147483647L {
    raise InvalidConfig(path, "Integer outside Int32 bounds")
  }
  value.to_int()
}
