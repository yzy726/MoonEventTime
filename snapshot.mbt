///|
/// Parse canonical signed Int64 decimal text without floating-point conversion.
pub fn parse_decimal(text : StringView) -> Result[Int64, StreamError] {
  if text.is_empty() || text.length() > 20 {
    return Err(InvalidInput)
  }
  let negative = text[0] == 45
  let start = if negative { 1 } else { 0 }
  if start == text.length() {
    return Err(InvalidInput)
  }
  let mut n = 0L
  for i = start; i < text.length(); i = i + 1 {
    let digit = text[i].to_int() - 48
    if digit < 0 || digit > 9 || n < I64_MIN / 10L {
      return Err(InvalidInput)
    }
    guard checked_sub(n * 10L, digit.to_int64()) is Some(next) else {
      return Err(InvalidInput)
    }
    n = next
  }
  if !negative && n == I64_MIN {
    return Err(InvalidInput)
  }
  let value = if negative { n } else { -n }
  if value.to_string() != text.to_owned() {
    return Err(InvalidInput)
  }
  Ok(value)
}

///|
fn Config::fingerprint(self : Config) -> String {
  let l = self.limits
  "tumbling/v1/\{self.size_ms}/\{self.origin_ms}/\{l.max_active_windows}/\{l.max_key_bytes}/\{l.max_outputs}/\{l.max_snapshot_bytes}/\{l.max_line_bytes}"
}

///|
fn Config::snapshot_json(self : Config) -> Json {
  let l = self.limits
  {
    "size_ms": @json.ToJson::to_json(self.size_ms.to_string()),
    "origin_ms": @json.ToJson::to_json(self.origin_ms.to_string()),
    "max_active_windows": @json.ToJson::to_json(l.max_active_windows),
    "max_key_bytes": @json.ToJson::to_json(l.max_key_bytes),
    "max_outputs": @json.ToJson::to_json(l.max_outputs),
    "max_snapshot_bytes": @json.ToJson::to_json(l.max_snapshot_bytes),
    "max_line_bytes": @json.ToJson::to_json(l.max_line_bytes),
  }
}

///|
fn snapshot_field(value : Json, name : String) -> Json? {
  match value {
    Object(obj) => obj.get(name)
    _ => None
  }
}

///|
fn snapshot_string(value : Json, name : String) -> String? {
  match snapshot_field(value, name) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn snapshot_integer(value : Json, name : String) -> Int64? {
  guard snapshot_string(value, name) is Some(text) else { return None }
  match parse_decimal(text) {
    Ok(n) => Some(n)
    Err(_) => None
  }
}

///|
fn valid_stats(s : Stats) -> Bool {
  if s.count <= 0L || s.min > s.max {
    return false
  }
  if s.count == 1L {
    return s.min == s.max && s.sum == s.min
  }
  // Both extrema must have actually occurred. BigInt avoids validation overflow.
  let remaining = @bigint.BigInt::from_int64(s.count - 1L)
  let low = @bigint.BigInt::from_int64(s.min)
  let high = @bigint.BigInt::from_int64(s.max)
  let sum = @bigint.BigInt::from_int64(s.sum)
  remaining * low + high <= sum && sum <= remaining * high + low
}

///|
fn snapshot_depth_ok(text : StringView) -> Bool {
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for ch in text {
    if quoted {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        quoted = false
      }
    } else if ch == '"' {
      quoted = true
    } else if ch == '{' || ch == '[' {
      depth = depth + 1
      if depth > 16 {
        return false
      }
    } else if ch == '}' || ch == ']' {
      depth = depth - 1
      if depth < 0 {
        return false
      }
    }
  }
  true
}

