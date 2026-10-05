#!/usr/bin/env python3
"""Dump DRM connectors, connection status, and modes (no Chrome rebuild).

Usage on the device:
  nvidia-drm-dump
  python3 /usr/sbin/nvidia-drm-dump.py
"""

import array
import ctypes
import fcntl
import glob
import os
import struct
import sys

GETRESOURCES = 0xC04064A0  # DRM_IOWR(0xA0, drm_mode_card_res) 64 bytes
GETCONNECTOR = 0xC05064A7  # DRM_IOWR(0xA7, drm_mode_get_connector) 80 bytes
GETCRTC = 0xC06864A1       # DRM_IOWR(0xA1, drm_mode_crtc) 104 bytes

CONNECTOR_TYPES = {
    0: "Unknown",
    1: "VGA",
    2: "DVII",
    3: "DVID",
    4: "DVIA",
    5: "Composite",
    6: "SVIDEO",
    7: "LVDS",
    8: "Component",
    9: "DIN",
    10: "DP",
    11: "HDMI-A",
    12: "HDMI-B",
    13: "TV",
    14: "eDP",
    15: "VIRTUAL",
    16: "DSI",
    17: "DPI",
    18: "WRITEBACK",
    19: "SPI",
    20: "USB",
}

CONNECTION = {
    1: "connected",
    2: "disconnected",
    3: "unknown",
}

MODEINFO_SIZE = 68


def io(fd, req, buf):
    fcntl.ioctl(fd, req - (1 << 32) if req >= (1 << 31) else req, buf)


def ptr(buf):
    return ctypes.addressof((ctypes.c_char * len(buf)).from_buffer(buf))


def driver_of(node):
    link = "/sys/class/drm/%s/device/driver" % node
    try:
        return os.path.basename(os.path.realpath(link))
    except OSError:
        return "?"


def dump_sysfs():
    print("=== /sys/class/drm ===")
    try:
        names = sorted(os.listdir("/sys/class/drm"))
    except OSError as exc:
        print("  unreadable:", exc)
        return
    print("  entries:", " ".join(names) if names else "(empty)")
    for name in names:
        base = os.path.join("/sys/class/drm", name)
        status = os.path.join(base, "status")
        if not os.path.isfile(status):
            continue
        enabled_path = os.path.join(base, "enabled")
        modes_path = os.path.join(base, "modes")
        try:
            st = open(status).read().strip()
        except OSError:
            st = "?"
        try:
            en = open(enabled_path).read().strip()
        except OSError:
            en = "?"
        try:
            modes = ",".join(open(modes_path).read().split()) or "-"
        except OSError:
            modes = "-"
        print("  %s status=%s enabled=%s modes=%s" % (name, st, en, modes))


def dump_card(path):
    node = os.path.basename(path)
    print("=== %s driver=%s ===" % (path, driver_of(node)))
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
        minw, maxw, minh, maxh = rec[8], rec[9], rec[10], rec[11]
        cons = array.array("I", [0] * max(nconn, 1))
        crtcs = array.array("I", [0] * max(ncrtc, 1))
        encs = array.array("I", [0] * max(nenc, 1))
        raw = bytearray(struct.pack(
            "<QQQQIIIIIIII",
            0,
            crtcs.buffer_info()[0],
            cons.buffer_info()[0],
            encs.buffer_info()[0],
            0, ncrtc, nconn, nenc,
            minw, maxw, minh, maxh,
        ))
        io(fd, GETRESOURCES, raw)
        rec = struct.unpack("<QQQQIIIIIIII", raw)
        ncrtc, nconn, nenc = rec[5], rec[6], rec[7]
        print("  crtcs=%d connectors=%d encoders=%d size=%dx%d..%dx%d" % (
            ncrtc, nconn, nenc, rec[8], rec[10], rec[9], rec[11]))
        print("  crtc_ids=%s" % (list(crtcs[:ncrtc]),))

        for crtc_id in crtcs[:ncrtc]:
            dump_crtc(fd, crtc_id)

        for cid in cons[:nconn]:
            dump_connector(fd, cid)
    finally:
        os.close(fd)


