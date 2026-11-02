///|
test "valid/aggregate single measurement" {
  let s = @MoonEventTime.Stats::single(21L)
  assert_eq((s.count, s.sum, s.min, s.max), (1L, 21L, 21L, 21L))
}

///|
test "valid/aggregate mixed signed values" {
  let s = @MoonEventTime.Stats::single(5L).add(-8L).unwrap().add(7L).unwrap()
  assert_eq((s.count, s.sum, s.min, s.max), (3L, 4L, -8L, 7L))
}

///|
test "edge/aggregate zero values" {
  let s = @MoonEventTime.Stats::single(0L).add(0L).unwrap()
  assert_eq((s.count, s.sum, s.min, s.max), (2L, 0L, 0L, 0L))
}

///|
test "edge/aggregate maximum sum is representable" {
  let s = @MoonEventTime.Stats::single(9223372036854775806L).add(1L).unwrap()
  assert_eq(s.sum, 9223372036854775807L)
}

///|
test "edge/aggregate minimum sum is representable" {
  let s = @MoonEventTime.Stats::single(-9223372036854775807L).add(-1L).unwrap()
  assert_eq(s.sum, -9223372036854775808L)
}

///|
test "invalid/aggregate positive overflow leaves value unchanged" {
  let s = @MoonEventTime.Stats::single(9223372036854775807L)
  assert_eq(s.add(1L), Err(@MoonEventTime.AggregateOverflow))
  assert_eq(s.count, 1L)
  assert_eq(s.sum, 9223372036854775807L)
}

///|
test "invalid/aggregate negative overflow" {
  let s = @MoonEventTime.Stats::single(-9223372036854775808L)
  assert_eq(s.add(-1L), Err(@MoonEventTime.AggregateOverflow))
}

///|
test "edge/aggregate opposite extrema cancel safely" {
  let s = @MoonEventTime.Stats::single(-9223372036854775808L)
    .add(9223372036854775807L)
    .unwrap()
  assert_eq(
    (s.count, s.sum, s.min, s.max),
    (2L, -1L, -9223372036854775808L, 9223372036854775807L),
  )
}

///|
test "valid/aggregate arrival permutations agree without intermediate overflow" {
  let a = @MoonEventTime.Stats::single(12L).add(-3L).unwrap().add(4L).unwrap()
  let b = @MoonEventTime.Stats::single(4L).add(12L).unwrap().add(-3L).unwrap()
  assert_eq(a, b)
}
