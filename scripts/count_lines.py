"""Count hand-written production MoonBit code, excluding tests and text blocks."""
from pathlib import Path
import argparse
import json


def effective_lines(text):
    count = 0
    in_comment = False
    for line in text.splitlines():
        if line.lstrip().startswith(("#|", "$|")):
            continue  # help/documentation text is not implementation
        code = False
        quote = None
        escape = False
        index = 0
        while index < len(line):
            pair = line[index:index + 2]
            char = line[index]
            if in_comment:
                if pair == "*/":
                    in_comment = False
                    index += 2
                else:
                    index += 1
                continue
            if quote:
                code = True
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == quote:
                    quote = None
                index += 1
                continue
            if pair == "//":
                break
            if pair == "/*":
                in_comment = True
                index += 2
                continue
            if char in ('"', "'"):
                quote = char
            if not char.isspace():
                code = True
            index += 1
        count += code
    return count


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--minimum", type=int, default=4000)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    files = sorted(root.glob("*.mbt"))
    for directory in ("cli", "cmd"):
        files.extend(sorted((root / directory).rglob("*.mbt")))
    production, tests = {}, {}
    for path in files:
        bucket = tests if path.name.endswith(("_test.mbt", "_wbtest.mbt")) else production
        bucket[path.relative_to(root).as_posix()] = effective_lines(path.read_text(encoding="utf-8"))
    total = sum(production.values())
    report = {"production": total, "tests": sum(tests.values()), "minimum": args.minimum,
              "passed": total >= args.minimum, "files": production}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for name, lines in production.items():
            print(f"{lines:5} {name}")
        print(f"Production: {total}; tests (excluded): {sum(tests.values())}; minimum: {args.minimum}")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
