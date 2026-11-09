///|
fn bounds(t : Int64, size : Int64, origin~ : Int64 = 0L) -> (Int64, Int64) {
  let config = @MoonEventTime.Config::new(size, origin_ms=origin).unwrap()
  let w = config.assign(t, "sensor").unwrap()
  (w.start_ms, w.end_ms)
}

///|
test "valid/time zero and last millisecond" {
  assert_eq(bounds(0L, 10L), (0L, 10L))
  assert_eq(bounds(9L, 10L), (0L, 10L))
}

///|
test "edge/time endpoint starts next window" {
  assert_eq(bounds(10L, 10L), (10L, 20L))
}

///|
test "edge/time minus one floors down" {
  assert_eq(bounds(-1L, 10L), (-10L, 0L))
}

///|
test "edge/time exact negative boundary" {
  assert_eq(bounds(-10L, 10L), (-10L, 0L))
}

///|
test "edge/time below negative boundary" {
  assert_eq(bounds(-11L, 10L), (-20L, -10L))
}

///|
test "valid/time positive origin" {
  assert_eq(bounds(2L, 10L, origin=3L), (-7L, 3L))
  assert_eq(bounds(3L, 10L, origin=3L), (3L, 13L))
}

///|
test "valid/time negative origin" {
  assert_eq(bounds(-4L, 10L, origin=-3L), (-13L, -3L))
}

///|
test "edge/time one millisecond" {
  assert_eq(bounds(-1L, 1L), (-1L, 0L))
}

///|
test "edge/time extreme origin does not require overflowing subtraction" {
  assert_eq(bounds(0L, 10L, origin=-9223372036854775808L), (-8L, 2L))
  assert_eq(bounds(0L, 10L, origin=9223372036854775807L), (-3L, 7L))
}

///|
test "edge/time minimum representable aligned window" {
  assert_eq(
    bounds(-9223372036854775808L, 2L),
    (-9223372036854775808L, -9223372036854775806L),
  )
}

///|
test "invalid/time start underflow" {
  let c = @MoonEventTime.Config::new(10L).unwrap()
  assert_eq(
    c.assign(-9223372036854775808L, "a"),
    Err(@MoonEventTime.TimeOverflow),
  )
}

///|
test "invalid/time end overflow" {
  let c = @MoonEventTime.Config::new(1L).unwrap()
  assert_eq(
    c.assign(9223372036854775807L, "a"),
    Err(@MoonEventTime.TimeOverflow),
  )
}

///|
test "invalid/time zero size" {
  assert_eq(@MoonEventTime.Config::new(0L), Err(@MoonEventTime.InvalidConfig))
}

///|
test "invalid/time negative size" {
  assert_eq(@MoonEventTime.Config::new(-1L), Err(@MoonEventTime.InvalidConfig))
}

///|
test "invalid/time empty key" {
  let c = @MoonEventTime.Config::new(10L).unwrap()
  assert_eq(c.assign(0L, ""), Err(@MoonEventTime.InvalidKey))
}

///|
test "edge/time key budget is UTF8 bytes" {
  let limits = @MoonEventTime.Limits::new(max_key_bytes=3)
  let c = @MoonEventTime.Config::new(10L, limits~).unwrap()
  assert_true(c.assign(0L, "中") is Ok(_))
  assert_eq(c.assign(0L, "中文"), Err(@MoonEventTime.InvalidKey))
}

///|
test "invalid/time all resource budgets must be positive" {
  let limits = @MoonEventTime.Limits::new(max_active_windows=0)
  assert_eq(
    @MoonEventTime.Config::new(10L, limits~),
    Err(@MoonEventTime.InvalidConfig),
  )
  let limits = @MoonEventTime.Limits::new(max_outputs=0)
  assert_eq(
    @MoonEventTime.Config::new(10L, limits~),
    Err(@MoonEventTime.InvalidConfig),
  )
  let limits = @MoonEventTime.Limits::new(max_key_bytes=0)
  assert_eq(
    @MoonEventTime.Config::new(10L, limits~),
    Err(@MoonEventTime.InvalidConfig),
  )
  let limits = @MoonEventTime.Limits::new(max_snapshot_bytes=0)
  assert_eq(
    @MoonEventTime.Config::new(10L, limits~),
    Err(@MoonEventTime.InvalidConfig),
  )
  let limits = @MoonEventTime.Limits::new(max_line_bytes=0)
  assert_eq(
    @MoonEventTime.Config::new(10L, limits~),
    Err(@MoonEventTime.InvalidConfig),
  )
}

///|
test "valid/time partition agrees with mathematical small reference" {
  for t = -100; t <= 100; t = t + 1 {
    for size = 1; size <= 17; size = size + 1 {
      let (start, end) = bounds(t.to_int64(), size.to_int64(), origin=3L)
      assert_true(start <= t.to_int64() && t.to_int64() < end)
      assert_eq((start - 3L) % size.to_int64(), 0L)
      assert_eq(end - start, size.to_int64())
    }
  }
}
