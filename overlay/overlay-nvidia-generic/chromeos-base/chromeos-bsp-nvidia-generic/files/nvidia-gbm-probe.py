#!/usr/bin/env python3
"""Probe DRM dumb-buffer allocation on every card/render node.

Chrome logs one message for three unrelated failures, all reading as
"Unable to initialize GBM ... Permission denied (13)". gbm_create_device()
returns NULL whenever minigbm has no backend for the DRM driver name, and the
errno printed alongside is whatever was left over. This separates them:

    OK      kernel and driver are fine; a missing minigbm backend is the gap
    EACCES  a real permission problem (udev mode, ACL, sandbox)
    ENOSYS  the driver has no dumb_create (nvidia-drm needs modeset=1)
    ENODEV  no display engine behind the node

Usage: nvidia-gbm-probe
"""

import ctypes
import errno
import fcntl
import glob
import os
import struct
import sys

# DRM_IOWR(0xB2, struct drm_mode_create_dumb)  -- 32 bytes
DRM_IOCTL_MODE_CREATE_DUMB = 0xC02064B2
# DRM_IOWR(0xB4, struct drm_mode_destroy_dumb) -- 4 bytes
DRM_IOCTL_MODE_DESTROY_DUMB = 0xC00464B4


def as_signed(request):
    """fcntl.ioctl wants a value that fits a C int on some Python builds."""
    return request - (1 << 32) if request >= (1 << 31) else request


def driver_of(node):
    link = "/sys/class/drm/%s/device/driver" % node
    try:
        return os.path.basename(os.path.realpath(link))
    except OSError:
        return "?"


def probe(path):
    node = os.path.basename(path)
    driver = driver_of(node)
    try:
        fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
    except OSError as exc:
        return "%-12s driver=%-10s open: %s" % (node, driver, exc.strerror)

    try:
        # height, width, bpp, flags, handle, pitch, size
        args = struct.pack("<IIIIIIQ", 64, 64, 32, 0, 0, 0, 0)
        buf = ctypes.create_string_buffer(args, 32)
        try:
            fcntl.ioctl(fd, as_signed(DRM_IOCTL_MODE_CREATE_DUMB), buf)
        except OSError as exc:
            name = errno.errorcode.get(exc.errno, exc.errno)
            return "%-12s driver=%-10s CREATE_DUMB: %s (%s)" % (
                node, driver, name, exc.strerror)

        _, _, _, _, handle, pitch, size = struct.unpack("<IIIIIIQ", buf.raw)
        try:
            fcntl.ioctl(fd, as_signed(DRM_IOCTL_MODE_DESTROY_DUMB),
                        ctypes.create_string_buffer(struct.pack("<I", handle), 4))
        except OSError:
            pass
        return "%-12s driver=%-10s CREATE_DUMB: OK (pitch=%d size=%d)" % (
            node, driver, pitch, size)
    finally:
        os.close(fd)


def minigbm_backends():
    """Report whether the shipped minigbm knows the nvidia-drm driver name.

    Greping the library by hand dumps the whole string blob, so do it here.
    """
    for lib in sorted(glob.glob("/usr/lib64/libminigbm.so.*")
                      + glob.glob("/usr/lib/libminigbm.so.*")):
        if os.path.islink(lib):
            continue
        try:
            with open(lib, "rb") as handle:
                blob = handle.read()
        except OSError as exc:
            return "%s unreadable: %s" % (lib, exc.strerror)
        has = b"nvidia-drm\x00" in blob or b"nvidia-drm" in blob
        return "%s: nvidia-drm backend %s" % (lib, "PRESENT" if has else "MISSING")
    return "no libminigbm found"


def main():
    nodes = sorted(glob.glob("/dev/dri/card*") + glob.glob("/dev/dri/renderD*"))
    if not nodes:
        print("no /dev/dri nodes; nvidia-drm modeset=1 not loaded?")
        return 1

    for path in nodes:
        st = os.stat(path)
        print("%s mode=%04o" % (path, st.st_mode & 0o7777))
        print("  " + probe(path))

    print()
    print(minigbm_backends())
    print()
    print("With CREATE_DUMB OK and the backend PRESENT, allocation is not the")
    print("blocker. Look at what Chrome does with it next:")
    print("  grep -iE 'Gbm|GBM|EGL|SwiftShader|llvmpipe' /var/log/chrome/chrome | tail -40")
    return 0


if __name__ == "__main__":
    sys.exit(main())