///|
/// Serialize a canonical, versioned snapshot. Int64 fields are decimal strings.
pub fn Engine::snapshot(self : Engine) -> Result[String, StreamError] {
  let entries : Array[Json] = []
  let mut entry_bytes = 0
  for pair in self.windows.iter() {
    let (id, s) = pair
    let entry : Json = {
      "key": @json.ToJson::to_json(id.key),
      "start_ms": @json.ToJson::to_json(id.start_ms.to_string()),
      "end_ms": @json.ToJson::to_json(id.end_ms.to_string()),
      "count": @json.ToJson::to_json(s.count.to_string()),
      "sum": @json.ToJson::to_json(s.sum.to_string()),
      "min": @json.ToJson::to_json(s.min.to_string()),
      "max": @json.ToJson::to_json(s.max.to_string()),
    }
    let length = @utf8.encode(entry.stringify()).length()
    if length > self.config.limits.max_snapshot_bytes - entry_bytes {
      return Err(BudgetExceeded)
    }
    entry_bytes = entry_bytes + length
    entries.push(entry)
  }
  let watermark : Json = match self.watermark_ms {
    Some(w) => @json.ToJson::to_json(w.to_string())
    None => Json::null()
  }
  let snapshot : Json = {
    "format_version": 1,
    "fingerprint": @json.ToJson::to_json(self.config.fingerprint()),
    "config": self.config.snapshot_json(),
    "watermark_ms": watermark,
    "finished": @json.ToJson::to_json(self.finished),
    "windows": @json.ToJson::to_json(entries),
  }
  let text = snapshot.stringify()
  if @utf8.encode(text).length() > self.config.limits.max_snapshot_bytes {
    Err(BudgetExceeded)
  } else {
    Ok(text)
  }
}

///|
/// Restore into the same configuration, validating all state before returning an engine.
pub fn Engine::restore(
  config : Config,
  text : StringView,
) -> Result[Engine, StreamError] {
  if text.length() > config.limits.max_snapshot_bytes ||
    @utf8.encode(text).length() > config.limits.max_snapshot_bytes {
    return Err(BudgetExceeded)
  }
  if !snapshot_depth_ok(text) {
    return Err(InvalidSnapshot)
  }
  let value = @json.parse(text) catch { _ => return Err(InvalidSnapshot) }
  guard value is Object(obj) && obj.length() == 6 else {
    return Err(InvalidSnapshot)
  }
  guard snapshot_field(value, "format_version") is Some(Number(version, ..)) else {
    return Err(InvalidSnapshot)
  }
  if version != 1.0 {
    return Err(SnapshotVersion)
  }
  if snapshot_field(value, "config") != Some(config.snapshot_json()) ||
    snapshot_string(value, "fingerprint") != Some(config.fingerprint()) {
    return Err(ConfigMismatch)
  }
  let watermark_ms = match snapshot_field(value, "watermark_ms") {
    Some(Null) => None
    Some(String(s)) =>
      match parse_decimal(s) {
        Ok(w) => Some(w)
        Err(_) => return Err(InvalidSnapshot)
      }
    _ => return Err(InvalidSnapshot)
  }
  let finished = match snapshot_field(value, "finished") {
    Some(True) => true
    Some(False) => false
    _ => return Err(InvalidSnapshot)
  }
  guard snapshot_field(value, "windows") is Some(Array(entries)) else {
    return Err(InvalidSnapshot)
  }
  if entries.length() > config.limits.max_active_windows {
    return Err(BudgetExceeded)
  }
  if finished && !entries.is_empty() {
    return Err(InvalidSnapshot)
  }
  let engine = Engine::new(config)
  let mut previous : WindowId? = None
  for entry in entries {
    guard entry is Object(fields) && fields.length() == 7 else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_string(entry, "key") is Some(key) else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_integer(entry, "start_ms") is Some(start_ms) else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_integer(entry, "end_ms") is Some(end_ms) else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_integer(entry, "count") is Some(count) else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_integer(entry, "sum") is Some(sum) else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_integer(entry, "min") is Some(min) else {
      return Err(InvalidSnapshot)
    }
    guard snapshot_integer(entry, "max") is Some(max) else {
      return Err(InvalidSnapshot)
    }
    let id = match config.assign(start_ms, key) {
      Ok(id) => id
      Err(_) => return Err(InvalidSnapshot)
    }
    let stats : Stats = { count, sum, min, max, }
    if id.start_ms != start_ms || id.end_ms != end_ms || !valid_stats(stats) {
      return Err(InvalidSnapshot)
    }
    if watermark_ms is Some(w) && end_ms <= w {
      return Err(InvalidSnapshot)
    }
    if previous is Some(old) && Compare::compare(old, id) >= 0 {
      return Err(InvalidSnapshot)
    }
    engine.windows = engine.windows.add(id, stats)
    previous = Some(id)
  }
  engine.watermark_ms = watermark_ms
  engine.finished = finished
  Ok(engine)
}