def dump_crtc(fd, crtc_id):
    # drm_mode_crtc: u64 + 7*u32 + modeinfo(68) = 104
    buf = bytearray(104)
    struct.pack_into("<Q7I", buf, 0, 0, 0, crtc_id, 0, 0, 0, 0, 0)
    try:
        io(fd, GETCRTC, buf)
    except OSError as exc:
        print("  crtc %d GETCRTC failed: %s" % (crtc_id, exc))
        return
    _ptr, _n, cid, fb, x, y, gamma, valid = struct.unpack_from("<Q7I", buf, 0)
    clock, hdisp = struct.unpack_from("<IH", buf, 36)
    vdisp = struct.unpack_from("<H", buf, 36 + 14)[0]
    name = buf[36 + 36:36 + 68].split(b"\x00", 1)[0].decode("ascii", "replace")
    print("  crtc %d fb=%d pos=%d,%d mode_valid=%d %dx%d %s" % (
        cid, fb, x, y, valid, hdisp, vdisp, name or "-"))


def dump_connector(fd, cid):
    buf = bytearray(80)
    struct.pack_into("<QQQQ12I", buf, 0, 0, 0, 0, 0, 0, 0, 0, 0, cid, 0, 0, 0, 0, 0, 0, 0)
    try:
        io(fd, GETCONNECTOR, buf)
    except OSError as exc:
        print("  connector %d GETCONNECTOR failed: %s" % (cid, exc))
        return

    unpacked = struct.unpack_from("<QQQQ12I", buf)
    count_modes = unpacked[4]
    count_props = unpacked[5]
    count_encoders = unpacked[6]

    modes = bytearray(MODEINFO_SIZE * max(count_modes, 1))
    encoders = array.array("I", [0] * max(count_encoders, 1))
    props = array.array("I", [0] * max(count_props, 1))
    prop_values = array.array("Q", [0] * max(count_props, 1))
    struct.pack_into(
        "<QQQQ12I", buf, 0,
        encoders.buffer_info()[0],
        ptr(modes),
        props.buffer_info()[0],
        prop_values.buffer_info()[0],
        count_modes, count_props, count_encoders,
        0, cid, 0, 0, 0, 0, 0, 0, 0,
    )
    try:
        io(fd, GETCONNECTOR, buf)
    except OSError as exc:
        print("  connector %d GETCONNECTOR(fill) failed: %s" % (cid, exc))
        return

    (_encp, _mp, _pp, _pvp, count_modes, count_props, count_encoders,
     encoder_id, cid2, ctype, ctype_id, connection, mmw, mmh, sub, _pad) = (
        struct.unpack_from("<QQQQ12I", buf))

    names = []
    for i in range(count_modes):
        off = i * MODEINFO_SIZE
        clock, hdisp = struct.unpack_from("<IH", modes, off)
        vdisp = struct.unpack_from("<H", modes, off + 14)[0]
        vrefresh = struct.unpack_from("<I", modes, off + 24)[0]
        mname = modes[off + 36:off + 68].split(b"\x00", 1)[0].decode("ascii", "replace")
        names.append("%s %dx%d@%d" % (mname or "mode", hdisp, vdisp, vrefresh))

    print("  connector id=%d %s-%d %s encoder=%d mm=%dx%d modes=%d" % (
        cid2,
        CONNECTOR_TYPES.get(ctype, "type%d" % ctype),
        ctype_id,
        CONNECTION.get(connection, str(connection)),
        encoder_id, mmw, mmh, count_modes))
    if names:
        print("    " + "; ".join(names[:12]))
        if len(names) > 12:
            print("    ... +%d more" % (len(names) - 12))
    else:
        print("    (no modes)")


def main():
    dump_sysfs()
    print()
    cards = sorted(glob.glob("/dev/dri/card*"))
    if not cards:
        print("no /dev/dri/card* nodes")
        return 1
    for path in cards:
        dump_card(path)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
