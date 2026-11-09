///|
fn alter(text : String, field : String, replacement : Json) -> String {
  guard (try! @json.parse(text)) is Object(obj) else {
    abort("object expected")
  }
  obj.set(field, replacement)
  @json.ToJson::to_json(obj).stringify()
}

///|
fn alter_entry(text : String, field : String, replacement : Json) -> String {
  guard (try! @json.parse(text)) is Object(obj) else {
    abort("object expected")
  }
  guard obj.get("windows") is Some(Array(entries)) else {
    abort("windows expected")
  }
  guard entries[0] is Object(entry) else { abort("entry expected") }
  entry.set(field, replacement)
  @json.ToJson::to_json(obj).stringify()
}

///|
fn seeded_snapshot() -> String {
  let e = engine()
  e.ingest(event(1L, value=5L)).unwrap() |> ignore
  e.snapshot().unwrap()
}

///|
fn restore(
  text : String,
) -> Result[@MoonEventTime.Engine, @MoonEventTime.StreamError] {
  @MoonEventTime.Engine::restore(@MoonEventTime.Config::new(10L).unwrap(), text)
}

///|
test "valid/snapshot empty roundtrip" {
  let e = engine()
  let s = e.snapshot().unwrap()
  assert_eq(restore(s).unwrap().snapshot().unwrap(), s)
}

///|
test "valid/snapshot prefix restore suffix equals uninterrupted run" {
  let a = engine()
  a.ingest(event(9L, value=21L)).unwrap() |> ignore
  a.advance_watermark(7L).unwrap() |> ignore
  let b = restore(a.snapshot().unwrap()).unwrap()
  for e in [a, b] {
    e.ingest(event(2L, value=20L)).unwrap() |> ignore
  }
  assert_eq(a.advance_watermark(10L), b.advance_watermark(10L))
  assert_eq(a.snapshot(), b.snapshot())
}

///|
test "edge/snapshot Int64 extrema are exact decimal strings" {
  let e = engine()
  e.ingest(event(1L, value=-9223372036854775808L)).unwrap() |> ignore
  let b = restore(e.snapshot().unwrap()).unwrap()
  assert_eq(b.finish().unwrap()[0].stats.sum, -9223372036854775808L)
}

///|
test "valid/snapshot stable across insertion order" {
  let a = engine()
  let b = engine()
  for key in ["b", "a"] {
    a.ingest(event(1L, key~)).unwrap() |> ignore
  }
  for key in ["a", "b"] {
    b.ingest(event(1L, key~)).unwrap() |> ignore
  }
  assert_eq(a.snapshot(), b.snapshot())
}

///|
test "edge/snapshot preserves terminal state" {
  let a = engine()
  a.finish().unwrap() |> ignore
  let b = restore(a.snapshot().unwrap()).unwrap()
  assert_eq(b.ingest(event(1L)), Err(@MoonEventTime.Finished))
}

///|
test "invalid/snapshot truncated JSON" {
  assert_true(
    restore("{\"format_version\":") is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot unknown version" {
  assert_true(
    restore(alter(seeded_snapshot(), "format_version", 2))
    is Err(@MoonEventTime.SnapshotVersion),
  )
}

///|
test "invalid/snapshot missing schema fields" {
  assert_true(restore("{}") is Err(@MoonEventTime.InvalidSnapshot))
}

///|
test "invalid/snapshot configuration mismatch" {
  let config = @MoonEventTime.Config::new(11L).unwrap()
  assert_true(
    @MoonEventTime.Engine::restore(config, seeded_snapshot())
    is Err(@MoonEventTime.ConfigMismatch),
  )
}

///|
test "invalid/snapshot fingerprint mismatch" {
  assert_true(
    restore(alter(seeded_snapshot(), "fingerprint", "forged"))
    is Err(@MoonEventTime.ConfigMismatch),
  )
}

///|
test "invalid/snapshot duplicate window identities" {
  let s = seeded_snapshot()
  guard @json.parse(s) is Object(obj) else { fail("object") }
  guard obj.get("windows") is Some(Array(entries)) else { fail("windows") }
  entries.push(entries[0])
  assert_true(
    restore(@json.ToJson::to_json(obj).stringify())
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot misaligned window" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "start_ms", "1"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot forged end boundary" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "end_ms", "11"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot already closed window" {
  assert_true(
    restore(alter(seeded_snapshot(), "watermark_ms", "10"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot terminal engine cannot retain windows" {
  assert_true(
    restore(alter(seeded_snapshot(), "finished", true))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot count must be positive" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "count", "0"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot min greater than max" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "min", "6"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot impossible single value sum" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "sum", "6"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot integer numbers are rejected" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "sum", 5))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot oversized decimal" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "sum", "9223372036854775808"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot noncanonical decimal" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "sum", "05"))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot invalid key" {
  assert_true(
    restore(alter_entry(seeded_snapshot(), "key", ""))
    is Err(@MoonEventTime.InvalidSnapshot),
  )
}

///|
test "invalid/snapshot serialization budget leaves engine live" {
  let e = engine(limits=@MoonEventTime.Limits::new(max_snapshot_bytes=10))
  e.ingest(event(1L)).unwrap() |> ignore
  assert_eq(e.snapshot(), Err(@MoonEventTime.BudgetExceeded))
  assert_eq(e.finish().unwrap().length(), 1)
}

///|
test "invalid/snapshot restore checks byte limit before parsing" {
  let config = @MoonEventTime.Config::new(
    10L,
    limits=@MoonEventTime.Limits::new(max_snapshot_bytes=10),
  ).unwrap()
  assert_true(
    @MoonEventTime.Engine::restore(config, seeded_snapshot())
    is Err(@MoonEventTime.BudgetExceeded),
  )
}
