///|
fn engine(
  limits~ : @MoonEventTime.Limits = @MoonEventTime.Limits::new(),
) -> @MoonEventTime.Engine {
  @MoonEventTime.Engine::new(@MoonEventTime.Config::new(10L, limits~).unwrap())
}

///|
fn event(
  t : Int64,
  value~ : Int64 = 1L,
  key~ : String = "a",
) -> @MoonEventTime.Event {
  { key, timestamp_ms: t, value, }
}

///|
test "valid/engine out of order sensor exact statistics" {
  let e = engine()
  assert_true(e.ingest(event(9L, value=21L)) is Ok(@MoonEventTime.Accepted(_)))
  e.ingest(event(2L, value=20L)).unwrap() |> ignore
  let out = e.advance_watermark(10L).unwrap()
  assert_eq(out.length(), 1)
  assert_eq(
    (out[0].stats.count, out[0].stats.sum, out[0].stats.min, out[0].stats.max),
    (2L, 41L, 20L, 21L),
  )
  assert_eq(e.active_windows(), 0)
}

///|
test "valid/engine initial progress is absent" {
  assert_eq(engine().watermark(), None)
}

///|
test "edge/engine no empty window outputs" {
  assert_eq(engine().advance_watermark(100L).unwrap().length(), 0)
}

///|
test "edge/engine equality closes window" {
  let e = engine()
  e.ingest(event(1L)).unwrap() |> ignore
  assert_eq(e.advance_watermark(9L).unwrap().length(), 0)
  assert_eq(e.advance_watermark(10L).unwrap().length(), 1)
}

///|
test "edge/engine repeated watermark is idempotent" {
  let e = engine()
  e.ingest(event(1L)).unwrap() |> ignore
  assert_eq(e.advance_watermark(10L).unwrap().length(), 1)
  assert_eq(e.advance_watermark(10L).unwrap().length(), 0)
}

///|
test "invalid/engine watermark regression keeps state" {
  let e = engine()
  e.ingest(event(11L)).unwrap() |> ignore
  e.advance_watermark(10L).unwrap() |> ignore
  assert_eq(e.advance_watermark(9L), Err(@MoonEventTime.WatermarkRegression))
  assert_eq(e.watermark(), Some(10L))
  assert_eq(e.active_windows(), 1)
}

///|
test "edge/engine timestamp before watermark in open window is accepted" {
  let e = engine()
  e.advance_watermark(7L).unwrap() |> ignore
  assert_true(e.ingest(event(1L)) is Ok(@MoonEventTime.Accepted(_)))
  assert_eq(e.advance_watermark(10L).unwrap()[0].stats.count, 1L)
}

///|
test "valid/engine closed window is late side output" {
  let e = engine()
  e.advance_watermark(10L).unwrap() |> ignore
  guard e.ingest(event(9L, value=55L)) is Ok(@MoonEventTime.Late(late)) else {
    fail("expected late")
  }
  assert_eq(late.event.value, 55L)
  assert_eq(
    (late.window.start_ms, late.window.end_ms, late.reason),
    (0L, 10L, "window_closed"),
  )
  assert_eq(e.active_windows(), 0)
}

///|
test "edge/engine unseen closed key is still late" {
  let e = engine()
  e.advance_watermark(100L).unwrap() |> ignore
  assert_true(e.ingest(event(1L, key="unseen")) is Ok(@MoonEventTime.Late(_)))
}

///|
test "edge/engine event at watermark belongs to open next window" {
  let e = engine()
  e.advance_watermark(10L).unwrap() |> ignore
  assert_true(e.ingest(event(10L)) is Ok(@MoonEventTime.Accepted(_)))
}

///|
test "valid/engine multiple keys sorted by UTF8 bytes" {
  let e = engine()
  for key in ["😀", "\u{E000}", "中", "z", "a"] {
    e.ingest(event(1L, key~)).unwrap() |> ignore
  }
  let out = e.finish().unwrap()
  assert_eq(out.map(fn(o) { o.window.key }), [
    "a", "z", "中", "\u{E000}", "😀",
  ])
}

///|
test "valid/engine outputs sorted by window end before key" {
  let e = engine()
  e.ingest(event(11L, key="a")).unwrap() |> ignore
  e.ingest(event(-1L, key="z")).unwrap() |> ignore
  let out = e.finish().unwrap()
  assert_eq(out.map(fn(o) { o.window.end_ms }), [0L, 20L])
}

