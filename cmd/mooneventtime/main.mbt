///|
#borrow(path)
extern "C" fn input_open(path : Bytes) -> Int = "mooneventtime_open"

///|
#borrow(buffer)
extern "C" fn input_read(buffer : Bytes) -> Int = "mooneventtime_read"

///|
extern "C" fn input_close() -> Int = "mooneventtime_close"

///|
#borrow(message)
extern "C" fn stderr(message : Bytes) -> Unit = "mooneventtime_stderr"

///|
#borrow(path, data)
extern "C" fn write_snapshot(path : Bytes, data : Bytes) -> Int = "mooneventtime_write_snapshot"

///|
extern "C" fn process_exit(status : Int) -> Unit = "mooneventtime_exit"

///|
struct Options {
  input : String
  config : @eventtime.Config
  restore : String?
  snapshot : String?
  no_finish : Bool
}

///|
fn positive_int(text : String) -> Int? {
  match @eventtime.parse_decimal(text) {
    Ok(n) if n > 0L && n <= 2147483647L => Some(n.to_int())
    _ => None
  }
}

///|
fn valid_path(path : String) -> Bool {
  !path.is_empty() && path.length() <= 32768 && !path.contains("\u{0000}")
}

///|
fn cpath(path : String) -> Bytes {
  @utf8.encode(path + "\u{0000}")
}

///|
fn options(args : Array[String]) -> Options? {
  if args.length() < 3 || args[1] != "replay" || !valid_path(args[2]) {
    return None
  }
  let mut size : Int64? = None
  let mut origin = 0L
  let mut restore : String? = None
  let mut snapshot : String? = None
  let mut no_finish = false
  let mut active = 1024
  let mut key_bytes = 256
  let mut outputs = 1024
  let mut snapshot_bytes = 1048576
  let mut line_bytes = 65536
  let mut index = 3
  let seen : Map[String, Bool] = Map([])
  while index < args.length() {
    let name = args[index]
    if seen.contains(name) {
      return None
    }
    seen.set(name, true)
    if name == "--no-finish" {
      no_finish = true
      index = index + 1
      continue
    }
    if name == "--jsonl" {
      index = index + 1
      continue
    }
    if index + 1 >= args.length() {
      return None
    }
    let value = args[index + 1]
    match name {
      "--window-ms" => {
        guard @eventtime.parse_decimal(value) is Ok(n) else { return None }
        size = Some(n)
      }
      "--origin-ms" => {
        guard @eventtime.parse_decimal(value) is Ok(n) else { return None }
        origin = n
      }
      "--restore" => {
        if !valid_path(value) {
          return None
        }
        restore = Some(value)
      }
      "--snapshot" => {
        if !valid_path(value) || value == args[2] {
          return None
        }
        snapshot = Some(value)
      }
      "--max-active-windows" => {
        guard positive_int(value) is Some(n) else { return None }
        active = n
      }
      "--max-key-bytes" => {
        guard positive_int(value) is Some(n) else { return None }
        key_bytes = n
      }
      "--max-outputs" => {
        guard positive_int(value) is Some(n) else { return None }
        outputs = n
      }
      "--max-snapshot-bytes" => {
        guard positive_int(value) is Some(n) else { return None }
        snapshot_bytes = n
      }
      "--max-line-bytes" => {
        guard positive_int(value) is Some(n) else { return None }
        line_bytes = n
      }
      _ => return None
    }
    index = index + 2
  }
  guard size is Some(size) else { return None }
  let limits = @eventtime.Limits::new(
    max_active_windows=active,
    max_key_bytes=key_bytes,
    max_outputs=outputs,
    max_snapshot_bytes=snapshot_bytes,
    max_line_bytes=line_bytes,
  )
  guard @eventtime.Config::new(size, origin_ms=origin, limits~) is Ok(config) else {
    return None
  }
  Some({ input: args[2], config, restore, snapshot, no_finish, })
}

///|
fn report(error : @eventtime.StreamError, line? : Int = 0) -> Int {
  stderr(@utf8.encode(@replay.error_json(error, line~).stringify()))
  @replay.exit_code(error)
}

///|
fn io_error() -> Int {
  let diagnostic : Json = { "type": "error", "code": "io_error", "line": 0 }
  stderr(@utf8.encode(diagnostic.stringify()))
  4
}

