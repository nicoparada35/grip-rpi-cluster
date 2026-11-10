#!/usr/bin/env python3
"""
GRIP Basketball — Lightweight GitHub Webhook Receiver for Continuous Deployment (CD)
Listens on GRIP_WEBHOOK_PORT (default 9000), verifies HMAC-SHA256 signature
against GRIP_WEBHOOK_SECRET, and triggers scripts/09-cd-deploy.sh asynchronously.
"""
import hashlib
import hmac
import http.server
import json
import os
import subprocess
import sys

PORT = int(os.environ.get("GRIP_WEBHOOK_PORT", "9000"))
SECRET = os.environ.get("GRIP_WEBHOOK_SECRET", "GripWebhookSecret2026!").encode("utf-8")
DEPLOY_SCRIPT = "/opt/grip/repo/scripts/09-cd-deploy.sh"


class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok","service":"grip-cd-webhook"}')
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path not in ("/webhook", "/deploy"):
            self.send_error(404, "Endpoint not found")
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        sig_header = self.headers.get("X-Hub-Signature-256", "")
        if SECRET:
            expected_sig = "sha256=" + hmac.new(SECRET, body, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(sig_header, expected_sig):
                self.send_error(403, "Invalid X-Hub-Signature-256")
                return

        subprocess.Popen(
            ["/usr/bin/env", "bash", DEPLOY_SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        resp = json.dumps({"ok": True, "message": "CD deployment triggered"}).encode("utf-8")
        self.send_response(202)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), WebhookHandler)
    print(f"GRIP CD Webhook Receiver listening on 0.0.0.0:{PORT}...", flush=True)
    sys.exit(server.serve_forever())
