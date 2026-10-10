#!/usr/bin/env python3
"""Dump RTX / nvidia-drm bring-up state for nvidia-generic.

Run on the ChromiumOS device (VT2 as root):

    nvidia-rtx-debug
    python3 /usr/sbin/nvidia-rtx-debug.py
    python3 /usr/sbin/nvidia-rtx-debug.py --out /tmp/rtx-debug.txt

Prints PCI, modules, DRM connectors/modes, CREATE_DUMB, minigbm backend,
EGL/GBM libs, chrome_dev.conf, vtcon bind, and Chrome Ozone/GBM log hits.
"""

from __future__ import annotations

import argparse
import array
import ctypes
import errno
import fcntl
import glob
import os
import struct
import subprocess
import sys
from datetime import datetime, timezone

GETRESOURCES = 0xC04064A0
GETCONNECTOR = 0xC05064A7
GETCRTC = 0xC06864A1
CREATE_DUMB = 0xC02064B2
DESTROY_DUMB = 0xC00464B4
MODEINFO_SIZE = 68

CONNECTOR_TYPES = {
    0: "Unknown", 1: "VGA", 2: "DVII", 3: "DVID", 4: "DVIA", 5: "Composite",
    6: "SVIDEO", 7: "LVDS", 8: "Component", 9: "DIN", 10: "DP", 11: "HDMI-A",
    12: "HDMI-B", 13: "TV", 14: "eDP", 15: "VIRTUAL", 16: "DSI", 17: "DPI",
    18: "WRITEBACK", 19: "SPI", 20: "USB",
}
CONNECTION = {1: "connected", 2: "disconnected", 3: "unknown"}


def io(fd, req, buf):
    fcntl.ioctl(fd, req - (1 << 32) if req >= (1 << 31) else req, buf)


def ptr(buf):
    return ctypes.addressof((ctypes.c_char * len(buf)).from_buffer(buf))


def section(title):
    print()
    print("=== %s ===" % title)


def run(cmd, timeout=15):
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, check=False, timeout=timeout)
    except OSError as exc:
        return "exec failed: %s" % exc
    except subprocess.TimeoutExpired:
        return "timeout: %s" % " ".join(cmd)
    out = (proc.stdout or "") + (proc.stderr or "")
    return out.rstrip() or "(empty, rc=%d)" % proc.returncode


def cat(path, default="(missing)"):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().rstrip()
    except OSError:
        return default


def ls_line(path):
    try:
        st = os.lstat(path)
        target = ""
        if os.path.islink(path):
            target = " -> %s" % os.readlink(path)
        return "%s mode=%04o%s" % (path, st.st_mode & 0o7777, target)
    except OSError as exc:
        return "%s: %s" % (path, exc.strerror)


def driver_of(node):
    link = "/sys/class/drm/%s/device/driver" % node
    try:
        return os.path.basename(os.path.realpath(link))
    except OSError:
        return "?"


def dump_pci():
    section("PCI GPUs")
    print(run(["lspci", "-nnk", "-d", "10de:"]))
    print(run(["lspci", "-nnk", "-d", "1002:"]))


def dump_modules():
    section("modules / nvidia params")
    for name in ("nvidia", "nvidia_drm", "nvidia_modeset", "nvidia_uvm",
                 "amdgpu", "simpledrm"):
        loaded = os.path.isdir("/sys/module/%s" % name)
        print("%-16s loaded=%s" % (name, loaded))
    print("nvidia_drm.modeset=", cat("/sys/module/nvidia_drm/parameters/modeset"))
    print("nvidia_drm.fbdev=", cat("/sys/module/nvidia_drm/parameters/fbdev"))
    for conf in sorted(glob.glob("/etc/modprobe.d/*nvidia*") +
                       glob.glob("/etc/modprobe.d/*simpledrm*") +
                       glob.glob("/etc/modprobe.d/zz-nvidia*")):
        print("-- %s --" % conf)
        print(cat(conf))


def dump_vtcon():
    section("vtcon / fbcon master")
    for path in sorted(glob.glob("/sys/class/vtconsole/vtcon*")):
        name = cat(os.path.join(path, "name"))
        bind = cat(os.path.join(path, "bind"))
        print("%s bind=%s name=%s" % (os.path.basename(path), bind, name))


def dump_nodes():
    section("/dev/dri")
    for path in sorted(glob.glob("/dev/dri/card*") + glob.glob("/dev/dri/renderD*")):
        try:
            st = os.stat(path)
            print("%s mode=%04o uid=%d gid=%d driver=%s" % (
                path, st.st_mode & 0o7777, st.st_uid, st.st_gid,
                driver_of(os.path.basename(path))))
        except OSError as exc:
            print("%s: %s" % (path, exc.strerror))


