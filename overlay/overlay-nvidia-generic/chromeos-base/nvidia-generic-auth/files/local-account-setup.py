#!/usr/bin/env python3
# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# First-boot HTTP UI on 127.0.0.1:17891.
# USB: disk picker wrapping install-to-disk.sh (never Flex OsInstall).
# Installed disk: localuser@localhost password (AuthFactor local-password).
# Do not use Chrome "Create local account" → Next.

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

HOST = "127.0.0.1"
PORT = 17891
HELPER = "/usr/sbin/create-local-account.sh"
GAIA_HELPER = "/usr/sbin/disable-gaia-after-local-account"
INSTALLER = "/usr/sbin/install-to-disk.sh"
MARKER = "/var/lib/nvidia-generic-auth/local-account-setup.done"
LIMITS_PATHS = (
    "/usr/share/chromiumos-nvidia-cross/limits.conf",
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "..", "safety", "limits.conf"),
)
FIXED_USER = "localuser@localhost"
KEY_LABEL = "local-password"

PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>nvidia-generic setup</title>
<style>
  :root { --bg:#0f1419; --card:#1a2332; --text:#e7ecf3; --muted:#9aa7b8;
          --accent:#3d9cf0; --accent2:#2a6fad; --err:#f07178; --ok:#7fd99a; --warn:#e0b45c; }
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; font-family: "Segoe UI", system-ui, sans-serif;
         background: radial-gradient(1200px 600px at 20% -10%, #1c3a5a 0%, transparent 55%),
                     var(--bg); color: var(--text);
         display:flex; align-items:flex-start; justify-content:center; padding:24px; }
  main { width:min(640px, 100%); background: color-mix(in srgb, var(--card) 92%, black);
         border:1px solid #2c3a4f; border-radius:16px; padding:28px;
         box-shadow: 0 24px 60px rgba(0,0,0,.45); }
  h1 { margin:0 0 6px; font-size:1.45rem; }
  p.lead { margin:0 0 18px; color:var(--muted); font-size:.95rem; line-height:1.45; }
  section { margin-top:22px; padding-top:18px; border-top:1px solid #2c3a4f; }
  label { display:block; font-size:.8rem; color:var(--muted); margin:12px 0 6px; }
  input, select { width:100%; padding:12px 14px; border-radius:10px; border:1px solid #334155;
          background:#0c121a; color:var(--text); font-size:1rem; }
  button { margin-top:14px; width:100%; padding:12px 16px; border:0; border-radius:10px;
           background: linear-gradient(180deg, var(--accent), var(--accent2));
           color:white; font-weight:600; font-size:1rem; cursor:pointer; }
  button.secondary { background:#243044; }
  button:disabled { opacity:.55; cursor:wait; }
  .disk { border:1px solid #334155; border-radius:10px; padding:10px 12px; margin:8px 0; cursor:pointer; }
  .disk.sel { outline:2px solid var(--accent); }
  .disk.bad { opacity:.55; cursor:not-allowed; }
  .tag { font-size:.75rem; color:var(--warn); }
  .msg { margin-top:14px; font-size:.9rem; min-height:1.2em; white-space:pre-wrap; }
  .msg.err { color:var(--err); } .msg.ok { color:var(--ok); }
  .foot { margin-top:16px; font-size:.75rem; color:var(--muted); line-height:1.4; }
  pre { background:#0c121a; padding:10px; border-radius:8px; overflow:auto; font-size:.75rem; }
</style>
</head>
<body>
<main>
  <h1>nvidia-generic setup</h1>
  <p class="lead">No Google account. Open this page as Guest for USB install, or after
  NVMe boot (not Guest) to set <em>localuser@localhost</em>. Never use Chrome
  “Create local account” → Next.</p>

  <section id="install-sec">
    <h2>Install to internal disk</h2>
    <p class="lead">Runs on the live USB. Ubuntu is refused by filesystem UUID.
    Type <code>erase DISKNAME</code> to confirm.</p>
    <div id="disks"></div>
    <label for="confirm">Confirm</label>
    <input id="confirm" placeholder="erase nvme0n1" autocomplete="off"/>
    <button type="button" class="secondary" id="dry">Dry-run</button>
    <button type="button" id="install">Erase and install</button>
    <pre id="install-out"></pre>
  </section>

  <section id="acct-sec">
    <h2>Local password</h2>
    <p class="lead">Creates cryptohome for localuser@localhost (factor
    <code>local-password</code>). Sign out of Guest first. USB vaults do not
    transfer to NVMe — set this <em>after</em> install.</p>
    <label for="password">Password</label>
    <input id="password" type="password" autocomplete="new-password"/>
    <label for="password2">Confirm password</label>
    <input id="password2" type="password" autocomplete="new-password"/>
    <button type="button" id="go">Create localuser@localhost</button>
  </section>
  <div class="msg" id="msg"></div>
  <p class="foot">http://127.0.0.1:17891/ — Gaia stays disabled.</p>
</main>
<script>
let dst = '';
const msg = document.getElementById('msg');
function setMsg(ok, t) { msg.className = 'msg ' + (ok ? 'ok' : 'err'); msg.textContent = t; }
async function load() {
  const r = await fetch('/api/status');
  const j = await r.json();
  const box = document.getElementById('disks');
  box.innerHTML = '';
  (j.disks || []).forEach(d => {
    const el = document.createElement('div');
    el.className = 'disk' + (d.allowed ? '' : ' bad');
    el.innerHTML = '<strong>/dev/' + d.name + '</strong> ' + d.size + ' ' + (d.model||'') +
      (d.preferred ? ' <span class="tag">preferred</span>' : '') +
      (d.warn ? ' <span class="tag">' + d.warn + '</span>' : '') +
      '<div class="foot">' + (d.reason || '') + ' uuids: ' + (d.uuids||[]).join(', ') + '</div>';
    if (d.allowed) el.onclick = () => {
      dst = '/dev/' + d.name;
      document.querySelectorAll('.disk').forEach(x => x.classList.remove('sel'));
      el.classList.add('sel');
      document.getElementById('confirm').placeholder = 'erase ' + d.name;
    };
    box.appendChild(el);
  });
  if (j.done) setMsg(true, 'Account marker present: ' + (j.user || 'ok'));
}
async function post(url, body) {
  const r = await fetch(url, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || 'request failed');
  return j;
}
document.getElementById('dry').onclick = async () => {
  setMsg(true, '');
  try {
    const j = await post('/api/install-dry-run', {dst});
    document.getElementById('install-out').textContent = j.output || j.message || '';
    setMsg(true, j.message || 'dry-run ok');
  } catch (e) { setMsg(false, e.message); }
};
document.getElementById('install').onclick = async () => {
  const confirm = document.getElementById('confirm').value.trim();
  document.getElementById('install').disabled = true;
  try {
    const j = await post('/api/install', {dst, confirm});
    document.getElementById('install-out').textContent = j.output || '';
    setMsg(true, j.message || 'install finished — reboot from the internal disk');
  } catch (e) { setMsg(false, e.message); }
  finally { document.getElementById('install').disabled = false; }
};
document.getElementById('go').onclick = async () => {
  const password = document.getElementById('password').value;
  const password2 = document.getElementById('password2').value;
  if (password !== password2) { setMsg(false, 'Passwords do not match.'); return; }
  document.getElementById('go').disabled = true;
  try {
    const j = await post('/api/create', {password});
    setMsg(true, j.message);
  } catch (e) { setMsg(false, e.message); }
  finally { document.getElementById('go').disabled = false; }
};
load().catch(e => setMsg(false, String(e)));
</script>
</body>
</html>
"""


def _load_limits() -> dict[str, str]:
    out: dict[str, str] = {}
    for path in LIMITS_PATHS:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"')
        break
    return out


LIMITS = _load_limits()


def _run(cmd: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)


def root_disk_name() -> str:
    src = _run(["findmnt", "-no", "SOURCE", "/"]).stdout.strip()
    if not src:
        return ""
    pk = _run(["lsblk", "-no", "PKNAME", src]).stdout.strip().splitlines()
    name = (pk[0] if pk else os.path.basename(src)).strip()
    return name


def is_live_usb() -> bool:
    name = root_disk_name()
    if not name:
        return True
    path = f"/sys/block/{name}/removable"
    try:
        return open(path, encoding="utf-8").read().strip() == "1"
    except OSError:
        return True


def disk_uuids(name: str) -> list[str]:
    out = _run(["lsblk", "-no", "UUID", f"/dev/{name}"]).stdout
    return [u.strip() for u in out.splitlines() if u.strip()]


def classify_disk(name: str, rm: str, uuids: list[str]) -> tuple[bool, str, bool, str]:
    """allowed, reason, preferred, warn."""
    ubuntu_root = LIMITS.get("UBUNTU_ROOT_FS_UUID", "")
    ubuntu_esp = LIMITS.get("UBUNTU_ESP_FS_UUID", "")
    install_uuid = LIMITS.get("INSTALL_TARGET_FS_UUID", "")
    steam_uuid = LIMITS.get("STEAM_LIBRARY_FS_UUID", "")
    live = root_disk_name()
    if name == live:
        return False, "live root disk", False, ""
    if rm == "1":
        return False, "removable", False, ""
    if ubuntu_root and ubuntu_root in uuids:
        return False, "Ubuntu root UUID", False, ""
    if ubuntu_esp and ubuntu_esp in uuids:
        return False, "Ubuntu ESP UUID", False, ""
    warn = ""
    if steam_uuid and steam_uuid in uuids:
        warn = "Steam library disk — do not install here"
    preferred = bool(install_uuid and install_uuid in uuids)
    if name == "sda":
        warn = (warn + "; " if warn else "") + "name sda (UUID checks still apply)"
    return True, "ok", preferred, warn


def list_disks() -> list[dict]:
    proc = _run(["lsblk", "-dn", "-o", "NAME,SIZE,TYPE,TRAN,RM,MODEL"])
    disks = []
    for line in proc.stdout.splitlines():
        parts = line.split(None, 5)
        if len(parts) < 5:
            continue
        name, size, typ, tran, rm = parts[0], parts[1], parts[2], parts[3], parts[4]
        model = parts[5] if len(parts) > 5 else ""
        if typ != "disk":
            continue
        uuids = disk_uuids(name)
        allowed, reason, preferred, warn = classify_disk(name, rm, uuids)
        disks.append({
            "name": name,
            "size": size,
            "tran": tran,
            "rm": rm,
            "model": model,
            "uuids": uuids,
            "allowed": allowed,
            "reason": reason,
            "preferred": preferred,
            "warn": warn,
        })
    return disks


def run_install(dst: str, dry_run: bool, confirm: str = "") -> str:
    if not dst.startswith("/dev/") or not re.fullmatch(r"/dev/[a-z0-9]+", dst):
        raise ValueError("invalid destination")
    name = dst[5:]
    if not os.path.isdir(f"/sys/block/{name}"):
        raise ValueError(f"not a whole disk: {dst}")
    allowed, reason, _, warn = classify_disk(
        name,
        open(f"/sys/block/{name}/removable", encoding="utf-8").read().strip(),
        disk_uuids(name),
    )
    if not allowed:
        raise RuntimeError(f"refused {dst}: {reason}")
    if warn and "Steam library" in warn and not dry_run:
        raise RuntimeError(warn)
    if not os.path.isfile(INSTALLER):
        raise RuntimeError(f"missing {INSTALLER}")
    if not dry_run:
        expect = f"erase {name}"
        if confirm.strip() != expect:
            raise ValueError(f'type "{expect}" to confirm')
    cmd = [INSTALLER, "--dst", dst]
    if dry_run:
        cmd.append("--dry-run")
    else:
        cmd.append("--yes")
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=3600)
    text = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if proc.returncode != 0:
        raise RuntimeError(text or f"installer exit {proc.returncode}")
    return text


def create_account(password: str) -> str:
    if not os.path.isfile(HELPER):
        raise RuntimeError(f"missing {HELPER}")
    if not password:
        raise ValueError("password required")
    proc = subprocess.run(
        [
            HELPER,
            "--force-remove",
            "--user",
            FIXED_USER,
            "--password",
            password,
            "--key-label",
            KEY_LABEL,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stdout or "") + (proc.stderr or "")
        raise RuntimeError(detail.strip() or f"helper exit {proc.returncode}")
    os.makedirs(os.path.dirname(MARKER), exist_ok=True)
    with open(MARKER, "w", encoding="utf-8") as fh:
        fh.write(FIXED_USER + "\n")
    gaia_note = ""
    gaia = GAIA_HELPER
    if not os.path.isfile(gaia):
        gaia = "/usr/sbin/scripts/disable-gaia-after-local-account.sh"
    if os.path.isfile(gaia):
        gproc = subprocess.run(
            [gaia, FIXED_USER],
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )
        if gproc.returncode != 0:
            gaia_note = " (WARN: disable-gaia helper failed — run disable-gaia-after-local-account)"
        else:
            gaia_note = " Gaia disabled; login UI restarted."
    return (
        f"Created {FIXED_USER} (label {KEY_LABEL}).{gaia_note} "
        "Sign in on that pod. Do not click Create local account → Next."
    )


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

    def _json_ok(self, obj: dict, code: int = 200) -> None:
        self._send(code, json.dumps(obj).encode(), "application/json")

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/", "/index.html", "/setup"):
            self._send(200, PAGE.encode(), "text/html; charset=utf-8")
            return
        if self.path == "/api/status":
            user = ""
            if os.path.isfile(MARKER):
                with open(MARKER, encoding="utf-8") as fh:
                    user = fh.read().strip()
            self._json_ok({
                "helper": os.path.isfile(HELPER),
                "installer": os.path.isfile(INSTALLER),
                "done": os.path.isfile(MARKER),
                "user": user,
                "live_usb": is_live_usb(),
                "root_disk": root_disk_name(),
                "disks": list_disks(),
            })
            return
        self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length else b""
        try:
            if self.headers.get("Content-Type", "").startswith("application/json"):
                obj = json.loads(raw.decode() or "{}")
            else:
                qs = parse_qs(raw.decode())
                obj = {k: (v[0] if v else "") for k, v in qs.items()}
            path = self.path.split("?", 1)[0]
            if path == "/api/create":
                message = create_account(str(obj.get("password", "")))
                self._json_ok({"ok": True, "message": message, "user": FIXED_USER})
                return
            if path == "/api/install-dry-run":
                out = run_install(str(obj.get("dst", "")), dry_run=True)
                self._json_ok({"ok": True, "message": "dry-run ok", "output": out})
                return
            if path == "/api/install":
                out = run_install(
                    str(obj.get("dst", "")),
                    dry_run=False,
                    confirm=str(obj.get("confirm", "")),
                )
                self._json_ok({
                    "ok": True,
                    "message": "Install finished. Reboot from the internal disk, then set the password here.",
                    "output": out,
                })
                return
            raise ValueError("unknown endpoint")
        except Exception as exc:  # pylint: disable=broad-except
            self._json_ok({"ok": False, "error": str(exc)}, code=400)


def main() -> int:
    print(f"[local-account-setup] http://{HOST}:{PORT}/", flush=True)
    print("[local-account-setup] Guest OK for install; sign out of Guest before password.", flush=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
