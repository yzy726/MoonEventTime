///|
fn main {
  let e = @eventtime.Engine::new(@eventtime.Config::new(60000L).unwrap())
  // Values are milli-degrees Celsius, never floating-point measurements.
  e.ingest({ key: "sensor-a", timestamp_ms: 59000L, value: 21000L, }).unwrap()
  |> ignore
  e.ingest({ key: "sensor-a", timestamp_ms: 12000L, value: 20500L, }).unwrap()
  |> ignore
  for out in e.advance_watermark(60000L).unwrap() {
    println(@replay.window_json(out).stringify())
  }
}