def dump_sysfs_connectors():
    section("/sys/class/drm")
    try:
        names = sorted(os.listdir("/sys/class/drm"))
    except OSError as exc:
        print("unreadable:", exc)
        return
    print("entries:", " ".join(names))
    for name in names:
        base = os.path.join("/sys/class/drm", name)
        status = os.path.join(base, "status")
        if not os.path.isfile(status):
            continue
        modes = ",".join(cat(os.path.join(base, "modes"), "").split()) or "-"
        print("  %s status=%s enabled=%s modes=%s" % (
            name, cat(status), cat(os.path.join(base, "enabled")), modes[:200]))


def dump_card(path):
    node = os.path.basename(path)
    print("--- %s driver=%s ---" % (path, driver_of(node)))
    try:
        fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
    except OSError as exc:
        print("  open failed:", exc)
        return
    try:
        raw = bytearray(64)
        try:
            io(fd, GETRESOURCES, raw)
        except OSError as exc:
            print("  GETRESOURCES failed:", exc)
            return
        rec = struct.unpack("<QQQQIIIIIIII", raw)
        ncrtc, nconn, nenc = rec[5], rec[6], rec[7]
        cons = array.array("I", [0] * max(nconn, 1))
        crtcs = array.array("I", [0] * max(ncrtc, 1))
        encs = array.array("I", [0] * max(nenc, 1))
        raw = bytearray(struct.pack(
            "<QQQQIIIIIIII", 0, crtcs.buffer_info()[0], cons.buffer_info()[0],
            encs.buffer_info()[0], 0, ncrtc, nconn, nenc,
            rec[8], rec[9], rec[10], rec[11]))
        io(fd, GETRESOURCES, raw)
        rec = struct.unpack("<QQQQIIIIIIII", raw)
        ncrtc, nconn = rec[5], rec[6]
        print("  crtcs=%d connectors=%d crtc_ids=%s" % (
            ncrtc, nconn, list(crtcs[:ncrtc])))
        for crtc_id in crtcs[:ncrtc]:
            buf = bytearray(104)
            struct.pack_into("<Q7I", buf, 0, 0, 0, crtc_id, 0, 0, 0, 0, 0)
            try:
                io(fd, GETCRTC, buf)
            except OSError as exc:
                print("  crtc %d GETCRTC failed: %s" % (crtc_id, exc))
                continue
            _p, _n, cid, fb, x, y, _g, valid = struct.unpack_from("<Q7I", buf, 0)
            clock, hdisp = struct.unpack_from("<IH", buf, 36)
            vdisp = struct.unpack_from("<H", buf, 36 + 14)[0]
            print("  crtc %d fb=%d pos=%d,%d mode_valid=%d %dx%d" % (
                cid, fb, x, y, valid, hdisp, vdisp))
        for cid in cons[:nconn]:
            dump_connector(fd, cid)
        probe_dumb(fd, node)
    finally:
        os.close(fd)


def dump_connector(fd, cid):
    buf = bytearray(80)
    struct.pack_into("<QQQQ12I", buf, 0, 0, 0, 0, 0, 0, 0, 0, 0, cid, 0, 0, 0, 0, 0, 0, 0)
    try:
        io(fd, GETCONNECTOR, buf)
    except OSError as exc:
        print("  connector %d GETCONNECTOR failed: %s" % (cid, exc))
        return
    count_modes = struct.unpack_from("<I", buf, 32)[0]
    count_props = struct.unpack_from("<I", buf, 36)[0]
    count_encoders = struct.unpack_from("<I", buf, 40)[0]
    modes = bytearray(MODEINFO_SIZE * max(count_modes, 1))
    encoders = array.array("I", [0] * max(count_encoders, 1))
    props = array.array("I", [0] * max(count_props, 1))
    prop_values = array.array("Q", [0] * max(count_props, 1))
    struct.pack_into(
        "<QQQQ12I", buf, 0,
        encoders.buffer_info()[0], ptr(modes), props.buffer_info()[0],
        prop_values.buffer_info()[0], count_modes, count_props, count_encoders,
        0, cid, 0, 0, 0, 0, 0, 0, 0)
    try:
        io(fd, GETCONNECTOR, buf)
    except OSError as exc:
        print("  connector %d fill failed: %s" % (cid, exc))
        return
    unpacked = struct.unpack_from("<QQQQ12I", buf)
    count_modes, encoder_id, cid2, ctype, ctid, st, mmw, mmh = (
        unpacked[4], unpacked[7], unpacked[8], unpacked[9], unpacked[10],
        unpacked[11], unpacked[12], unpacked[13])
    names = []
    for i in range(min(count_modes, 8)):
        off = i * MODEINFO_SIZE
        _clock, hdisp = struct.unpack_from("<IH", modes, off)
        vdisp = struct.unpack_from("<H", modes, off + 14)[0]
        vrefresh = struct.unpack_from("<I", modes, off + 24)[0]
        names.append("%dx%d@%d" % (hdisp, vdisp, vrefresh))
    print("  connector id=%d %s-%d %s encoder=%d mm=%dx%d modes=%d %s" % (
        cid2, CONNECTOR_TYPES.get(ctype, "type%d" % ctype), ctid,
        CONNECTION.get(st, str(st)), encoder_id, mmw, mmh, count_modes,
        ",".join(names) or "-"))


