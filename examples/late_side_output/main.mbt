///|
fn main {
  let e = @eventtime.Engine::new(@eventtime.Config::new(60000L).unwrap())
  e.advance_watermark(45000L).unwrap() |> ignore
  e.ingest({ key: "a", timestamp_ms: 12000L, value: 4L, }).unwrap() |> ignore
  for out in e.advance_watermark(60000L).unwrap() {
    println(@replay.window_json(out).stringify())
  }
  match e.ingest({ key: "a", timestamp_ms: 45000L, value: 9L, }).unwrap() {
    @eventtime.Late(late) => println(@replay.late_json(late).stringify())
    @eventtime.Accepted(_) => abort("closed window accepted")
  }
}
