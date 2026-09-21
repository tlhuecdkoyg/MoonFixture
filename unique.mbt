///|
/// A lazy Fisher-Yates permutation uses memory proportional to draws, not domain.
priv struct UniqueDomain {
  generator : Generator
  mut remaining : Int
  swaps : Map[Int, Int]
  values : Array[Value]
  alphabet : Array[Char]
}

///|
fn unique_domain(
  generator : Generator,
  tables : Map[String, Table],
) -> UniqueDomain? {
  let values : Array[Value] = []
  let alphabet : Array[Char] = []
  let size = match generator {
    IntegerRange(min, max) => (max.to_int64() - min.to_int64() + 1L).to_int()
    BooleanChance(chance) => {
      if chance < 1000 {
        values.push(Boolean(false))
      }
      if chance > 0 {
        values.push(Boolean(true))
      }
      values.length()
    }
    Constant(Null) => return None
    Constant(value) => {
      values.push(value)
      1
    }
    Choice(choices) => {
      let seen : Map[String, Bool] = Map([])
      for value in choices {
        if !seen.contains(value.key()) {
          seen[value.key()] = true
          values.push(value)
        }
      }
      values.length()
    }
    Reference(target, key) => {
      for row in tables.get(target).unwrap().rows {
        if row.get(key) is Some(value) {
          values.push(value)
        }
      }
      values.length()
    }
    Pattern(chars, length) => {
      for c in chars.iter() {
        if !alphabet.contains(c) {
          alphabet.push(c)
        }
      }
      let mut count = 1L
      for _ in 0..<length {
        count *= alphabet.length().to_int64()
        if count > 2147483647L {
          return None
        }
      }
      count.to_int()
    }
    _ => return None
  }
  Some({ generator, remaining: size, swaps: Map([]), values, alphabet, })
}

///|
fn UniqueDomain::draw(self : UniqueDomain, rng : Random) -> Value? {
  if self.remaining == 0 {
    return None
  }
  let slot = rng.below(self.remaining).unwrap()
  let index = self.swaps.get(slot).unwrap_or(slot)
  let last = self.remaining - 1
  self.swaps[slot] = self.swaps.get(last).unwrap_or(last)
  self.remaining = last
  match self.generator {
    IntegerRange(min, _) => Some(Integer(min + index))
    Pattern(_, length) => {
      let out = StringBuilder()
      let mut rank = index
      for _ in 0..<length {
        out.write_char(self.alphabet[rank % self.alphabet.length()])
        rank = rank / self.alphabet.length()
      }
      Some(Text(out.to_string()))
    }
    _ => Some(self.values[index])
  }
}
