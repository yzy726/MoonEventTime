"""Real-process JSONL acceptance checks. Only Python's standard library is used."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SUFFIX = ".exe" if os.name == "nt" else ""
BINARY = ROOT / "_build/native/debug/build/cmd/mooneventtime" / ("mooneventtime" + SUFFIX)


def event(key, timestamp, value=1):
    return dict(type="event", key=key, timestamp_ms=str(timestamp), value=str(value))


def watermark(timestamp):
    return dict(type="watermark", exclusive_ms=str(timestamp))


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="mooneventtime-")
        self.addCleanup(self.workspace.cleanup)
        self.directory = Path(self.workspace.name)

    def write(self, name, records):
        path = self.directory / name
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records), encoding="utf-8")
        return path

    def run_cli(self, path, *options, code=0):
        result = subprocess.run([str(BINARY), "replay", str(path), "--window-ms", "60000", *map(str, options)],
                                cwd=ROOT, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stderr.decode("utf-8", "replace"))
        output = [json.loads(line) for line in result.stdout.decode("utf-8").splitlines()]
        diagnostics = [json.loads(line) for line in result.stderr.decode("utf-8").splitlines()]
        if code == 0:
            self.assertEqual(diagnostics, [])
        else:
            self.assertEqual(len(diagnostics), 1)
            self.assertEqual(diagnostics[0]["type"], "error")
        return output, diagnostics

    def test_out_of_order_sensor(self):
        output, _ = self.run_cli(self.write("sensor.jsonl", [event("sensor-a", 59000, 21000), event("sensor-a", 12000, 20500), watermark(60000)]))
        self.assertEqual(output, [dict(type="window", key="sensor-a", start_ms="0", end_ms="60000", count="2", sum="41500", min="20500", max="21000")])

    def test_multiple_keys_utf8_order(self):
        output, _ = self.run_cli(self.write("keys.jsonl", [event(k, 1, v) for k, v in [("😀", 3), ("\ue000", 2), ("a", 1)]]))
        self.assertEqual([r["key"] for r in output], ["a", "\ue000", "😀"])
        self.assertEqual([r["sum"] for r in output], ["1", "2", "3"])

    def test_late_side_output_and_still_open(self):
        output, _ = self.run_cli(self.write("late.jsonl", [watermark(45000), event("a", 12000, 4), watermark(60000), event("a", 45000, 9)]))
        self.assertEqual([r["type"] for r in output], ["window", "late"])
        self.assertEqual(output[0]["sum"], "4")
        self.assertEqual(output[1]["reason"], "window_closed")

    def test_negative_time_and_endpoint(self):
        output, _ = self.run_cli(self.write("boundary.jsonl", [event("a", -1, 3), event("a", 0, 4), event("a", 60000, 5)]))
        self.assertEqual([(r["start_ms"], r["sum"]) for r in output], [("-60000", "3"), ("0", "4"), ("60000", "5")])

    def test_snapshot_prefix_restore_suffix(self):
        prefix = [event("a", 59000, 21), watermark(30000)]
        suffix = [event("a", 12000, 20), watermark(60000), event("a", 45000, 9), event("b", 60000, 7)]
        snapshot = self.directory / "state.json"
        left, _ = self.run_cli(self.write("prefix.jsonl", prefix), "--snapshot", snapshot, "--no-finish")
        right, _ = self.run_cli(self.write("suffix.jsonl", suffix), "--restore", snapshot)
        full, _ = self.run_cli(self.write("all.jsonl", prefix + suffix))
        self.assertEqual(left + right, full)
        self.assertFalse(json.loads(snapshot.read_text(encoding="utf-8"))["finished"])

    def test_exact_large_integer(self):
        output, _ = self.run_cli(self.write("large.jsonl", [event("a", 1, 9007199254740993)]))
        self.assertEqual(output[0]["sum"], "9007199254740993")

    def test_truncated_record_reports_line_and_keeps_confirmed_output(self):
        path = self.write("truncated.jsonl", [event("private", 1), watermark(60000)])
        with path.open("a", encoding="utf-8") as stream:
            stream.write('{"type":')
        output, diagnostic = self.run_cli(path, code=2)
        self.assertEqual(len(output), 1)
        self.assertEqual(diagnostic[0], dict(type="error", code="invalid_input", line=3))

    def test_watermark_regression(self):
        _, diagnostic = self.run_cli(self.write("regress.jsonl", [watermark(10), watermark(9)]), code=2)
        self.assertEqual(diagnostic[0]["code"], "watermark_regression")

    def test_active_window_budget(self):
        _, diagnostic = self.run_cli(self.write("budget.jsonl", [event("a", 0), event("b", 0)]), "--max-active-windows", "1", code=3)
        self.assertEqual(diagnostic[0]["code"], "budget_exceeded")

    def test_output_budget(self):
        _, diagnostic = self.run_cli(self.write("outputs.jsonl", [event("a", 0), event("b", 0)]), "--max-outputs", "1", code=3)
        self.assertEqual(diagnostic[0]["code"], "budget_exceeded")

    def test_long_line_rejected_before_json_parse(self):
        _, diagnostic = self.run_cli(self.write("line.jsonl", [event("secret", 0)]), "--max-line-bytes", "8", code=3)
        self.assertEqual(diagnostic[0]["code"], "budget_exceeded")
        self.assertNotIn("secret", json.dumps(diagnostic))

    def test_missing_input_io_exit(self):
        _, diagnostic = self.run_cli(self.directory / "absent.jsonl", code=4)
        self.assertEqual(diagnostic[0]["code"], "io_error")

    def test_invalid_utf8(self):
        path = self.directory / "utf8.jsonl"
        path.write_bytes(b'\xff\xfe\n')
        _, diagnostic = self.run_cli(path, code=2)
        self.assertEqual(diagnostic[0]["code"], "invalid_input")

    def test_corrupt_snapshot(self):
        snapshot = self.directory / "bad.json"
        snapshot.write_text("{", encoding="utf-8")
        _, diagnostic = self.run_cli(self.write("empty.jsonl", []), "--restore", snapshot, code=2)
        self.assertEqual(diagnostic[0]["code"], "invalid_snapshot")

    def test_snapshot_byte_limit_during_read(self):
        snapshot = self.directory / "big.json"
        snapshot.write_bytes(b" " * 9000)
        _, diagnostic = self.run_cli(self.write("empty.jsonl", []), "--restore", snapshot, "--max-snapshot-bytes", "32", code=3)
        self.assertEqual(diagnostic[0]["code"], "budget_exceeded")

    def test_unicode_path_and_chunk_boundary(self):
        key = "a" * 8150 + "中😀"
        output, _ = self.run_cli(self.write("传感器.jsonl", [event(key, 0)]), "--max-key-bytes", "9000", "--max-line-bytes", "10000")
        self.assertEqual(output[0]["key"], key)

    def test_explicit_finish(self):
        output, _ = self.run_cli(self.write("finish.jsonl", [event("a", 0), dict(type="finish")]))
        self.assertEqual(len(output), 1)

    def test_snapshot_write_failure(self):
        _, diagnostic = self.run_cli(self.write("empty.jsonl", []), "--snapshot", self.directory / "absent" / "state.json", code=4)
        self.assertEqual(diagnostic[0]["code"], "io_error")

    def test_help_and_invalid_arguments(self):
        help_result = subprocess.run([str(BINARY), "--help"], capture_output=True, timeout=10)
        self.assertEqual(help_result.returncode, 0)
        self.assertIn(b"replay", help_result.stdout)
        _, diagnostic = self.run_cli(self.write("empty.jsonl", []), "--unknown", code=2)
        self.assertEqual(diagnostic[0]["code"], "invalid_config")


if __name__ == "__main__":
    if not BINARY.is_file():
        raise SystemExit(f"Build the native CLI first: moon build --target native (missing {BINARY})")
    unittest.main(verbosity=2)
