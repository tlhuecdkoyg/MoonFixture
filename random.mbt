///|
/// Versioned xorshift32 stream; not suitable for secrets or cryptography.
pub struct Random {
  mut state : UInt
} derive(Debug)

///|
pub fn Random::new(seed : UInt) -> Random {
  { state: if seed == 0U { 0x6D2B79F5U } else { seed }, }
}

///|
pub fn Random::next(self : Random) -> UInt {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  x
}

///|
/// Uniform bounded selection using rejection rather than biased modulo alone.
pub fn Random::below(self : Random, bound : Int) -> Int? {
  if bound <= 0 {
    return None
  }
  let b = bound.reinterpret_as_uint()
  let threshold = (0U - b) % b
  for ;; {
    let value = self.next()
    if value >= threshold {
      return Some((value % b).reinterpret_as_int())
    }
  }
}

///|
fn mix_name(state : UInt, name : String) -> UInt {
  let mut hash = state
  // Scalar values are encoded into four fixed little-endian bytes.
  for char in name.iter() {
    let scalar = char.to_int().reinterpret_as_uint()
    for shift in [0, 8, 16, 24] {
      hash = (hash ^ ((scalar >> shift) & 255U)) * 16777619U
    }
  }
  // Include a separator that is not an encoded Unicode scalar.
  (hash ^ 0xFFFFFFFFU) * 16777619U
}

///|
/// Stable stream identity is (seed, entity, field, row, attempt).
pub fn stream(
  seed : UInt,
  entity : String,
  field : String,
  row : Int,
  attempt? : Int = 0,
) -> Random {
  let hash = mix_name(mix_name(2166136261U ^ seed, entity), field)
  let hash = (hash ^ row.reinterpret_as_uint()) * 16777619U
  Random::new((hash ^ attempt.reinterpret_as_uint()) * 16777619U)
}

///|
pub fn algorithm_version() -> String {
  "moonfixture-xorshift32-scalar-fnv1a-v1"
}

///|
pub extend Random with @moonbitlang/core/debug.Debug::{to_repr}
