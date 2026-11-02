///|
/// JSONL inputs deliberately expose only initial-acceptance operations.
pub(all) enum InputRecord {
  Data(@eventtime.Event)
  Watermark(Int64)
  Finish
} derive(Eq, Debug)

///|
pub extend InputRecord with Eq::{equal, not_equal}

///|
pub extend InputRecord with @debug.Debug::{to_repr}

///|
/// Decode one bounded line. Int64 JSON numbers are rejected to preserve precision.
pub fn parse_record(
  line : StringView,
  limits : @eventtime.Limits,
) -> Result[InputRecord, @eventtime.StreamError] {
  if line.length() > limits.max_line_bytes ||
    @utf8.encode(line).length() > limits.max_line_bytes {
    return Err(@eventtime.BudgetExceeded)
  }
  let json = @json.parse(line) catch {
    _ => return Err(@eventtime.InvalidInput)
  }
  guard json is Object(fields) else { return Err(@eventtime.InvalidInput) }
  match json {
    {
      "type": String("event"),
      "key": String(key),
      "timestamp_ms": String(timestamp),
      "value": String(value),
      ..
    } => {
      if fields.length() != 4 {
        return Err(@eventtime.InvalidInput)
      }
      guard @eventtime.parse_decimal(timestamp) is Ok(timestamp_ms) else {
        return Err(@eventtime.InvalidInput)
      }
      guard @eventtime.parse_decimal(value) is Ok(value) else {
        return Err(@eventtime.InvalidInput)
      }
      Ok(Data({ key, timestamp_ms, value, }))
    }
    { "type": String("watermark"), "exclusive_ms": String(boundary), .. } => {
      if fields.length() != 2 {
        return Err(@eventtime.InvalidInput)
      }
      guard @eventtime.parse_decimal(boundary) is Ok(w) else {
        return Err(@eventtime.InvalidInput)
      }
      Ok(Watermark(w))
    }
    { "type": String("finish"), .. } => {
      if fields.length() != 1 {
        return Err(@eventtime.InvalidInput)
      }
      Ok(Finish)
    }
    _ => Err(@eventtime.InvalidInput)
  }
}

///|
/// Format final results; all counts, measurements and times are decimal strings.
pub fn window_json(output : @eventtime.WindowOutput) -> Json {
  let w = output.window
  let s = output.stats
  {
    "type": "window",
    "key": w.key.to_json(),
    "start_ms": w.start_ms.to_string().to_json(),
    "end_ms": w.end_ms.to_string().to_json(),
    "count": s.count.to_string().to_json(),
    "sum": s.sum.to_string().to_json(),
    "min": s.min.to_string().to_json(),
    "max": s.max.to_string().to_json(),
  }
}

///|
/// Format late data as data, leaving persistence and redaction to the caller.
pub fn late_json(late : @eventtime.LateRecord) -> Json {
  {
    "type": "late",
    "key": late.event.key.to_json(),
    "timestamp_ms": late.event.timestamp_ms.to_string().to_json(),
    "value": late.event.value.to_string().to_json(),
    "start_ms": late.window.start_ms.to_string().to_json(),
    "end_ms": late.window.end_ms.to_string().to_json(),
    "reason": late.reason.to_json(),
  }
}

///|
/// Apply a parsed record using the core state machine, with no duplicate window rules.
pub fn apply_record(
  engine : @eventtime.Engine,
  record : InputRecord,
) -> Result[Array[Json], @eventtime.StreamError] {
  match record {
    Data(event) =>
      match engine.ingest(event) {
        Ok(@eventtime.Accepted(_)) => Ok([])
        Ok(@eventtime.Late(late)) => Ok([late_json(late)])
        Err(e) => Err(e)
      }
    Watermark(w) =>
      match engine.advance_watermark(w) {
        Ok(outputs) => Ok(outputs.map(window_json))
        Err(e) => Err(e)
      }
    Finish =>
      match engine.finish() {
        Ok(outputs) => Ok(outputs.map(window_json))
        Err(e) => Err(e)
      }
  }
}

///|
/// Stable diagnostic codes independent of enum debugging representations.
pub fn error_code(error : @eventtime.StreamError) -> String {
  match error {
    @eventtime.InvalidConfig => "invalid_config"
    @eventtime.InvalidKey => "invalid_key"
    @eventtime.TimeOverflow => "time_overflow"
    @eventtime.AggregateOverflow => "aggregate_overflow"
    @eventtime.WatermarkRegression => "watermark_regression"
    @eventtime.BudgetExceeded => "budget_exceeded"
    @eventtime.Finished => "finished"
    @eventtime.InvalidSnapshot => "invalid_snapshot"
    @eventtime.SnapshotVersion => "snapshot_version"
    @eventtime.ConfigMismatch => "config_mismatch"
    @eventtime.InvalidInput => "invalid_input"
  }
}

///|
/// Minimal diagnostics do not contain raw keys, measurements or input lines.
pub fn error_json(error : @eventtime.StreamError, line? : Int = 0) -> Json {
  {
    "type": "error",
    "code": error_code(error).to_json(),
    "line": line.to_json(),
  }
}

///|
/// Invalid input/configuration is 2; resource refusal is 3. The I/O adapter uses 4.
pub fn exit_code(error : @eventtime.StreamError) -> Int {
  match error {
    @eventtime.BudgetExceeded => 3
    _ => 2
  }
}