def probe_dumb(fd, node):
    args = struct.pack("<IIIIIIQ", 64, 64, 32, 0, 0, 0, 0)
    buf = ctypes.create_string_buffer(args, 32)
    try:
        io(fd, CREATE_DUMB, buf)
    except OSError as exc:
        code = errno.errorcode.get(exc.errno, exc.errno)
        print("  CREATE_DUMB %s: %s (%s)" % (node, code, exc.strerror))
        return
    _h, _w, _b, _f, handle, pitch, size = struct.unpack("<IIIIIIQ", buf.raw)
    try:
        io(fd, DESTROY_DUMB, ctypes.create_string_buffer(struct.pack("<I", handle), 4))
    except OSError:
        pass
    print("  CREATE_DUMB %s: OK pitch=%d size=%d" % (node, pitch, size))


def dump_minigbm():
    section("minigbm / GBM")
    found = False
    for lib in sorted(glob.glob("/usr/lib64/libminigbm.so.*") +
                      glob.glob("/usr/lib/libminigbm.so.*")):
        if os.path.islink(lib):
            continue
        found = True
        try:
            with open(lib, "rb") as fh:
                blob = fh.read()
        except OSError as exc:
            print("%s unreadable: %s" % (lib, exc.strerror))
            continue
        has = b"nvidia-drm" in blob
        print("%s: nvidia-drm backend %s" % (lib, "PRESENT" if has else "MISSING"))
    if not found:
        print("no libminigbm found")
    for path in ("/usr/lib64/gbm", "/usr/lib/gbm"):
        if os.path.isdir(path):
            print(run(["ls", "-l", path]))


def dump_egl():
    section("EGL / GLX / GBM userspace")
    for path in (
        "/usr/lib64/libEGL_nvidia.so.0",
        "/usr/lib64/libGLX_nvidia.so.0",
        "/usr/lib64/libnvidia-egl-gbm.so.1",
        "/usr/lib64/libminigbm.so.1.0.0",
        "/usr/lib64/gbm/nvidia-drm_gbm.so",
    ):
        print(ls_line(path))
        real = path
        try:
            if os.path.islink(path):
                real = os.path.realpath(path)
                print("  real", ls_line(real))
        except OSError:
            pass
    for d in ("/usr/share/glvnd/egl_vendor.d",
              "/usr/share/egl/egl_external_platform.d"):
        if os.path.isdir(d):
            print(run(["ls", "-l", d]))
    smi = "/usr/bin/nvidia-smi"
    if os.path.isfile(smi):
        print(run([smi, "-L"]))
        print(run([smi, "-q", "-d", "UTILIZATION,TEMPERATURE"], timeout=20)[:1500])


def dump_chrome_conf():
    section("chrome_dev.conf")
    conf = cat("/etc/chrome_dev.conf")
    print(conf if conf != "(missing)" else "(missing)")
    print("-- grepped flags --")
    for line in conf.splitlines():
        if any(k in line for k in (
                "gaia", "oobe", "gpu", "ozone", "skip-force", "sandbox",
                "nvidia", "ignore-gpu")):
            print(line)


def dump_chrome_logs():
    section("Chrome / ui logs (last hits)")
    pattern = (
        r"forcing legacy KMS|Test-modeset|Disabled|3440x1440|Modeset succeeded|"
        r"Couldn't create Gbm|Unable to initialize GBM|Permission denied|"
        r"CRTC-connector|nvidia-drm|HDMI-A-3|connector=134"
    )
    for log in ("/var/log/chrome/chrome", "/var/log/ui/ui.LATEST"):
        if not os.path.isfile(log):
            print("%s: missing" % log)
            continue
        print("-- %s --" % log)
        out = run(["grep", "-iE", pattern, log])
        lines = out.splitlines()
        for line in lines[-40:]:
            print(line)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", help="also write the dump to this file")
    args = parser.parse_args()

    chunks = []

    class Tee:
        def write(self, data):
            sys.__stdout__.write(data)
            chunks.append(data)
            return len(data)

        def flush(self):
            sys.__stdout__.flush()

    if args.out:
        sys.stdout = Tee()  # type: ignore

    print("nvidia-rtx-debug", datetime.now(timezone.utc).isoformat())
    print("host", cat("/etc/lsb-release").replace("\n", " | "))
    dump_pci()
    dump_modules()
    dump_vtcon()
    dump_nodes()
    dump_sysfs_connectors()
    section("ioctl dump")
    cards = sorted(glob.glob("/dev/dri/card*"))
    if not cards:
        print("no /dev/dri/card*")
    for path in cards:
        dump_card(path)
    dump_minigbm()
    dump_egl()
    dump_chrome_conf()
    dump_chrome_logs()
    print()
    print("done. Photo this output, or copy --out file off the device.")

    if args.out:
        sys.stdout = sys.__stdout__
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write("".join(chunks))
        print("wrote", args.out)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