///|
test "invalid/engine active window budget atomic refusal" {
  let e = engine(limits=@MoonEventTime.Limits::new(max_active_windows=1))
  e.ingest(event(1L)).unwrap() |> ignore
  assert_eq(e.ingest(event(11L)), Err(@MoonEventTime.BudgetExceeded))
  assert_eq(e.active_windows(), 1)
  assert_eq(e.finish().unwrap()[0].stats.count, 1L)
}

///|
test "edge/engine existing window updates at capacity" {
  let e = engine(limits=@MoonEventTime.Limits::new(max_active_windows=1))
  e.ingest(event(1L)).unwrap() |> ignore
  e.ingest(event(2L)).unwrap() |> ignore
  assert_eq(e.finish().unwrap()[0].stats.count, 2L)
}

///|
test "invalid/engine output budget rejects without advancing or clearing" {
  let e = engine(limits=@MoonEventTime.Limits::new(max_outputs=1))
  e.ingest(event(1L)).unwrap() |> ignore
  e.ingest(event(11L)).unwrap() |> ignore
  assert_eq(e.advance_watermark(20L), Err(@MoonEventTime.BudgetExceeded))
  assert_eq(e.watermark(), None)
  assert_eq(e.active_windows(), 2)
  assert_eq(e.advance_watermark(10L).unwrap().length(), 1)
  assert_eq(e.advance_watermark(20L).unwrap().length(), 1)
}

///|
test "invalid/engine finish output budget keeps engine live" {
  let e = engine(limits=@MoonEventTime.Limits::new(max_outputs=1))
  e.ingest(event(1L)).unwrap() |> ignore
  e.ingest(event(11L)).unwrap() |> ignore
  assert_eq(e.finish(), Err(@MoonEventTime.BudgetExceeded))
  assert_false(e.is_finished())
  e.advance_watermark(10L).unwrap() |> ignore
  assert_eq(e.finish().unwrap().length(), 1)
}

///|
test "invalid/engine aggregate failure preserves prior statistics" {
  let e = engine()
  e.ingest(event(1L, value=9223372036854775807L)).unwrap() |> ignore
  assert_eq(e.ingest(event(2L)), Err(@MoonEventTime.AggregateOverflow))
  let s = e.finish().unwrap()[0].stats
  assert_eq((s.count, s.sum), (1L, 9223372036854775807L))
}

///|
test "invalid/engine invalid key leaves no state" {
  let e = engine()
  assert_eq(e.ingest(event(1L, key="")), Err(@MoonEventTime.InvalidKey))
  assert_eq(e.active_windows(), 0)
}

///|
test "invalid/engine time overflow leaves no state" {
  let e = engine()
  assert_eq(
    e.ingest(event(9223372036854775807L)),
    Err(@MoonEventTime.TimeOverflow),
  )
  assert_eq(e.active_windows(), 0)
}

///|
test "valid/engine finish flushes and becomes terminal" {
  let e = engine()
  e.ingest(event(15L)).unwrap() |> ignore
  assert_eq(e.finish().unwrap().length(), 1)
  assert_true(e.is_finished())
  assert_eq(e.active_windows(), 0)
}

///|
test "invalid/engine ingest after finish" {
  let e = engine()
  e.finish().unwrap() |> ignore
  assert_eq(e.ingest(event(1L)), Err(@MoonEventTime.Finished))
}

///|
test "invalid/engine watermark after finish" {
  let e = engine()
  e.finish().unwrap() |> ignore
  assert_eq(e.advance_watermark(0L), Err(@MoonEventTime.Finished))
}

///|
test "invalid/engine repeated finish is explicit error" {
  let e = engine()
  e.finish().unwrap() |> ignore
  assert_eq(e.finish(), Err(@MoonEventTime.Finished))
}

///|
test "edge/engine negative watermark and zero boundary" {
  let e = engine()
  e.ingest(event(-1L)).unwrap() |> ignore
  assert_eq(e.advance_watermark(-1L).unwrap().length(), 0)
  assert_eq(e.advance_watermark(0L).unwrap().length(), 1)
}

///|
test "valid/engine advancing long stream keeps active state bounded" {
  let e = engine(limits=@MoonEventTime.Limits::new(max_active_windows=2))
  for n = 0; n < 2000; n = n + 1 {
    e.ingest(event(n.to_int64() * 10L)).unwrap() |> ignore
    assert_eq(e.active_windows(), 1)
    assert_eq(
      e.advance_watermark((n + 1).to_int64() * 10L).unwrap().length(),
      1,
    )
    assert_eq(e.active_windows(), 0)
  }
}
