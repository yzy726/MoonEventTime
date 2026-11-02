///|
fn main {
  let e = @eventtime.Engine::new(@eventtime.Config::new(60000L).unwrap())
  e.ingest({ key: "a", timestamp_ms: -1L, value: 3L, }).unwrap() |> ignore
  e.ingest({ key: "a", timestamp_ms: 0L, value: 4L, }).unwrap() |> ignore
  e.ingest({ key: "a", timestamp_ms: 60000L, value: 5L, }).unwrap() |> ignore
  for out in e.finish().unwrap() {
    println(@replay.window_json(out).stringify())
  }
}
