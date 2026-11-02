///|
fn parse(line : String) -> Result[@replay.InputRecord, @eventtime.StreamError] {
  @replay.parse_record(line, @eventtime.Limits::new())
}

///|
test "valid/protocol event uses exact strings" {
  assert_eq(
    parse(
      "{\"type\":\"event\",\"key\":\"a\",\"timestamp_ms\":\"9\",\"value\":\"9223372036854775807\"}",
    ),
    Ok(
      @replay.Data({ key: "a", timestamp_ms: 9L, value: 9223372036854775807L, }),
    ),
  )
}

///|
test "valid/protocol watermark" {
  assert_eq(
    parse("{\"type\":\"watermark\",\"exclusive_ms\":\"-10\"}"),
    Ok(@replay.Watermark(-10L)),
  )
}

///|
test "valid/protocol explicit finish" {
  assert_eq(parse("{\"type\":\"finish\"}"), Ok(@replay.Finish))
}

///|
test "invalid/protocol malformed JSON" {
  assert_eq(parse("{"), Err(@eventtime.InvalidInput))
}

///|
test "invalid/protocol JSON array" {
  assert_eq(parse("[]"), Err(@eventtime.InvalidInput))
}

///|
test "invalid/protocol blank record" {
  assert_eq(parse(" "), Err(@eventtime.InvalidInput))
}

///|
test "invalid/protocol unknown record type" {
  assert_eq(parse("{\"type\":\"idle\"}"), Err(@eventtime.InvalidInput))
}

///|
test "invalid/protocol missing value" {
  assert_eq(
    parse("{\"type\":\"event\",\"key\":\"a\",\"timestamp_ms\":\"1\"}"),
    Err(@eventtime.InvalidInput),
  )
}

///|
test "invalid/protocol numeric timestamp cannot lose precision" {
  assert_eq(
    parse(
      "{\"type\":\"event\",\"key\":\"a\",\"timestamp_ms\":9007199254740993,\"value\":\"1\"}",
    ),
    Err(@eventtime.InvalidInput),
  )
}

///|
test "invalid/protocol overflow decimal" {
  assert_eq(
    parse("{\"type\":\"watermark\",\"exclusive_ms\":\"-9223372036854775809\"}"),
    Err(@eventtime.InvalidInput),
  )
}

///|
test "invalid/protocol unknown fields are rejected" {
  assert_eq(
    parse("{\"type\":\"finish\",\"extra\":1}"),
    Err(@eventtime.InvalidInput),
  )
}

///|
test "invalid/protocol line byte budget" {
  assert_eq(
    @replay.parse_record(
      "{\"type\":\"finish\"}",
      @eventtime.Limits::new(max_line_bytes=8),
    ),
    Err(@eventtime.BudgetExceeded),
  )
}

///|
test "edge/protocol decimal canonical signed domain" {
  for s in ["0", "1", "-1", "9223372036854775807", "-9223372036854775808"] {
    assert_true(@eventtime.parse_decimal(s) is Ok(_))
  }
}

///|
test "invalid/protocol decimal alternate spellings" {
  for
    s in [
      "", "+1", "01", "-0", "-01", "1.0", "1e1", " 1", "1 ", "-", "一", "9223372036854775808",
    ] {
    assert_eq(@eventtime.parse_decimal(s), Err(@eventtime.InvalidInput))
  }
}

///|
test "valid/protocol library replay outputs same statistics" {
  let e = @eventtime.Engine::new(@eventtime.Config::new(10L).unwrap())
  @replay.apply_record(
    e,
    @replay.Data({ key: "a", timestamp_ms: 9L, value: 21L, }),
  ).unwrap()
  |> ignore
  @replay.apply_record(
    e,
    @replay.Data({ key: "a", timestamp_ms: 2L, value: 20L, }),
  ).unwrap()
  |> ignore
  let result = @replay.apply_record(e, @replay.Watermark(10L)).unwrap()
  assert_eq(result.length(), 1)
  guard result[0] is { "sum": String(sum), "count": String(count), .. } else {
    fail("statistics")
  }
  assert_eq((sum, count), ("41", "2"))
}

///|
test "valid/protocol late data is explicit JSON side output" {
  let e = @eventtime.Engine::new(@eventtime.Config::new(10L).unwrap())
  @replay.apply_record(e, @replay.Watermark(10L)).unwrap() |> ignore
  let out = @replay.apply_record(
    e,
    @replay.Data({ key: "a", timestamp_ms: 1L, value: 2L, }),
  ).unwrap()
  assert_true(
    out[0] is { "type": String("late"), "reason": String("window_closed"), .. },
  )
}

///|
test "invalid/protocol error diagnostics omit raw event data" {
  let diagnostic = @replay.error_json(@eventtime.InvalidKey, line=7).stringify()
  assert_true(
    (try! @json.parse(diagnostic))
    is { "code": String("invalid_key"), "line": Number(7.0, ..), .. },
  )
  assert_eq(@replay.exit_code(@eventtime.BudgetExceeded), 3)
  assert_eq(@replay.exit_code(@eventtime.WatermarkRegression), 2)
}
