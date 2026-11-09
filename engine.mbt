///|
/// Window statistics in canonical end, start, UTF-8 key order.
#derive(Eq, Debug)
pub struct WindowOutput {
  window : WindowId
  stats : Stats
}

///|
pub extend WindowOutput with Eq::{equal, not_equal}

///|
pub extend WindowOutput with @debug.Debug::{to_repr}

///|
/// Late data is returned immediately, never retained in an internal queue.
#derive(Eq, Debug)
pub struct LateRecord {
  event : Event
  window : WindowId
  reason : String
}

///|
pub extend LateRecord with Eq::{equal, not_equal}

///|
pub extend LateRecord with @debug.Debug::{to_repr}

///|
/// Every successful ingest either updates one window or returns a late record.
#derive(Eq, Debug)
pub(all) enum IngestOutcome {
  Accepted(WindowId)
  Late(LateRecord)
}

///|
pub extend IngestOutcome with Eq::{equal, not_equal}

///|
pub extend IngestOutcome with @debug.Debug::{to_repr}

///|
impl Compare for WindowId with fn compare(a, b) {
  let end_order = a.end_ms.compare(b.end_ms)
  if end_order != 0 {
    return end_order
  }
  let start_order = a.start_ms.compare(b.start_ms)
  if start_order != 0 {
    return start_order
  }
  @utf8.encode(a.key).compare(@utf8.encode(b.key))
}

///|
/// A pure single-input state machine. No clocks, I/O or background work.
pub struct Engine {
  priv config : Config
  priv mut windows : @sorted_map.SortedMap[WindowId, Stats]
  priv mut watermark_ms : Int64?
  priv mut finished : Bool
}

///|
/// Start an engine from a configuration validated by Config::new.
pub fn Engine::new(config : Config) -> Engine {
  { config, windows: @sorted_map.new(), watermark_ms: None, finished: false, }
}

///|
/// Return the immutable configuration.
pub fn Engine::configuration(self : Engine) -> Config {
  self.config
}

///|
/// Return the exclusive progress boundary, or None before the first watermark.
pub fn Engine::watermark(self : Engine) -> Int64? {
  self.watermark_ms
}

///|
/// Count active nonempty windows.
pub fn Engine::active_windows(self : Engine) -> Int32 {
  self.windows.length()
}

///|
/// Indicate whether finish has successfully terminated this engine.
pub fn Engine::is_finished(self : Engine) -> Bool {
  self.finished
}

///|
/// Ingest atomically. An event before W is accepted when its window remains open.
pub fn Engine::ingest(
  self : Engine,
  event : Event,
) -> Result[IngestOutcome, StreamError] {
  if self.finished {
    return Err(Finished)
  }
  let id = match self.config.assign(event.timestamp_ms, event.key) {
    Ok(id) => id
    Err(e) => return Err(e)
  }
  if self.watermark_ms is Some(w) && id.end_ms <= w {
    return Ok(Late({ event, window: id, reason: "window_closed", }))
  }
  let stats = match self.windows.get(id) {
    Some(old) =>
      match old.add(event.value) {
        Ok(stats) => stats
        Err(e) => return Err(e)
      }
    None => {
      if self.windows.length() >= self.config.limits.max_active_windows {
        return Err(BudgetExceeded)
      }
      Stats::single(event.value)
    }
  }
  self.windows = self.windows.add(id, stats)
  Ok(Accepted(id))
}

///|
fn Engine::due(
  self : Engine,
  boundary : Int64?,
) -> Result[Array[WindowOutput], StreamError] {
  let result : Array[WindowOutput] = []
  // The ordered tree is also the expiry index; stop at the first future window.
  for entry in self.windows.iter() {
    let (window, stats) = entry
    if boundary is Some(w) && window.end_ms > w {
      break
    }
    if result.length() >= self.config.limits.max_outputs {
      return Err(BudgetExceeded)
    }
    result.push({ window, stats, })
  }
  Ok(result)
}

///|
fn Engine::remove_outputs(self : Engine, outputs : Array[WindowOutput]) -> Unit {
  for output in outputs {
    self.windows = self.windows.remove(output.window)
  }
}

///|
/// Close end<=W windows exactly once. Refusal leaves both progress and state unchanged.
pub fn Engine::advance_watermark(
  self : Engine,
  exclusive_ms : Int64,
) -> Result[Array[WindowOutput], StreamError] {
  if self.finished {
    return Err(Finished)
  }
  if self.watermark_ms is Some(old) && exclusive_ms < old {
    return Err(WatermarkRegression)
  }
  let outputs = match self.due(Some(exclusive_ms)) {
    Ok(outputs) => outputs
    Err(e) => return Err(e)
  }
  self.remove_outputs(outputs)
  self.watermark_ms = Some(exclusive_ms)
  Ok(outputs)
}

///|
/// Flush remaining windows and terminate, after output-budget preflight.
pub fn Engine::finish(
  self : Engine,
) -> Result[Array[WindowOutput], StreamError] {
  if self.finished {
    return Err(Finished)
  }
  let outputs = match self.due(None) {
    Ok(outputs) => outputs
    Err(e) => return Err(e)
  }
  self.remove_outputs(outputs)
  self.finished = true
  Ok(outputs)
}
