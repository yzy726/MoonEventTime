///|
/// Exact statistics for a nonempty window. Every intermediate sum must fit Int64.
pub struct Stats {
  count : Int64
  sum : Int64
  min : Int64
  max : Int64
} derive(Eq, Debug)

///|
pub extend Stats with Eq::{equal, not_equal}

///|
pub extend Stats with @debug.Debug::{to_repr}

///|
/// Start a nonempty aggregate from one measurement.
pub fn Stats::single(value : Int64) -> Stats {
  { count: 1L, sum: value, min: value, max: value, }
}

///|
/// Return updated statistics, leaving the original immutable value unchanged on error.
pub fn Stats::add(self : Stats, value : Int64) -> Result[Stats, StreamError] {
  guard checked_add(self.count, 1L) is Some(count) else {
    return Err(AggregateOverflow)
  }
  guard checked_add(self.sum, value) is Some(sum) else {
    return Err(AggregateOverflow)
  }
  Ok({
    count,
    sum,
    min: if value < self.min {
      value
    } else {
      self.min
    },
    max: if value > self.max {
      value
    } else {
      self.max
    },
  })
}
