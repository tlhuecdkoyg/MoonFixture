"""Run the compiled MoonBit CLI against real SQLite and a local HTTP service.

Python's standard library is an independent consumer, not the fixture engine.
Usage: python scripts/integration.py [--exe PATH]
"""
from pathlib import Path
import argparse
import csv
import io
import json
import sqlite3
import subprocess
import tempfile
import threading
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent


def run(exe, *args, stdin=None, code=0):
    result = subprocess.run([str(exe), *map(str, args)], input=stdin,
                            capture_output=True, encoding="utf-8", cwd=ROOT,
                            timeout=60)
    assert result.returncode == code, (args, result.returncode, result.stderr, result.stdout)
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path)
    args = parser.parse_args()
    suffix = ".exe" if __import__("os").name == "nt" else ""
    exe = (args.exe or ROOT / f"_build/native/debug/build/cmd/main/main{suffix}").resolve()
    with tempfile.TemporaryDirectory(prefix="moonfixture-") as directory:
        temporary = Path(directory)
        for model_name in ("shop", "helpdesk"):
            model_path = ROOT / "examples" / f"{model_name}.json"
            text = run(exe, "generate", model_path, "--seed", "2026")
            assert text == run(exe, "generate", model_path, "--seed", "2026")
            data = json.loads(text)
            tables = {table["name"]: table["rows"] for table in data["tables"]}
            output = temporary / f"{model_name}.json"
            output.write_text(text, encoding="utf-8")
            report = json.loads(run(exe, "validate", output, "--model", model_path))
            assert report["valid"] and report["checked_rows"] == sum(map(len, tables.values()))
            manifest = run(exe, "manifest", model_path, "--seed", "2026")
            assert run(exe, "replay", "-", stdin=manifest) == text
            bundle = json.loads(run(exe, "generate", model_path, "--seed", "2026", "--format", "sqlite", "--batch-size", "7"))
            connection = sqlite3.connect(":memory:")
            connection.execute("PRAGMA foreign_keys = ON")
            with connection:
                for sql in bundle["schema"]:
                    connection.execute(sql)
                for batch in bundle["batches"]:
                    connection.executemany(batch["sql"], batch["parameters"])
            assert not connection.execute("PRAGMA foreign_key_check").fetchall()
            for table, rows in tables.items():
                assert connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0] == len(rows)
            if model_name == "shop":
                sql_total = connection.execute("SELECT SUM(l.quantity*p.price_cents) FROM order_lines l JOIN products p ON p.id=l.product_id JOIN orders o ON o.id=l.order_id JOIN users u ON u.id=o.user_id").fetchone()[0]
                assert sql_total == sum(row["total_cents"] for row in tables["order_lines"])
                try:
                    connection.execute("INSERT INTO orders(id,user_id) VALUES (?,?)", (-1, 999999))
                except sqlite3.IntegrityError:
                    connection.rollback()
                else:
                    raise AssertionError("SQLite failed to reject an invalid foreign key")
                csv_text = run(exe, "generate", model_path, "--seed", "2026", "--format", "csv", "--table", "products")
                csv_rows = list(csv.DictReader(io.StringIO(csv_text)))
                assert [row["label"] for row in csv_rows] == [row["label"] for row in tables["products"]]
                ndjson = run(exe, "generate", model_path, "--seed", "2026", "--format", "ndjson", "--table", "orders")
                assert [json.loads(line) for line in ndjson.splitlines()] == tables["orders"]
                http_check(tables)
            else:
                mismatches = connection.execute("SELECT COUNT(*) FROM tickets t JOIN agents a ON t.agent_id=a.id WHERE t.team_id<>a.team_id").fetchone()[0]
                assert mismatches == 0
            connection.close()
            print(f"PASS {model_name}: generation, replay, validation, parameterized SQLite")
        model_path = ROOT / "examples" / "shop.json"
        output = temporary / "overwrite.json"
        run(exe, "generate", model_path, "--output", output)
        run(exe, "generate", model_path, "--output", output, code=2)
        run(exe, "generate", model_path, "--output", output, "--force")
        run(exe, "generate", model_path, "--max-input", "10", code=2)
        run(exe, "generate", "-", stdin="not json", code=1)
    print("PASS CLI I/O limits and overwrite policy")


def http_check(tables):
    users = {row["id"] for row in tables["users"]}
    orders = tables["orders"]

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, data):
            payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            if self.path == "/orders":
                self.reply(200, orders[:10])
            elif self.path.startswith("/orders/"):
                try:
                    identifier = int(self.path.rsplit("/", 1)[1])
                except ValueError:
                    self.reply(400, {"error": "invalid id"})
                    return
                row = next((row for row in orders if row["id"] == identifier), None)
                self.reply(200 if row else 404, row or {"error": "not found"})
            else:
                self.reply(404, {"error": "not found"})

        def do_POST(self):
            data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            self.reply(201 if data.get("user_id") in users else 422,
                       {"accepted": data.get("user_id") in users})

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    base = f"http://127.0.0.1:{server.server_port}"
    try:
        with opener.open(base + "/orders", timeout=5) as response:
            assert json.load(response) == orders[:10]
        with opener.open(base + f'/orders/{orders[0]["id"]}', timeout=5) as response:
            assert json.load(response) == orders[0]
        for owner, status in ((orders[0]["user_id"], 201), (999999, 422)):
            request = urllib.request.Request(base + "/orders", data=json.dumps({"user_id": owner}).encode(), headers={"Content-Type": "application/json"})
            try:
                response = opener.open(request, timeout=5)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                assert response.status == status
        print("PASS actual HTTP list/detail/create/invalid-reference requests")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == "__main__":
    main()
