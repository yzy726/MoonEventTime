///|
/// Stable, data-free error categories. Raw keys and values are not diagnostics.
pub(all) enum StreamError {
  InvalidConfig
  InvalidKey
  TimeOverflow
  AggregateOverflow
  WatermarkRegression
  BudgetExceeded
  Finished
  InvalidSnapshot
  SnapshotVersion
  ConfigMismatch
  InvalidInput
} derive(Eq, Debug)

///|
/// Resource limits are checked before committing a state transition.
pub struct Limits {
  max_active_windows : Int
  max_key_bytes : Int
  max_outputs : Int
  max_snapshot_bytes : Int
  max_line_bytes : Int
} derive(Eq, Debug)

///|
/// Construct budgets. Config::new rejects nonpositive values.
pub fn Limits::new(
  max_active_windows? : Int = 1024,
  max_key_bytes? : Int = 256,
  max_outputs? : Int = 1024,
  max_snapshot_bytes? : Int = 1048576,
  max_line_bytes? : Int = 65536,
) -> Limits {
  {
    max_active_windows,
    max_key_bytes,
    max_outputs,
    max_snapshot_bytes,
    max_line_bytes,
  }
}

///|
/// Validated tumbling window configuration; milliseconds use signed Int64.
pub struct Config {
  size_ms : Int64
  origin_ms : Int64
  limits : Limits
} derive(Eq, Debug)

///|
/// Create a fixed-width, half-open window configuration.
pub fn Config::new(
  size_ms : Int64,
  origin_ms? : Int64 = 0L,
  limits? : Limits = Limits::new(),
) -> Result[Config, StreamError] {
  if size_ms <= 0L ||
    limits.max_active_windows <= 0 ||
    limits.max_key_bytes <= 0 ||
    limits.max_outputs <= 0 ||
    limits.max_snapshot_bytes <= 0 ||
    limits.max_line_bytes <= 0 {
    Err(InvalidConfig)
  } else {
    Ok({ size_ms, origin_ms, limits, })
  }
}

///|
/// A nonempty key and a measurement in a caller-defined fixed unit.
pub(all) struct Event {
  key : String
  timestamp_ms : Int64
  value : Int64
} derive(Eq, Debug)

///|
pub extend StreamError with Eq::{equal, not_equal}

///|
pub extend StreamError with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Config with Eq::{equal, not_equal}

///|
pub extend Config with @debug.Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
pub extend WindowId with Eq::{equal, not_equal}

///|
pub extend WindowId with @debug.Debug::{to_repr}

///|
/// Identity of the half-open interval [start_ms, end_ms) for one key.
pub struct WindowId {
  key : String
  start_ms : Int64
  end_ms : Int64
} derive(Eq, Debug)
