#!/usr/bin/env python3
"""Minimal AdGuard Home Prometheus exporter.

Polls AdGuard's /control/stats + /control/status JSON APIs (admin creds
from ADGUARD_USERNAME/ADGUARD_PASSWORD env) and serves metrics on :9618.
Stdlib only — no pip dependencies.
"""
import base64
import json
import os
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ADGUARD_URL = os.environ.get("ADGUARD_URL", "http://127.0.0.1:8081")
USERNAME = os.environ.get("ADGUARD_USERNAME", "admin")
PASSWORD = os.environ.get("ADGUARD_PASSWORD", "")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "30"))
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "9618"))

AUTH = base64.b64encode(f"{USERNAME}:{PASSWORD}".encode()).decode()

state = {
    "num_dns_queries": 0.0,
    "num_blocked_filtering": 0.0,
    "avg_processing_time": 0.0,
    "protection_enabled": 0.0,
    "up": 0.0,
}
lock = threading.Lock()


def fetch(path):
    req = urllib.request.Request(
        ADGUARD_URL + path, headers={"Authorization": "Basic " + AUTH}
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def poll():
    while True:
        try:
            stats = fetch("/control/stats")
            status = fetch("/control/status")
            with lock:
                state["num_dns_queries"] = float(stats.get("num_dns_queries", 0))
                state["num_blocked_filtering"] = float(
                    stats.get("num_blocked_filtering", 0)
                )
                state["avg_processing_time"] = float(
                    stats.get("avg_processing_time", 0)
                )
                state["protection_enabled"] = float(
                    bool(status.get("protection_enabled"))
                )
                state["up"] = 1.0
        except Exception:
            with lock:
                state["up"] = 0.0
        time.sleep(POLL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        with lock:
            body = (
                "# HELP adguard_num_dns_queries Total DNS queries in AdGuard's stats window\n"
                "# TYPE adguard_num_dns_queries counter\n"
                f"adguard_num_dns_queries {state['num_dns_queries']}\n"
                "# HELP adguard_num_blocked_filtering Queries blocked by filtering\n"
                "# TYPE adguard_num_blocked_filtering counter\n"
                f"adguard_num_blocked_filtering {state['num_blocked_filtering']}\n"
                "# HELP adguard_avg_processing_time Average query processing time in ms\n"
                "# TYPE adguard_avg_processing_time gauge\n"
                f"adguard_avg_processing_time {state['avg_processing_time']}\n"
                "# HELP adguard_protection_enabled AdGuard filtering protection state\n"
                "# TYPE adguard_protection_enabled gauge\n"
                f"adguard_protection_enabled {state['protection_enabled']}\n"
                "# HELP adguard_up Whether the exporter last fetched AdGuard stats successfully\n"
                "# TYPE adguard_up gauge\n"
                f"adguard_up {state['up']}\n"
            ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=poll, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
