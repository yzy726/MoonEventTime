"""Consume the packaged source from an unrelated temporary MoonBit workspace.

This validates the local artifact, not a Mooncakes registry publication.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "moon.mod").read_text(encoding="utf-8"), re.MULTILINE)[1]
ARCHIVE = ROOT / f"_build/publish/Ag108-MoonEventTime-{VERSION}.zip"


def run(*command):
    subprocess.run(list(map(str, command)), cwd=ROOT, check=True, timeout=180)


run("moon", "package", "--list")
with zipfile.ZipFile(ARCHIVE) as archive:
    names = [name.replace("\\", "/") for name in archive.namelist()]
    for name in names:
        parts = Path(name).parts
        assert ".." not in parts and not name.startswith("/"), name
        assert not any(p in {"goal.md", "AGENTS.md", "项目申报书.md", ".agent-workplace", ".git", ".mooncakes"} for p in parts), name
        assert not (name.lower().endswith(".md") and ("acceptance" in name.lower() or "验收" in name)), name
    assert any(name.endswith("cmd/mooneventtime/io.c") for name in names)
    with tempfile.TemporaryDirectory(prefix="mooneventtime-consumer-") as directory:
        workspace = Path(directory)
        library = workspace / "library"
        library.mkdir()
        archive.extractall(library)
        # Archives from supported toolchains put moon.mod at their root.
        assert (library / "moon.mod").is_file(), names[:5]
        run("moon", "-C", library, "doc")
        consumer = workspace / "consumer"
        consumer.mkdir()
        (consumer / "moon.mod").write_text(f'name = "local/consumer"\nversion = "0.1.0"\npreferred_target = "wasm-gc"\nimport {{ "Ag108/MoonEventTime@{VERSION}", }}\n', encoding="utf-8")
        (consumer / "moon.pkg").write_text('import { "Ag108/MoonEventTime", } for "test"\n', encoding="utf-8")
        readme = (library / "README.mbt.md").read_text(encoding="utf-8")
        blocks = re.findall(r"```(?:moonbit|mbt)[^\n]*\n(.*?)\n```", readme, re.DOTALL)
        samples = [block for block in blocks if re.search(r'\btest\s+"README quick start"', block)]
        assert len(samples) == 1, "README quick start must be compiled verbatim"
        (consumer / "readme_test.mbt").write_text(samples[0] + "\n", encoding="utf-8")
        run("moon", "-C", workspace, "work", "init")
        run("moon", "-C", workspace, "work", "use", library, consumer)
        run("moon", "-C", consumer, "test", "--target", "wasm-gc", "--deny-warn")
print("Packaged library documentation generated; clean consumer and README passed; private Markdown excluded.")
