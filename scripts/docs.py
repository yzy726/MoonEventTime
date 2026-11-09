"""Regression gate for the documentation build performed by Mooncakes."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def regr_mooncakes_documentation():
    print("+ moon doc", flush=True)
    subprocess.run(["moon", "doc"], cwd=ROOT, check=True, timeout=300)


if __name__ == "__main__":
    regr_mooncakes_documentation()
