#!/usr/bin/env python3
# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Local-account setup HTTP UI (de-Googled). Listens on 127.0.0.1:17891.
# Creates cryptohome vaults via /usr/sbin/create-local-account.sh (AuthSession).

from __future__ import annotations

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

HOST = "127.0.0.1"
PORT = 17891
HELPER = "/usr/sbin/create-local-account.sh"
MARKER = "/var/lib/nvidia-generic-auth/local-account-setup.done"

PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Local account</title>
<style>
  :root { --bg:#0f1419; --card:#1a2332; --text:#e7ecf3; --muted:#9aa7b8;
          --accent:#3d9cf0; --accent2:#2a6fad; --err:#f07178; --ok:#7fd99a; }
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; font-family: "Segoe UI", system-ui, sans-serif;
         background: radial-gradient(1200px 600px at 20% -10%, #1c3a5a 0%, transparent 55%),
                     radial-gradient(900px 500px at 100% 0%, #243048 0%, transparent 50%),
                     var(--bg); color: var(--text);
         display:flex; align-items:center; justify-content:center; padding:24px; }
  main { width:min(420px, 100%); background: color-mix(in srgb, var(--card) 92%, black);
         border:1px solid #2c3a4f; border-radius:16px; padding:28px 28px 24px;
         box-shadow: 0 24px 60px rgba(0,0,0,.45); }
  h1 { margin:0 0 6px; font-size:1.45rem; letter-spacing:-0.02em; }
  p.lead { margin:0 0 22px; color:var(--muted); font-size:.95rem; line-height:1.45; }
  label { display:block; font-size:.8rem; color:var(--muted); margin:12px 0 6px; }
  input { width:100%; padding:12px 14px; border-radius:10px; border:1px solid #334155;
          background:#0c121a; color:var(--text); font-size:1rem; }
  input:focus { outline:2px solid var(--accent); border-color:transparent; }
  button { margin-top:20px; width:100%; padding:12px 16px; border:0; border-radius:10px;
           background: linear-gradient(180deg, var(--accent), var(--accent2));
           color:white; font-weight:600; font-size:1rem; cursor:pointer; }
  button:disabled { opacity:.55; cursor:wait; }
  .msg { margin-top:16px; font-size:.9rem; min-height:1.2em; }
  .msg.err { color:var(--err); }
  .msg.ok { color:var(--ok); }
  .foot { margin-top:18px; font-size:.75rem; color:var(--muted); line-height:1.4; }
</style>
</head>
<body>
<main>
  <h1>Create local account</h1>
  <p class="lead">No Google account. Username and password are stored in cryptohome
  on this disk’s stateful partition.</p>
  <form id="f">
    <label for="user">Username</label>
    <input id="user" name="user" autocomplete="username" placeholder="localuser" required/>
    <label for="password">Password</label>
    <input id="password" name="password" type="password" autocomplete="new-password" required/>
    <label for="password2">Confirm password</label>
    <input id="password2" name="password2" type="password" autocomplete="new-password" required/>
    <button type="submit" id="go">Create account</button>
  </form>
  <div class="msg" id="msg"></div>
  <p class="foot">After success, reboot and sign in as <em>user@localhost</em>.
  Installing to NVMe creates a fresh stateful — create the account again there.</p>
</main>
<script>
const msg = document.getElementById('msg');
const form = document.getElementById('f');
const go = document.getElementById('go');
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  msg.className = 'msg';
  msg.textContent = '';
  const user = document.getElementById('user').value.trim();
  const password = document.getElementById('password').value;
  const password2 = document.getElementById('password2').value;
  if (password !== password2) {
    msg.className = 'msg err';
    msg.textContent = 'Passwords do not match.';
    return;
  }
  go.disabled = true;
  try {
    const r = await fetch('/api/create', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({user, password}),
    });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || 'create failed');
    msg.className = 'msg ok';
    msg.textContent = j.message || 'Account created. Reboot and sign in.';
  } catch (err) {
    msg.className = 'msg err';
    msg.textContent = String(err.message || err);
  } finally {
    go.disabled = false;
  }
});
</script>
</body>
</html>
"""


def normalize_user(raw: str) -> str:
    u = raw.strip()
    if not u:
        raise ValueError("username required")
    if "@" not in u:
        u = f"{u}@localhost"
    if len(u) < 3 or "/" in u or " " in u:
        raise ValueError("invalid username")
    return u


def create_account(user: str, password: str) -> str:
    if not os.path.isfile(HELPER):
        raise RuntimeError(f"missing {HELPER} — rebuild image with nvidia-generic-auth")
    if not password:
        raise ValueError("password required")
    proc = subprocess.run(
        [HELPER, "--user", user, "--password", password],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stdout or "") + (proc.stderr or "")
        raise RuntimeError(detail.strip() or f"helper exit {proc.returncode}")
    os.makedirs(os.path.dirname(MARKER), exist_ok=True)
    with open(MARKER, "w", encoding="utf-8") as fh:
        fh.write(user + "\n")
    return f"Created {user}. Reboot, then sign in with that username and password."


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[local-account-setup] " + (fmt % args) + "\n")

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/", "/index.html", "/setup"):
            self._send(200, PAGE.encode(), "text/html; charset=utf-8")
            return
        if self.path == "/api/status":
            payload = {
                "helper": os.path.isfile(HELPER),
                "done": os.path.isfile(MARKER),
            }
            data = json.dumps(payload).encode()
            self._send(200, data, "application/json")
            return
        self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length else b""
        user = password = ""
        try:
            if self.headers.get("Content-Type", "").startswith("application/json"):
                obj = json.loads(raw.decode() or "{}")
                user = str(obj.get("user", ""))
                password = str(obj.get("password", ""))
            else:
                qs = parse_qs(raw.decode())
                user = (qs.get("user") or [""])[0]
                password = (qs.get("password") or [""])[0]
            email = normalize_user(user)
            message = create_account(email, password)
            data = json.dumps({"ok": True, "message": message, "user": email}).encode()
            self._send(200, data, "application/json")
        except Exception as exc:  # pylint: disable=broad-except
            data = json.dumps({"ok": False, "error": str(exc)}).encode()
            self._send(400, data, "application/json")


def main() -> int:
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"[local-account-setup] http://{HOST}:{PORT}/", flush=True)
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
