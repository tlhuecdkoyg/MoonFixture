///|
test "xorshift32 reference vector and zero handling" {
  let rng = @MoonFixture.Random::new(1U)
  assert_eq(rng.next(), 270369U)
  assert_eq(rng.next(), 67634689U)
  assert_eq(rng.next(), 2647435461U)
  assert_true(@MoonFixture.Random::new(0U).next() != 0U)
}

///|
test "stream replay and bounded samples" {
  let a = @MoonFixture.stream(42U, "orders", "price", 7)
  let b = @MoonFixture.stream(42U, "orders", "price", 7)
  for _ in 0..<100 {
    assert_eq(a.next(), b.next())
  }
  let rng = @MoonFixture.Random::new(12U)
  assert_eq(rng.below(0), None)
  for bound in [1, 3, 100, 2147483647] {
    for _ in 0..<100 {
      let value = rng.below(bound).unwrap()
      assert_true(value >= 0 && value < bound)
    }
  }
}

///|
test "value keys preserve scalar identity" {
  assert_true(
    @MoonFixture.Value::Null.key() != @MoonFixture.Value::Text("").key(),
  )
  assert_true(
    @MoonFixture.Value::Integer(1).key() != @MoonFixture.Value::Text("1").key(),
  )
}
