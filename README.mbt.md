# MoonEventTime

可嵌入 MoonBit 程序的事件时间滚动窗口库，适合传感器、日志指标和离线回放。`0.1.0` 提供单输入、按键精确整数统计、显式水位线、迟到侧输出、资源预算和快照恢复；附 native JSONL CLI。核心不读取时钟、文件或网络。

## 安装与最小调用

当前为本地开发版本，尚未发布 Mooncakes。发布后可运行 `moon add Ag108/MoonEventTime@0.1.0`，并在 `moon.pkg` 中导入 `"Ag108/MoonEventTime"`。最小调用使用毫秒时间与毫摄氏度测量值：

```moonbit nocheck
///|
test "README quick start" {
  let config = @MoonEventTime.Config::new(60000L).unwrap()
  let engine = @MoonEventTime.Engine::new(config)
  engine
  .ingest({ key: "sensor-a", timestamp_ms: 59000L, value: 21000L, })
  .unwrap()
  |> ignore
  engine
  .ingest({ key: "sensor-a", timestamp_ms: 12000L, value: 20500L, })
  .unwrap()
  |> ignore
  let result = engine.advance_watermark(60000L).unwrap()
  assert_eq(result.length(), 1)
  assert_eq(result[0].stats.count, 2L)
  assert_eq(result[0].stats.sum, 41500L)
}
```

实际运行时应匹配 `Result` 的 `Ok/Err`；示例仅对已知合法数据使用 unwrap。`ingest` 返回 `Accepted(window)` 或 `Late(record)`；水位线与 finish 返回按 `end_ms → start_ms → UTF-8 key` 排序的窗口结果。

## 语义

窗口为半开区间 `[start,end)`，负时间戳按数学向下取整，可配置对齐原点。排他水位线 W 关闭 `end<=W` 的窗口。`timestamp<W` 但所属窗口尚未关闭的事件仍可接收；关闭后返回 `LateRecord`，原因为 `window_closed`。无事件窗口不输出。

count/sum/min/max 均为精确 Int64；单位由调用方定义。每次计数和中间求和必须可表示，溢出返回错误并保持原状态。重复输入会重复计数。finish 刷出剩余窗口并终止；后续事件、推进或重复 finish 返回 `Finished`。

## JSONL 文件回放

输入 `testdata/out_of_order_sensor.jsonl`：

```jsonl
{"type":"event","key":"sensor-a","timestamp_ms":"59000","value":"21000"}
{"type":"event","key":"sensor-a","timestamp_ms":"12000","value":"20500"}
{"type":"watermark","exclusive_ms":"60000"}
```

```sh
moon run --target native cmd/mooneventtime -- replay testdata/out_of_order_sensor.jsonl --window-ms 60000 --jsonl
```

stdout 结果（JSON 字段顺序不构成协议）：

```jsonl
{"type":"window","key":"sensor-a","start_ms":"0","end_ms":"60000","count":"2","sum":"41500","min":"20500","max":"21000"}
```

时间、测量值和计数使用规范十进制字符串，拒绝 JSON 数字、前导零、`+1`、`-0`。允许空白行、CRLF 和没有末尾换行的完整记录；非法或截断记录立即停止。stdout 为窗口与迟到记录，stderr 为不含原始键值的 `{"type":"error","code":"...","line":N}`。退出码：0 成功、2 输入/配置/状态错误、3 资源限额、4 文件 I/O 错误。错误前已输出的成功前缀不会撤回。

## 资源与恢复

默认限额：1,024 个活跃窗口、键长 256 UTF-8 字节、每次 1,024 个窗口结果、1 MiB 快照、64 KiB JSONL 行。通过 `Limits::new` 或 CLI 的 `--max-active-windows/--max-key-bytes/--max-outputs/--max-snapshot-bytes/--max-line-bytes` 设置。预算不足时保持原状态；输出批次过大可分段推进水位线后重试。CLI 以 8 KiB 块读取，逐行处理。

状态上界依赖预算；水位线停滞时达到上限后拒绝新窗口。在固定键基数且持续推进时，关闭的窗口立即清理；输出与快照临时数据也受预算限制。

```sh
moon run --target native cmd/mooneventtime -- replay testdata/snapshot_prefix.jsonl --window-ms 60000 --no-finish --snapshot _build/state.json
moon run --target native cmd/mooneventtime -- replay testdata/snapshot_suffix.jsonl --window-ms 60000 --restore _build/state.json
```

恢复要求相同配置和相同未确认后缀。输入偏移、快照与下游输出确认须由调用方协调，重复回放可能重复统计或输出。文件原子替换不代表跨系统恰好一次或断电持久性。CLI 默认 EOF 时 finish；保存可继续的状态须使用 `--no-finish`。

## 示例与验证

```sh
moon run examples/out_of_order_sensor
moon run examples/multiple_keys
moon run examples/late_side_output
moon run examples/boundary_and_negative_time
moon run examples/snapshot_replay_cli
moon build --target native --deny-warn
python scripts/examples.py
python scripts/e2e.py
python scripts/verify.py
```

五个示例的完整输入和手算输出位于 `testdata/`；脚本同时核对库与 CLI。核心 native/JavaScript/wasm-gc 和 Windows native CLI 已本地验证；远程 CI、Linux CLI 与注册表发布尚未执行。

文档：[语义](docs/SEMANTICS.md)、[支持范围](docs/SUPPORT.md)、[快照](docs/SNAPSHOT.md)、[测试](docs/TESTING.md)、[性能口径](docs/BENCHMARKS.md)、[来源](docs/PROVENANCE.md)、[安全边界](SECURITY.md)、[AI 使用](AI_USAGE.md)。Apache-2.0 许可。当前不支持滑动窗口、迟到修订、多源水位线或事件去重。
