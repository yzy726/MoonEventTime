///|
test "valid/reference seeded unordered stream versus independent batch lists" {
  // Small numbers keep reference arithmetic independent of production helpers.
  let e = engine()
  let input : Array[@MoonEventTime.Event] = []
  let mut seed = 726U
  for n = 0; n < 300; n = n + 1 {
    seed = seed * 1664525U + 1013904223U
    let t = (seed % 200U).reinterpret_as_int() - 100
    seed = seed * 1664525U + 1013904223U
    let value = (seed % 101U).reinterpret_as_int() - 50
    let key = if seed % 3U == 0U { "a" } else { "b" }
    let item = event(t.to_int64(), value=value.to_int64(), key~)
    input.push(item)
    e.ingest(item).unwrap() |> ignore
  }
  let actual = e.finish().unwrap()
  let mut index = 0
  for start = -100; start < 100; start = start + 10 {
    for key in ["a", "b"] {
      let items = input.filter(fn(e) {
        e.key == key &&
        e.timestamp_ms >= start.to_int64() &&
        e.timestamp_ms < (start + 10).to_int64()
      })
      if items.is_empty() {
        continue
      }
      let mut sum = 0L
      let mut low = items[0].value
      let mut high = low
      for item in items {
        sum = sum + item.value
        low = if item.value < low { item.value } else { low }
        high = if item.value > high { item.value } else { high }
      }
      let out = actual[index]
      assert_eq((out.window.key, out.window.start_ms), (key, start.to_int64()))
      assert_eq(
        (out.stats.count, out.stats.sum, out.stats.min, out.stats.max),
        (items.length().to_int64(), sum, low, high),
      )
      index = index + 1
    }
  }
  assert_eq(index, actual.length())
}
