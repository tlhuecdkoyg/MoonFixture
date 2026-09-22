"""Fail immediately on any failed check; shared by local runs and CI."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    print("+ " + " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


if __name__ == "__main__":
    run("moon", "version", "--all")
    run("moon", "update")
    run("moon", "check", "--target", "all", "--deny-warn")
    run("moon", "test", "--target", "all", "--deny-warn")
    run("moon", "fmt", "--check")
    run("moon", "info")
    run(sys.executable, "scripts/count_lines.py", "--minimum", "4000")
    run("moon", "build", "--target", "native", "--deny-warn")
    run(sys.executable, "scripts/integration.py")
