"""Pruebas del emisor falso de telemetría (F7): nunca un Claude real, solo un servidor HTTP en 127.0.0.1."""

import json
import os
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fake-claude.py")


class Collector(BaseHTTPRequestHandler):
    received = []

    def do_POST(self):
        length = int(self.headers["Content-Length"])
        Collector.received.append(
            {"path": self.path, "auth": self.headers.get("Authorization"), "body": json.loads(self.rfile.read(length))}
        )
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *args):
        pass


def run(args, env):
    return subprocess.run([sys.executable, SCRIPT, *args], env=env, capture_output=True, text=True, timeout=20)


class FakeClaudeTests(unittest.TestCase):
    def setUp(self):
        Collector.received = []
        self.server = HTTPServer(("127.0.0.1", 0), Collector)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        port = self.server.server_address[1]
        self.env = {
            "PATH": os.environ.get("PATH", ""),
            "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT": f"http://127.0.0.1:{port}/v1/logs",
            "OTEL_EXPORTER_OTLP_LOGS_HEADERS": "Authorization=Bearer tok",
        }

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def test_exits_3_without_endpoint(self):
        result = run(["--session", "s"], {"PATH": os.environ.get("PATH", "")})
        self.assertEqual(result.returncode, 3)

    def test_posts_api_request_and_error_batches(self):
        result = run(["--session", "abc", "--requests", "3", "--errors", "1", "--interval", "0"], self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Collector.received)
        self.assertTrue(all(r["path"] == "/v1/logs" and r["auth"] == "Bearer tok" for r in Collector.received))
        records = [
            record
            for r in Collector.received
            for resource in r["body"]["resourceLogs"]
            for scope in resource["scopeLogs"]
            for record in scope["logRecords"]
        ]
        names = [r["body"]["stringValue"] for r in records]
        self.assertEqual(names.count("claude_code.api_request"), 3)
        self.assertEqual(names.count("claude_code.api_error"), 1)
        attributes = {a["key"]: a["value"] for a in records[0]["attributes"]}
        self.assertEqual(attributes["session.id"]["stringValue"], "abc")
        self.assertEqual(attributes["event.name"]["stringValue"], "api_request")
        sequences = [int(next(a["value"]["intValue"] for a in r["attributes"] if a["key"] == "event.sequence")) for r in records]
        self.assertEqual(len(set(sequences)), len(sequences))

    def test_refuses_non_loopback_endpoint(self):
        env = dict(self.env, OTEL_EXPORTER_OTLP_LOGS_ENDPOINT="http://192.0.2.1:4318/v1/logs")
        result = run(["--session", "s"], env)
        self.assertEqual(result.returncode, 4)


if __name__ == "__main__":
    unittest.main()
