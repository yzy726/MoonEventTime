///|
fn main {
  let config = @eventtime.Config::new(60000L).unwrap()
  let continuous = @eventtime.Engine::new(config)
  continuous.ingest({ key: "a", timestamp_ms: 59000L, value: 21L, }).unwrap()
  |> ignore
  continuous.advance_watermark(30000L).unwrap() |> ignore
  let restored = @eventtime.Engine::restore(
    config,
    continuous.snapshot().unwrap(),
  ).unwrap()
  for e in [continuous, restored] {
    e.ingest({ key: "a", timestamp_ms: 12000L, value: 20L, }).unwrap() |> ignore
  }
  let actual = restored.advance_watermark(60000L).unwrap()
  if actual != continuous.advance_watermark(60000L).unwrap() {
    abort("recovery mismatch")
  }
  for out in actual {
    println(@replay.window_json(out).stringify())
  }
}
