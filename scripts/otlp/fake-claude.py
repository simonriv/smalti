#!/usr/bin/env python3
"""Emisor falso de telemetría de Claude Code (F7, solo para pruebas y mediciones).

Lee el endpoint y la cabecera que Smalti inyecta en el panel (OTEL_EXPORTER_OTLP_LOGS_ENDPOINT y
OTEL_EXPORTER_OTLP_LOGS_HEADERS) y manda lotes OTLP/HTTP JSON con eventos `api_request` y `api_error` con la forma de
Claude Code 2.1.332. Nunca habla con nada que no sea 127.0.0.1 y termina solo.

Uso: fake-claude.py --session <id> [--requests N] [--errors M] [--interval segundos] [--batch K]
Códigos de salida: 0 bien, 3 sin endpoint en el entorno, 4 endpoint fuera de 127.0.0.1, 5 el receptor rechazó un lote.
"""

import argparse
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def attribute(key, value):
    if isinstance(value, bool):
        return {"key": key, "value": {"boolValue": value}}
    if isinstance(value, int):
        return {"key": key, "value": {"intValue": str(value)}}
    if isinstance(value, float):
        return {"key": key, "value": {"doubleValue": value}}
    return {"key": key, "value": {"stringValue": value}}


def record(name, session, sequence, extra):
    now = datetime.datetime.now(datetime.timezone.utc)
    attributes = {
        "event.name": name,
        "event.timestamp": now.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "event.sequence": sequence,
        "session.id": session,
        "model": "claude-opus-5-5",
        **extra,
    }
    nanos = str(int(now.timestamp() * 1_000_000_000))
    return {
        "timeUnixNano": nanos,
        "observedTimeUnixNano": nanos,
        "body": {"stringValue": f"claude_code.{name}"},
        "attributes": [attribute(k, v) for k, v in attributes.items()],
    }


def request_event(session, sequence, index):
    return record(
        "api_request",
        session,
        sequence,
        {
            "input_tokens": 1200,
            "output_tokens": 300 + index,
            "cache_read_tokens": 40000,
            "cache_creation_tokens": 0,
            "cost_usd": 0.0125,
            "cost_usd_micros": 12500,
            "duration_ms": 1200 + 100 * (index % 5),
            "request_id": f"req_{sequence}",
            "speed": "normal",
            "query_source": "repl_main_thread",
        },
    )


def error_event(session, sequence):
    return record(
        "api_error",
        session,
        sequence,
        {"error": "rate_limit_error", "status_code": 429, "duration_ms": 2000, "attempt": 11},
    )


def batch(records):
    return {
        "resourceLogs": [
            {
                "resource": {"attributes": [attribute("service.name", "claude-code"), attribute("service.version", "2.1.332")]},
                "scopeLogs": [{"scope": {"name": "com.anthropic.claude_code.events"}, "logRecords": records}],
            }
        ]
    }


def headers_from(text):
    headers = {"Content-Type": "application/json"}
    for pair in filter(None, (text or "").split(",")):
        key, _, value = pair.partition("=")
        headers[urllib.parse.unquote(key.strip())] = urllib.parse.unquote(value.strip())
    return headers


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--requests", type=int, default=3)
    parser.add_argument("--errors", type=int, default=0)
    parser.add_argument("--interval", type=float, default=0.2)
    parser.add_argument("--batch", type=int, default=5)
    args = parser.parse_args()

    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT")
    if not endpoint:
        print("fake-claude: no OTEL_EXPORTER_OTLP_LOGS_ENDPOINT in the environment", file=sys.stderr)
        return 3
    if urllib.parse.urlparse(endpoint).hostname != "127.0.0.1":
        print("fake-claude: refusing a non-loopback endpoint", file=sys.stderr)
        return 4
    headers = headers_from(os.environ.get("OTEL_EXPORTER_OTLP_LOGS_HEADERS"))

    events = [lambda seq, i=i: request_event(args.session, seq, i) for i in range(args.requests)]
    events += [lambda seq: error_event(args.session, seq) for _ in range(args.errors)]
    sequence = 1
    for start in range(0, len(events), max(1, args.batch)):
        records = []
        for make in events[start : start + args.batch]:
            records.append(make(sequence))
            sequence += 1
        body = json.dumps(batch(records)).encode()
        try:
            # No proxies, ever: the batch goes straight to 127.0.0.1 even if the environment names a proxy.
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(urllib.request.Request(endpoint, data=body, headers=headers), timeout=5) as reply:
                reply.read()
        except urllib.error.URLError as error:
            print(f"fake-claude: batch refused: {error}", file=sys.stderr)
            return 5
        if args.interval:
            time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
