///|
const I64_MAX : Int64 = 9223372036854775807L

///|
const I64_MIN : Int64 = -9223372036854775808L

///|
fn checked_add(a : Int64, b : Int64) -> Int64? {
  if (b > 0L && a > I64_MAX - b) || (b < 0L && a < I64_MIN - b) {
    None
  } else {
    Some(a + b)
  }
}

///|
fn checked_sub(a : Int64, b : Int64) -> Int64? {
  if (b > 0L && a < I64_MIN + b) || (b < 0L && a > I64_MAX + b) {
    None
  } else {
    Some(a - b)
  }
}

///|
fn floor_mod(t : Int64, size : Int64) -> Int64 {
  let r = t % size
  if r < 0L {
    r + size
  } else {
    r
  }
}

///|
/// Assign a key and timestamp without forming the possibly overflowing t-origin.
pub fn Config::assign(
  self : Config,
  timestamp_ms : Int64,
  key : String,
) -> Result[WindowId, StreamError] {
  if key.is_empty() || @utf8.encode(key).length() > self.limits.max_key_bytes {
    return Err(InvalidKey)
  }
  let difference = floor_mod(timestamp_ms, self.size_ms) -
    floor_mod(self.origin_ms, self.size_ms)
  let offset = if difference < 0L {
    difference + self.size_ms
  } else {
    difference
  }
  guard checked_sub(timestamp_ms, offset) is Some(start_ms) else {
    return Err(TimeOverflow)
  }
  guard checked_add(start_ms, self.size_ms) is Some(end_ms) else {
    return Err(TimeOverflow)
  }
  Ok({ key, start_ms, end_ms, })
}
