"""Compare five native examples and file replay with hand-written golden outputs."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "_build/native/debug/build"
NAMES = ["out_of_order_sensor", "multiple_keys", "late_side_output", "boundary_and_negative_time", "snapshot_replay_cli"]


def binary(directory, name):
    return next((p for p in [directory / (name + ".exe"), directory / name] if p.is_file()), directory / (name + ".exe"))


CLI = binary(BUILD / "cmd/mooneventtime", "mooneventtime")


def records(text):
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def run(*command):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", "replace"))
    if result.stderr:
        raise AssertionError(result.stderr)
    return records(result.stdout.decode("utf-8"))


for name in NAMES:
    expected = records((ROOT / "testdata" / (name + ".expected.jsonl")).read_text(encoding="utf-8"))
    executable = binary(BUILD / "examples" / name, name)
    actual = run(executable)
    assert actual == expected, (name, actual, expected)
    if name != "snapshot_replay_cli":
        replay = run(CLI, "replay", ROOT / "testdata" / (name + ".jsonl"), "--window-ms", 60000)
    else:
        with tempfile.TemporaryDirectory(prefix="met-example-") as directory:
            state = Path(directory) / "state.json"
            prefix = run(CLI, "replay", ROOT / "testdata/snapshot_prefix.jsonl", "--window-ms", 60000, "--no-finish", "--snapshot", state)
            suffix = run(CLI, "replay", ROOT / "testdata/snapshot_suffix.jsonl", "--window-ms", 60000, "--restore", state)
            replay = prefix + suffix
    assert replay == expected, (name, replay, expected)
    print(f"{name}: library example and CLI match golden output")