///|
fn read_snapshot(
  path : String,
  config : @eventtime.Config,
) -> Result[@eventtime.Engine, Int] {
  if input_open(cpath(path)) != 0 {
    return Err(io_error())
  }
  let bytes = @buffer.Buffer()
  let chunk = Bytes::make(8192, 0)
  while true {
    let n = input_read(chunk)
    if n < 0 {
      input_close() |> ignore
      return Err(io_error())
    }
    if n == 0 {
      break
    }
    if n > config.limits.max_snapshot_bytes - bytes.length() {
      input_close() |> ignore
      return Err(report(@eventtime.BudgetExceeded))
    }
    bytes.write_bytes(chunk[:n])
  }
  if input_close() != 0 {
    return Err(io_error())
  }
  let text = @utf8.decode(bytes.to_bytes()) catch {
    _ => return Err(report(@eventtime.InvalidSnapshot))
  }
  match @eventtime.Engine::restore(config, text) {
    Ok(engine) => Ok(engine)
    Err(error) => Err(report(error))
  }
}

///|
fn apply_line(engine : @eventtime.Engine, bytes : Bytes, number : Int) -> Int {
  let line = @utf8.decode(bytes) catch {
    _ => return report(@eventtime.InvalidInput, line=number)
  }
  if line.trim().is_empty() {
    return 0
  }
  let record = match @replay.parse_record(line, engine.configuration().limits) {
    Ok(record) => record
    Err(error) => return report(error, line=number)
  }
  match @replay.apply_record(engine, record) {
    Ok(output) => {
      for item in output {
        println(item.stringify())
      }
      0
    }
    Err(error) => report(error, line=number)
  }
}

///|
fn replay_file(engine : @eventtime.Engine, path : String) -> Int {
  if input_open(cpath(path)) != 0 {
    return io_error()
  }
  let chunk = Bytes::make(8192, 0)
  let line = @buffer.Buffer()
  let mut number = 1
  while true {
    let count = input_read(chunk)
    if count < 0 {
      input_close() |> ignore
      return io_error()
    }
    if count == 0 {
      break
    }
    for i = 0; i < count; i = i + 1 {
      let byte = chunk[i]
      if byte == 10 {
        let status = apply_line(engine, line.to_bytes(), number)
        if status != 0 {
          input_close() |> ignore
          return status
        }
        line.reset()
        if number == 2147483647 {
          input_close() |> ignore
          return report(@eventtime.BudgetExceeded)
        }
        number = number + 1
      } else {
        if line.length() >= engine.configuration().limits.max_line_bytes {
          input_close() |> ignore
          return report(@eventtime.BudgetExceeded, line=number)
        }
        line.write_byte(byte)
      }
    }
  }
  if input_close() != 0 {
    return io_error()
  }
  if !line.is_empty() {
    return apply_line(engine, line.to_bytes(), number)
  }
  0
}

///|
fn run(options : Options) -> Int {
  let engine = match options.restore {
    Some(path) =>
      match read_snapshot(path, options.config) {
        Ok(e) => e
        Err(status) => return status
      }
    None => @eventtime.Engine::new(options.config)
  }
  let status = replay_file(engine, options.input)
  if status != 0 {
    return status
  }
  if !options.no_finish && !engine.is_finished() {
    match @replay.apply_record(engine, @replay.Finish) {
      Ok(output) =>
        for item in output {
          println(item.stringify())
        }
      Err(error) => return report(error)
    }
  }
  if options.snapshot is Some(path) {
    let text = match engine.snapshot() {
      Ok(text) => text
      Err(error) => return report(error)
    }
    if write_snapshot(cpath(path), @utf8.encode(text)) != 0 {
      return io_error()
    }
  }
  0
}

///|
fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    println(
      "MoonEventTime 0.1.0\nUsage: mooneventtime replay INPUT --window-ms N [--origin-ms N]\n  [--restore FILE] [--snapshot FILE] [--no-finish] [--jsonl]\n  [--max-active-windows N] [--max-key-bytes N] [--max-outputs N]\n  [--max-snapshot-bytes N] [--max-line-bytes N]\nResults/late records: stdout JSONL. Diagnostics: stderr JSONL. Exit: 0/2/3/4.",
    )
  } else {
    let status = match options(args) {
      Some(options) => run(options)
      None => report(@eventtime.InvalidConfig)
    }
    if status != 0 {
      process_exit(status)
    }
  }
}
