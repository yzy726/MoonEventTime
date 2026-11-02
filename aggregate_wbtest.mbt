///|
test "invalid/aggregate count overflow preflight" {
  let s : Stats = { count: I64_MAX, sum: 0L, min: 0L, max: 0L, }
  assert_eq(s.add(0L), Err(AggregateOverflow))
}

///|
test "edge/time checked subtraction handles minimum operand" {
  assert_eq(checked_sub(-1L, I64_MIN), Some(I64_MAX))
  assert_eq(checked_sub(0L, I64_MIN), None)
}

///|
test "edge/time checked subtraction handles maximum operand" {
  assert_eq(checked_sub(-1L, I64_MAX), Some(I64_MIN))
  assert_eq(checked_sub(-2L, I64_MAX), None)
}
