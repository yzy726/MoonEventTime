"""Reproduce the project's local and CI gates without publishing anything."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def project_files(pattern):
    return [p for p in ROOT.rglob(pattern) if not any(part.startswith(".") or part in {"_build", "target"} for part in p.relative_to(ROOT).parts)]


def run(*command):
    print("+ " + " ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=ROOT, check=True, timeout=300)


tests = []
for path in project_files("*.mbt"):
    tests.extend(re.findall(r'\btest\s+"([^"]+)"', path.read_text(encoding="utf-8")))
boundaries = [name for name in tests if name.startswith(("invalid/", "edge/"))]
assert len(tests) >= 80, len(tests)
assert len(boundaries) >= 25, len(boundaries)
assert len(tests) == len(set(tests)), "Duplicate test names"
print(f"Named deterministic scenarios: {len(tests)}; error/boundary scenarios: {len(boundaries)}", flush=True)

for markdown in project_files("*.md"):
    for target in re.findall(r"\]\(([^)]+)\)", markdown.read_text(encoding="utf-8")):
        if "://" in target or target.startswith(("#", "mailto:")):
            continue
        destination = target.split("#", 1)[0]
        if destination:
            assert (markdown.parent / destination).is_file(), (markdown, target)

run("moon", "version", "--all")
run("moon", "fmt", "--check")
for target in ["native", "js", "wasm-gc"]:
    run("moon", "check", "--target", target, "--deny-warn")
    run("moon", "test", "--target", target, "--deny-warn")
before = {p: p.read_bytes() for p in project_files("*.mbti")}
run("moon", "info")
run("moon", "fmt")
after = {p: p.read_bytes() for p in project_files("*.mbti")}
assert before == after, "Generated public interfaces changed; review and commit them before verifying again"
run("moon", "fmt", "--check")
run(sys.executable, "scripts/docs.py")
run("moon", "build", "--target", "native", "--deny-warn")
run(sys.executable, "scripts/e2e.py")
run(sys.executable, "scripts/examples.py")
run(sys.executable, "scripts/consumer.py")
print("All local gates passed. No push, publication or remote CI was performed.", flush=True)
