/* libdrm.so.2 stand-in: forward to CrOS libdrm, retry AddFB2 with LINEAR modifiers.
 * Also auto-SetCrtc Chrome FBs and block blanking SetCrtc(fb=0) — Ash reaches login
 * but never commits modeset on nvidia-drm.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void dlog(const char *fmt, ...) {
  FILE *f = fopen("/usr/local/tmp/drm-addfb.log", "a");
  va_list ap;
  va_start(ap, fmt);
  if (f) {
    vfprintf(f, fmt, ap);
    fclose(f);
  }
  va_end(ap);
}

#ifndef DRM_MODE_FB_MODIFIERS
#define DRM_MODE_FB_MODIFIERS (1U << 1)
#endif

/* Saved scanout target for auto-modeset / anti-blank. */
static int g_auto_fd = -1;
static uint32_t g_auto_fb;
static uint32_t g_auto_conn;
static uint32_t g_auto_crtc;
static struct drm_mode_modeinfo g_auto_mode;
static int g_auto_have_mode;
static int g_auto_modeset_ok;
static int g_chrome_real_modeset; /* Chrome SetCrtc/PageFlip with fb!=0 */

static uint32_t g_tgt_encoder;

static int load_modeset_target(uint32_t *conn_out, uint32_t *crtc_out,
                               struct drm_mode_modeinfo *mode_out) {
  FILE *tf = fopen("/usr/local/tmp/drm-modeset-target", "r");
  char line[128];
  uint32_t crtc = 0, conn = 0, enc = 0;
  struct drm_mode_modeinfo m;
  if (!tf)
    return -1;
  memset(&m, 0, sizeof(m));
  while (fgets(line, sizeof(line), tf)) {
    unsigned v;
    if (sscanf(line, "crtc=%u", &v) == 1)
      crtc = v;
    else if (sscanf(line, "connector=%u", &v) == 1)
      conn = v;
    else if (sscanf(line, "encoder=%u", &v) == 1)
      enc = v;
    else if (sscanf(line, "clock=%u", &v) == 1)
      m.clock = v;
    else if (sscanf(line, "hdisplay=%u", &v) == 1)
      m.hdisplay = (uint16_t)v;
    else if (sscanf(line, "hsync_start=%u", &v) == 1)
      m.hsync_start = (uint16_t)v;
    else if (sscanf(line, "hsync_end=%u", &v) == 1)
      m.hsync_end = (uint16_t)v;
    else if (sscanf(line, "htotal=%u", &v) == 1)
      m.htotal = (uint16_t)v;
    else if (sscanf(line, "hskew=%u", &v) == 1)
      m.hskew = (uint16_t)v;
    else if (sscanf(line, "vdisplay=%u", &v) == 1)
      m.vdisplay = (uint16_t)v;
    else if (sscanf(line, "vsync_start=%u", &v) == 1)
      m.vsync_start = (uint16_t)v;
    else if (sscanf(line, "vsync_end=%u", &v) == 1)
      m.vsync_end = (uint16_t)v;
    else if (sscanf(line, "vtotal=%u", &v) == 1)
      m.vtotal = (uint16_t)v;
    else if (sscanf(line, "vscan=%u", &v) == 1)
      m.vscan = (uint16_t)v;
    else if (sscanf(line, "vrefresh=%u", &v) == 1)
      m.vrefresh = v;
    else if (sscanf(line, "flags=%u", &v) == 1)
      m.flags = v;
    else if (sscanf(line, "type=%u", &v) == 1)
      m.type = v;
  }
  fclose(tf);
  if (!crtc || !conn || !m.hdisplay || !m.vdisplay)
    return -1;
  *crtc_out = crtc;
  *conn_out = conn;
  *mode_out = m;
  g_tgt_encoder = enc;
  dlog("drm-addfb-compat: loaded modeset-target crtc=%u conn=%u enc=%u %ux%u\n", crtc,
       conn, enc, m.hdisplay, m.vdisplay);
  return 0;
}

static int auto_pick_connector(int fd, int (*real)(int, unsigned long, void *),
                               uint32_t *conn_out, uint32_t *crtc_out,
                               struct drm_mode_modeinfo *mode_out) {
  struct drm_mode_card_res res;
  uint32_t conn_ids[32], crtc_ids[32], enc_ids[32];
  uint32_t i;
  /* Prefer root probe results — Chrome often sees connection=0 here. */
  if (load_modeset_target(conn_out, crtc_out, mode_out) == 0)
    return 0;
  memset(&res, 0, sizeof(res));
  res.count_connectors = 32;
  res.count_crtcs = 32;
  res.count_encoders = 32;
  res.connector_id_ptr = (uint64_t)(uintptr_t)conn_ids;
  res.crtc_id_ptr = (uint64_t)(uintptr_t)crtc_ids;
  res.encoder_id_ptr = (uint64_t)(uintptr_t)enc_ids;
  if (real(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) != 0) {
    dlog("drm-addfb-compat: GETRESOURCES errno=%d\n", errno);
    return -1;
  }
  dlog("drm-addfb-compat: probe crtcs=%u connectors=%u\n", res.count_crtcs,
       res.count_connectors);
  for (i = 0; i < res.count_connectors && i < 32; i++) {
    struct drm_mode_get_connector c;
    struct drm_mode_modeinfo modes[64];
    uint32_t encoders[8];
    uint32_t enc_id = 0, crtc_id = 0;
    memset(&c, 0, sizeof(c));
    c.connector_id = conn_ids[i];
    if (real(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0)
      continue;
    if (c.count_modes > 64)
      c.count_modes = 64;
    if (c.count_encoders > 8)
      c.count_encoders = 8;
    memset(modes, 0, sizeof(modes));
    c.modes_ptr = (uint64_t)(uintptr_t)modes;
    c.encoders_ptr = (uint64_t)(uintptr_t)encoders;
    if (real(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0)
      continue;
    dlog("drm-addfb-compat: conn id=%u type=%u connection=%u modes=%u\n",
         c.connector_id, c.connector_type, c.connection, c.count_modes);
    if (!(c.count_modes > 0 && c.connection != 2))
      continue;
    enc_id = c.encoder_id ? c.encoder_id : (c.count_encoders ? encoders[0] : 0);
    if (enc_id) {
      struct drm_mode_get_encoder e;
      memset(&e, 0, sizeof(e));
      e.encoder_id = enc_id;
      if (real(fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0) {
        crtc_id = e.crtc_id;
        if (!crtc_id) {
          uint32_t j;
          for (j = 0; j < res.count_crtcs && j < 32; j++) {
            if (e.possible_crtcs & (1u << j)) {
              crtc_id = crtc_ids[j];
              break;
            }
          }
        }
      }
    }
    if (!crtc_id && res.count_crtcs)
      crtc_id = crtc_ids[0];
    if (!crtc_id)
      continue;
    *conn_out = c.connector_id;
    *crtc_out = crtc_id;
    *mode_out = modes[0];
    return 0;
  }
  return -1;
}

static int auto_setcrtc(int fd, uint32_t fb_id, int (*real)(int, unsigned long, void *)) {
  struct drm_mode_crtc c;
  uint32_t conn;
  if (!g_auto_have_mode) {
    if (auto_pick_connector(fd, real, &g_auto_conn, &g_auto_crtc, &g_auto_mode) != 0) {
      dlog("drm-addfb-compat: auto-modeset no connector\n");
      return -1;
    }
    g_auto_have_mode = 1;
    dlog("drm-addfb-compat: auto-modeset picked crtc=%u conn=%u %ux%u\n", g_auto_crtc,
         g_auto_conn, g_auto_mode.hdisplay, g_auto_mode.vdisplay);
  }
  conn = g_auto_conn;
  memset(&c, 0, sizeof(c));
  c.crtc_id = g_auto_crtc;
  c.fb_id = fb_id;
  c.set_connectors_ptr = (uint64_t)(uintptr_t)&conn;
  c.count_connectors = 1;
  c.mode = g_auto_mode;
  c.mode_valid = 1;
  if (real(fd, DRM_IOCTL_SET_MASTER, 0) != 0) {
    /* may already be master */
  }
  if (real(fd, DRM_IOCTL_MODE_SETCRTC, &c) != 0) {
    dlog("drm-addfb-compat: auto-SetCrtc fb=%u FAILED errno=%d\n", fb_id, errno);
    return -1;
  }
  g_auto_fd = fd;
  g_auto_fb = fb_id;
  g_auto_modeset_ok = 1;
  dlog("drm-addfb-compat: auto-SetCrtc OK fb=%u crtc=%u\n", fb_id, g_auto_crtc);
  return 0;
}

/* After the first modeset, only pageflip — repeated SetCrtc freezes Ash (no present). */
static int auto_pageflip(int fd, uint32_t fb_id, int (*real)(int, unsigned long, void *)) {
  struct drm_mode_crtc_page_flip flip;
  if (!g_auto_modeset_ok || !g_auto_crtc || !fb_id)
    return -1;
  memset(&flip, 0, sizeof(flip));
  flip.crtc_id = g_auto_crtc;
  flip.fb_id = fb_id;
  flip.flags = 0;
  if (real(fd, DRM_IOCTL_MODE_PAGE_FLIP, &flip) != 0) {
    dlog("drm-addfb-compat: auto-PageFlip fb=%u FAILED errno=%d\n", fb_id, errno);
    return -1;
  }
  g_auto_fb = fb_id;
  dlog("drm-addfb-compat: auto-PageFlip OK fb=%u crtc=%u\n", fb_id, g_auto_crtc);
  return 0;
}

static void auto_present(int fd, uint32_t fb_id, uint32_t width, uint32_t height,
                         int (*real)(int, unsigned long, void *)) {
  /* Only bootstrap one SetCrtc if Chrome still won't modeset. Continuous
   * PageFlip-on-AddFB is wrong (AddFB is alloc, not present) and freezes Ash. */
  if (g_chrome_real_modeset || g_auto_modeset_ok || width < 1920 || height < 1080 ||
      !fb_id || !real)
    return;
  auto_setcrtc(fd, fb_id, real);
}

/* Chrome's GPU process often sees connection=0 on nvidia-drm; without a
 * connected connector it never modesets, so DrmWindow skips real pageflips
 * (PresentationFeedback::Failure) and the login UI freezes after ~2 frames.
 * Rewrite GETCONNECTOR using drm-modeset-target from the root probe. */
static int fake_connector_from_target(struct drm_mode_get_connector *c) {
  uint32_t conn = 0, crtc = 0;
  struct drm_mode_modeinfo mode;
  if (load_modeset_target(&conn, &crtc, &mode) != 0)
    return -1;
  if (c->connector_id != conn && c->connector_id != 0)
    return -1;
  c->connection = 1; /* DRM_MODE_CONNECTED */
  c->connector_id = conn;
  if (c->count_modes < 1)
    c->count_modes = 1;
  if (c->modes_ptr && c->count_modes >= 1) {
    struct drm_mode_modeinfo *dst =
        (struct drm_mode_modeinfo *)(uintptr_t)c->modes_ptr;
    dst[0] = mode;
  }
  {
    uint32_t enc = g_tgt_encoder ? g_tgt_encoder : 126;
    if (!c->encoder_id)
      c->encoder_id = enc;
    if (c->count_encoders < 1)
      c->count_encoders = 1;
    if (c->encoders_ptr) {
      uint32_t *encs = (uint32_t *)(uintptr_t)c->encoders_ptr;
      encs[0] = enc;
    }
  }
  dlog("drm-addfb-compat: fake GETCONNECTOR id=%u connected mode=%ux%u encoders=%u\n",
       conn, mode.hdisplay, mode.vdisplay, c->count_encoders);
  return 0;
}

void *drm_compat_real_lib;
int (* __attribute__((visibility("hidden"))) real_drmModeAddFB2)(int, uint32_t, uint32_t, uint32_t, const uint32_t *,
                          const uint32_t *, const uint32_t *, uint32_t *, uint32_t);
int (* __attribute__((visibility("hidden"))) real_drmModeAddFB2WithModifiers)(int, uint32_t, uint32_t, uint32_t, const uint32_t *,
                                       const uint32_t *, const uint32_t *, const uint64_t *,
                                       uint32_t *, uint32_t);
void * __attribute__((visibility("hidden"))) real_drmAddBufs;
void * __attribute__((visibility("hidden"))) real_drmAddContextPrivateMapping;
void * __attribute__((visibility("hidden"))) real_drmAddContextTag;
void * __attribute__((visibility("hidden"))) real_drmAddMap;
void * __attribute__((visibility("hidden"))) real_drmAgpAcquire;
void * __attribute__((visibility("hidden"))) real_drmAgpAlloc;
void * __attribute__((visibility("hidden"))) real_drmAgpBase;
void * __attribute__((visibility("hidden"))) real_drmAgpBind;
void * __attribute__((visibility("hidden"))) real_drmAgpDeviceId;
void * __attribute__((visibility("hidden"))) real_drmAgpEnable;
void * __attribute__((visibility("hidden"))) real_drmAgpFree;
void * __attribute__((visibility("hidden"))) real_drmAgpGetMode;
void * __attribute__((visibility("hidden"))) real_drmAgpMemoryAvail;
void * __attribute__((visibility("hidden"))) real_drmAgpMemoryUsed;
void * __attribute__((visibility("hidden"))) real_drmAgpRelease;
void * __attribute__((visibility("hidden"))) real_drmAgpSize;
void * __attribute__((visibility("hidden"))) real_drmAgpUnbind;
void * __attribute__((visibility("hidden"))) real_drmAgpVendorId;
void * __attribute__((visibility("hidden"))) real_drmAgpVersionMajor;
void * __attribute__((visibility("hidden"))) real_drmAgpVersionMinor;
void * __attribute__((visibility("hidden"))) real_drmAuthMagic;
void * __attribute__((visibility("hidden"))) real_drmAvailable;
void * __attribute__((visibility("hidden"))) real_drmCheckModesettingSupported;
void * __attribute__((visibility("hidden"))) real_drmClose;
void * __attribute__((visibility("hidden"))) real_drmCloseBufferHandle;
void * __attribute__((visibility("hidden"))) real_drmCloseOnce;
void * __attribute__((visibility("hidden"))) real_drmCommandNone;
void * __attribute__((visibility("hidden"))) real_drmCommandRead;
void * __attribute__((visibility("hidden"))) real_drmCommandWrite;
void * __attribute__((visibility("hidden"))) real_drmCommandWriteRead;
void * __attribute__((visibility("hidden"))) real_drmCreateContext;
void * __attribute__((visibility("hidden"))) real_drmCreateDrawable;
void * __attribute__((visibility("hidden"))) real_drmCrtcGetSequence;
void * __attribute__((visibility("hidden"))) real_drmCrtcQueueSequence;
void * __attribute__((visibility("hidden"))) real_drmCtlInstHandler;
void * __attribute__((visibility("hidden"))) real_drmCtlUninstHandler;
void * __attribute__((visibility("hidden"))) real_drmDelContextTag;
void * __attribute__((visibility("hidden"))) real_drmDestroyContext;
void * __attribute__((visibility("hidden"))) real_drmDestroyDrawable;
void * __attribute__((visibility("hidden"))) real_drmDevicesEqual;
void * __attribute__((visibility("hidden"))) real_drmDMA;
void * __attribute__((visibility("hidden"))) real_drmDropMaster;
void * __attribute__((visibility("hidden"))) real_drmError;
void * __attribute__((visibility("hidden"))) real_drmFinish;
void * __attribute__((visibility("hidden"))) real_drmFree;
void * __attribute__((visibility("hidden"))) real_drmFreeBufs;
void * __attribute__((visibility("hidden"))) real_drmFreeBusid;
void * __attribute__((visibility("hidden"))) real_drmFreeDevice;
void * __attribute__((visibility("hidden"))) real_drmFreeDevices;
void * __attribute__((visibility("hidden"))) real_drmFreeReservedContextList;
void * __attribute__((visibility("hidden"))) real_drmFreeVersion;
void * __attribute__((visibility("hidden"))) real_drmGetBufInfo;
void * __attribute__((visibility("hidden"))) real_drmGetBusid;
void * __attribute__((visibility("hidden"))) real_drmGetCap;
void * __attribute__((visibility("hidden"))) real_drmGetClient;
void * __attribute__((visibility("hidden"))) real_drmGetContextFlags;
void * __attribute__((visibility("hidden"))) real_drmGetContextPrivateMapping;
void * __attribute__((visibility("hidden"))) real_drmGetContextTag;
void * __attribute__((visibility("hidden"))) real_drmGetDevice;
void * __attribute__((visibility("hidden"))) real_drmGetDevice2;
void * __attribute__((visibility("hidden"))) real_drmGetDeviceFromDevId;
void * __attribute__((visibility("hidden"))) real_drmGetDeviceNameFromFd;
void * __attribute__((visibility("hidden"))) real_drmGetDeviceNameFromFd2;
void * __attribute__((visibility("hidden"))) real_drmGetDevices;
void * __attribute__((visibility("hidden"))) real_drmGetDevices2;
void * __attribute__((visibility("hidden"))) real_drmGetEntry;
void * __attribute__((visibility("hidden"))) real_drmGetFormatModifierName;
void * __attribute__((visibility("hidden"))) real_drmGetFormatModifierVendor;
void * __attribute__((visibility("hidden"))) real_drmGetFormatName;
void * __attribute__((visibility("hidden"))) real_drmGetHashTable;
void * __attribute__((visibility("hidden"))) real_drmGetInterruptFromBusID;
void * __attribute__((visibility("hidden"))) real_drmGetLibVersion;
void * __attribute__((visibility("hidden"))) real_drmGetLock;
void * __attribute__((visibility("hidden"))) real_drmGetMagic;
void * __attribute__((visibility("hidden"))) real_drmGetMap;
void * __attribute__((visibility("hidden"))) real_drmGetNodeTypeFromDevId;
void * __attribute__((visibility("hidden"))) real_drmGetNodeTypeFromFd;
void * __attribute__((visibility("hidden"))) real_drmGetPrimaryDeviceNameFromFd;
void * __attribute__((visibility("hidden"))) real_drmGetRenderDeviceNameFromFd;
void * __attribute__((visibility("hidden"))) real_drmGetReservedContextList;
void * __attribute__((visibility("hidden"))) real_drmGetStats;
void * __attribute__((visibility("hidden"))) real_drmGetVersion;
void * __attribute__((visibility("hidden"))) real_drmHandleEvent;
void * __attribute__((visibility("hidden"))) real_drmHashCreate;
void * __attribute__((visibility("hidden"))) real_drmHashDelete;
void * __attribute__((visibility("hidden"))) real_drmHashDestroy;
void * __attribute__((visibility("hidden"))) real_drmHashFirst;
void * __attribute__((visibility("hidden"))) real_drmHashInsert;
void * __attribute__((visibility("hidden"))) real_drmHashLookup;
void * __attribute__((visibility("hidden"))) real_drmHashNext;
void * __attribute__((visibility("hidden"))) real_drmIoctl;
void * __attribute__((visibility("hidden"))) real_drmIsKMS;
void * __attribute__((visibility("hidden"))) real_drmIsMaster;
void * __attribute__((visibility("hidden"))) real_drmMalloc;
void * __attribute__((visibility("hidden"))) real_drmMap;
void * __attribute__((visibility("hidden"))) real_drmMapBufs;
void * __attribute__((visibility("hidden"))) real_drmMarkBufs;
void * __attribute__((visibility("hidden"))) real_drmModeAddFB;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicAddProperty;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicAlloc;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicCommit;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicDuplicate;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicFree;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicGetCursor;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicMerge;
void * __attribute__((visibility("hidden"))) real_drmModeAtomicSetCursor;
void * __attribute__((visibility("hidden"))) real_drmModeAttachMode;
void * __attribute__((visibility("hidden"))) real_drmModeCloseFB;
void * __attribute__((visibility("hidden"))) real_drmModeConnectorGetPossibleCrtcs;
void * __attribute__((visibility("hidden"))) real_drmModeConnectorSetProperty;
void * __attribute__((visibility("hidden"))) real_drmModeCreateDumbBuffer;
void * __attribute__((visibility("hidden"))) real_drmModeCreateLease;
void * __attribute__((visibility("hidden"))) real_drmModeCreatePropertyBlob;
void * __attribute__((visibility("hidden"))) real_drmModeCrtcGetGamma;
void * __attribute__((visibility("hidden"))) real_drmModeCrtcSetGamma;
void * __attribute__((visibility("hidden"))) real_drmModeDestroyDumbBuffer;
void * __attribute__((visibility("hidden"))) real_drmModeDestroyPropertyBlob;
void * __attribute__((visibility("hidden"))) real_drmModeDetachMode;
void * __attribute__((visibility("hidden"))) real_drmModeDirtyFB;
void * __attribute__((visibility("hidden"))) real_drmModeFormatModifierBlobIterNext;
void * __attribute__((visibility("hidden"))) real_drmModeFreeConnector;
void * __attribute__((visibility("hidden"))) real_drmModeFreeCrtc;
void * __attribute__((visibility("hidden"))) real_drmModeFreeEncoder;
void * __attribute__((visibility("hidden"))) real_drmModeFreeFB;
void * __attribute__((visibility("hidden"))) real_drmModeFreeFB2;
void * __attribute__((visibility("hidden"))) real_drmModeFreeModeInfo;
void * __attribute__((visibility("hidden"))) real_drmModeFreeObjectProperties;
void * __attribute__((visibility("hidden"))) real_drmModeFreePlane;
void * __attribute__((visibility("hidden"))) real_drmModeFreePlaneResources;
void * __attribute__((visibility("hidden"))) real_drmModeFreeProperty;
void * __attribute__((visibility("hidden"))) real_drmModeFreePropertyBlob;
void * __attribute__((visibility("hidden"))) real_drmModeFreeResources;
void * __attribute__((visibility("hidden"))) real_drmModeGetConnector;
void * __attribute__((visibility("hidden"))) real_drmModeGetConnectorCurrent;
void * __attribute__((visibility("hidden"))) real_drmModeGetConnectorTypeName;
void * __attribute__((visibility("hidden"))) real_drmModeGetCrtc;
void * __attribute__((visibility("hidden"))) real_drmModeGetEncoder;
void * __attribute__((visibility("hidden"))) real_drmModeGetFB;
void * __attribute__((visibility("hidden"))) real_drmModeGetFB2;
void * __attribute__((visibility("hidden"))) real_drmModeGetLease;
void * __attribute__((visibility("hidden"))) real_drmModeGetPlane;
void * __attribute__((visibility("hidden"))) real_drmModeGetPlaneResources;
void * __attribute__((visibility("hidden"))) real_drmModeGetProperty;
void * __attribute__((visibility("hidden"))) real_drmModeGetPropertyBlob;
void * __attribute__((visibility("hidden"))) real_drmModeGetResources;
void * __attribute__((visibility("hidden"))) real_drmModeListLessees;
void * __attribute__((visibility("hidden"))) real_drmModeMapDumbBuffer;
void * __attribute__((visibility("hidden"))) real_drmModeMoveCursor;
void * __attribute__((visibility("hidden"))) real_drmModeObjectGetProperties;
void * __attribute__((visibility("hidden"))) real_drmModeObjectSetProperty;
void * __attribute__((visibility("hidden"))) real_drmModePageFlip;
void * __attribute__((visibility("hidden"))) real_drmModePageFlipTarget;
void * __attribute__((visibility("hidden"))) real_drmModeRevokeLease;
void * __attribute__((visibility("hidden"))) real_drmModeRmFB;
void * __attribute__((visibility("hidden"))) real_drmModeSetCrtc;
void * __attribute__((visibility("hidden"))) real_drmModeSetCursor;
void * __attribute__((visibility("hidden"))) real_drmModeSetCursor2;
void * __attribute__((visibility("hidden"))) real_drmModeSetPlane;
void * __attribute__((visibility("hidden"))) real_drmMsg;
void * __attribute__((visibility("hidden"))) real_drmOpen;
void * __attribute__((visibility("hidden"))) real_drmOpenControl;
void * __attribute__((visibility("hidden"))) real_drmOpenOnce;
void * __attribute__((visibility("hidden"))) real_drmOpenOnceWithType;
void * __attribute__((visibility("hidden"))) real_drmOpenRender;
void * __attribute__((visibility("hidden"))) real_drmOpenWithType;
void * __attribute__((visibility("hidden"))) real_drmPrimeFDToHandle;
void * __attribute__((visibility("hidden"))) real_drmPrimeHandleToFD;
void * __attribute__((visibility("hidden"))) real_drmRandom;
void * __attribute__((visibility("hidden"))) real_drmRandomCreate;
void * __attribute__((visibility("hidden"))) real_drmRandomDestroy;
void * __attribute__((visibility("hidden"))) real_drmRandomDouble;
void * __attribute__((visibility("hidden"))) real_drmRmMap;
void * __attribute__((visibility("hidden"))) real_drmScatterGatherAlloc;
void * __attribute__((visibility("hidden"))) real_drmScatterGatherFree;
void * __attribute__((visibility("hidden"))) real_drmSetBusid;
void * __attribute__((visibility("hidden"))) real_drmSetClientCap;
void * __attribute__((visibility("hidden"))) real_drmSetContextFlags;
void * __attribute__((visibility("hidden"))) real_drmSetInterfaceVersion;
void * __attribute__((visibility("hidden"))) real_drmSetMaster;
void * __attribute__((visibility("hidden"))) real_drmSetServerInfo;
void * __attribute__((visibility("hidden"))) real_drmSLCreate;
void * __attribute__((visibility("hidden"))) real_drmSLDelete;
void * __attribute__((visibility("hidden"))) real_drmSLDestroy;
void * __attribute__((visibility("hidden"))) real_drmSLDump;
void * __attribute__((visibility("hidden"))) real_drmSLFirst;
void * __attribute__((visibility("hidden"))) real_drmSLInsert;
void * __attribute__((visibility("hidden"))) real_drmSLLookup;
void * __attribute__((visibility("hidden"))) real_drmSLLookupNeighbors;
void * __attribute__((visibility("hidden"))) real_drmSLNext;
void * __attribute__((visibility("hidden"))) real_drmSwitchToContext;
void * __attribute__((visibility("hidden"))) real_drmSyncobjCreate;
void * __attribute__((visibility("hidden"))) real_drmSyncobjDestroy;
void * __attribute__((visibility("hidden"))) real_drmSyncobjEventfd;
void * __attribute__((visibility("hidden"))) real_drmSyncobjExportSyncFile;
void * __attribute__((visibility("hidden"))) real_drmSyncobjFDToHandle;
void * __attribute__((visibility("hidden"))) real_drmSyncobjHandleToFD;
void * __attribute__((visibility("hidden"))) real_drmSyncobjImportSyncFile;
void * __attribute__((visibility("hidden"))) real_drmSyncobjQuery;
void * __attribute__((visibility("hidden"))) real_drmSyncobjQuery2;
void * __attribute__((visibility("hidden"))) real_drmSyncobjReset;
void * __attribute__((visibility("hidden"))) real_drmSyncobjSignal;
void * __attribute__((visibility("hidden"))) real_drmSyncobjTimelineSignal;
void * __attribute__((visibility("hidden"))) real_drmSyncobjTimelineWait;
void * __attribute__((visibility("hidden"))) real_drmSyncobjTransfer;
void * __attribute__((visibility("hidden"))) real_drmSyncobjWait;
void * __attribute__((visibility("hidden"))) real_drmUnlock;
void * __attribute__((visibility("hidden"))) real_drmUnmap;
void * __attribute__((visibility("hidden"))) real_drmUnmapBufs;
void * __attribute__((visibility("hidden"))) real_drmUpdateDrawableInfo;
void * __attribute__((visibility("hidden"))) real_drmWaitVBlank;

__attribute__((constructor)) static void drm_compat_init(void) {
  const char *cands[] = {
      "/usr/lib64/libdrm.so.2.124.0",
      "/lib64/libdrm.so.2.124.0",
      0};
  for (int i = 0; cands[i]; i++) {
    drm_compat_real_lib = dlopen(cands[i], RTLD_NOW | RTLD_LOCAL);
    if (drm_compat_real_lib)
      break;
  }
  if (!drm_compat_real_lib) {
    dlog("drm-addfb-compat: dlopen libdrm failed: %s\n", dlerror());
    return;
  }
  real_drmAddBufs = dlsym(drm_compat_real_lib, "drmAddBufs");
  real_drmAddContextPrivateMapping = dlsym(drm_compat_real_lib, "drmAddContextPrivateMapping");
  real_drmAddContextTag = dlsym(drm_compat_real_lib, "drmAddContextTag");
  real_drmAddMap = dlsym(drm_compat_real_lib, "drmAddMap");
  real_drmAgpAcquire = dlsym(drm_compat_real_lib, "drmAgpAcquire");
  real_drmAgpAlloc = dlsym(drm_compat_real_lib, "drmAgpAlloc");
  real_drmAgpBase = dlsym(drm_compat_real_lib, "drmAgpBase");
  real_drmAgpBind = dlsym(drm_compat_real_lib, "drmAgpBind");
  real_drmAgpDeviceId = dlsym(drm_compat_real_lib, "drmAgpDeviceId");
  real_drmAgpEnable = dlsym(drm_compat_real_lib, "drmAgpEnable");
  real_drmAgpFree = dlsym(drm_compat_real_lib, "drmAgpFree");
  real_drmAgpGetMode = dlsym(drm_compat_real_lib, "drmAgpGetMode");
  real_drmAgpMemoryAvail = dlsym(drm_compat_real_lib, "drmAgpMemoryAvail");
  real_drmAgpMemoryUsed = dlsym(drm_compat_real_lib, "drmAgpMemoryUsed");
  real_drmAgpRelease = dlsym(drm_compat_real_lib, "drmAgpRelease");
  real_drmAgpSize = dlsym(drm_compat_real_lib, "drmAgpSize");
  real_drmAgpUnbind = dlsym(drm_compat_real_lib, "drmAgpUnbind");
  real_drmAgpVendorId = dlsym(drm_compat_real_lib, "drmAgpVendorId");
  real_drmAgpVersionMajor = dlsym(drm_compat_real_lib, "drmAgpVersionMajor");
  real_drmAgpVersionMinor = dlsym(drm_compat_real_lib, "drmAgpVersionMinor");
  real_drmAuthMagic = dlsym(drm_compat_real_lib, "drmAuthMagic");
  real_drmAvailable = dlsym(drm_compat_real_lib, "drmAvailable");
  real_drmCheckModesettingSupported = dlsym(drm_compat_real_lib, "drmCheckModesettingSupported");
  real_drmClose = dlsym(drm_compat_real_lib, "drmClose");
  real_drmCloseBufferHandle = dlsym(drm_compat_real_lib, "drmCloseBufferHandle");
  real_drmCloseOnce = dlsym(drm_compat_real_lib, "drmCloseOnce");
  real_drmCommandNone = dlsym(drm_compat_real_lib, "drmCommandNone");
  real_drmCommandRead = dlsym(drm_compat_real_lib, "drmCommandRead");
  real_drmCommandWrite = dlsym(drm_compat_real_lib, "drmCommandWrite");
  real_drmCommandWriteRead = dlsym(drm_compat_real_lib, "drmCommandWriteRead");
  real_drmCreateContext = dlsym(drm_compat_real_lib, "drmCreateContext");
  real_drmCreateDrawable = dlsym(drm_compat_real_lib, "drmCreateDrawable");
  real_drmCrtcGetSequence = dlsym(drm_compat_real_lib, "drmCrtcGetSequence");
  real_drmCrtcQueueSequence = dlsym(drm_compat_real_lib, "drmCrtcQueueSequence");
  real_drmCtlInstHandler = dlsym(drm_compat_real_lib, "drmCtlInstHandler");
  real_drmCtlUninstHandler = dlsym(drm_compat_real_lib, "drmCtlUninstHandler");
  real_drmDelContextTag = dlsym(drm_compat_real_lib, "drmDelContextTag");
  real_drmDestroyContext = dlsym(drm_compat_real_lib, "drmDestroyContext");
  real_drmDestroyDrawable = dlsym(drm_compat_real_lib, "drmDestroyDrawable");
  real_drmDevicesEqual = dlsym(drm_compat_real_lib, "drmDevicesEqual");
  real_drmDMA = dlsym(drm_compat_real_lib, "drmDMA");
  real_drmDropMaster = dlsym(drm_compat_real_lib, "drmDropMaster");
  real_drmError = dlsym(drm_compat_real_lib, "drmError");
  real_drmFinish = dlsym(drm_compat_real_lib, "drmFinish");
  real_drmFree = dlsym(drm_compat_real_lib, "drmFree");
  real_drmFreeBufs = dlsym(drm_compat_real_lib, "drmFreeBufs");
  real_drmFreeBusid = dlsym(drm_compat_real_lib, "drmFreeBusid");
  real_drmFreeDevice = dlsym(drm_compat_real_lib, "drmFreeDevice");
  real_drmFreeDevices = dlsym(drm_compat_real_lib, "drmFreeDevices");
  real_drmFreeReservedContextList = dlsym(drm_compat_real_lib, "drmFreeReservedContextList");
  real_drmFreeVersion = dlsym(drm_compat_real_lib, "drmFreeVersion");
  real_drmGetBufInfo = dlsym(drm_compat_real_lib, "drmGetBufInfo");
  real_drmGetBusid = dlsym(drm_compat_real_lib, "drmGetBusid");
  real_drmGetCap = dlsym(drm_compat_real_lib, "drmGetCap");
  real_drmGetClient = dlsym(drm_compat_real_lib, "drmGetClient");
  real_drmGetContextFlags = dlsym(drm_compat_real_lib, "drmGetContextFlags");
  real_drmGetContextPrivateMapping = dlsym(drm_compat_real_lib, "drmGetContextPrivateMapping");
  real_drmGetContextTag = dlsym(drm_compat_real_lib, "drmGetContextTag");
  real_drmGetDevice = dlsym(drm_compat_real_lib, "drmGetDevice");
  real_drmGetDevice2 = dlsym(drm_compat_real_lib, "drmGetDevice2");
  real_drmGetDeviceFromDevId = dlsym(drm_compat_real_lib, "drmGetDeviceFromDevId");
  real_drmGetDeviceNameFromFd = dlsym(drm_compat_real_lib, "drmGetDeviceNameFromFd");
  real_drmGetDeviceNameFromFd2 = dlsym(drm_compat_real_lib, "drmGetDeviceNameFromFd2");
  real_drmGetDevices = dlsym(drm_compat_real_lib, "drmGetDevices");
  real_drmGetDevices2 = dlsym(drm_compat_real_lib, "drmGetDevices2");
  real_drmGetEntry = dlsym(drm_compat_real_lib, "drmGetEntry");
  real_drmGetFormatModifierName = dlsym(drm_compat_real_lib, "drmGetFormatModifierName");
  real_drmGetFormatModifierVendor = dlsym(drm_compat_real_lib, "drmGetFormatModifierVendor");
  real_drmGetFormatName = dlsym(drm_compat_real_lib, "drmGetFormatName");
  real_drmGetHashTable = dlsym(drm_compat_real_lib, "drmGetHashTable");
  real_drmGetInterruptFromBusID = dlsym(drm_compat_real_lib, "drmGetInterruptFromBusID");
  real_drmGetLibVersion = dlsym(drm_compat_real_lib, "drmGetLibVersion");
  real_drmGetLock = dlsym(drm_compat_real_lib, "drmGetLock");
  real_drmGetMagic = dlsym(drm_compat_real_lib, "drmGetMagic");
  real_drmGetMap = dlsym(drm_compat_real_lib, "drmGetMap");
  real_drmGetNodeTypeFromDevId = dlsym(drm_compat_real_lib, "drmGetNodeTypeFromDevId");
  real_drmGetNodeTypeFromFd = dlsym(drm_compat_real_lib, "drmGetNodeTypeFromFd");
  real_drmGetPrimaryDeviceNameFromFd = dlsym(drm_compat_real_lib, "drmGetPrimaryDeviceNameFromFd");
  real_drmGetRenderDeviceNameFromFd = dlsym(drm_compat_real_lib, "drmGetRenderDeviceNameFromFd");
  real_drmGetReservedContextList = dlsym(drm_compat_real_lib, "drmGetReservedContextList");
  real_drmGetStats = dlsym(drm_compat_real_lib, "drmGetStats");
  real_drmGetVersion = dlsym(drm_compat_real_lib, "drmGetVersion");
  real_drmHandleEvent = dlsym(drm_compat_real_lib, "drmHandleEvent");
  real_drmHashCreate = dlsym(drm_compat_real_lib, "drmHashCreate");
  real_drmHashDelete = dlsym(drm_compat_real_lib, "drmHashDelete");
  real_drmHashDestroy = dlsym(drm_compat_real_lib, "drmHashDestroy");
  real_drmHashFirst = dlsym(drm_compat_real_lib, "drmHashFirst");
  real_drmHashInsert = dlsym(drm_compat_real_lib, "drmHashInsert");
  real_drmHashLookup = dlsym(drm_compat_real_lib, "drmHashLookup");
  real_drmHashNext = dlsym(drm_compat_real_lib, "drmHashNext");
  real_drmIoctl = dlsym(drm_compat_real_lib, "drmIoctl");
  real_drmIsKMS = dlsym(drm_compat_real_lib, "drmIsKMS");
  real_drmIsMaster = dlsym(drm_compat_real_lib, "drmIsMaster");
  real_drmMalloc = dlsym(drm_compat_real_lib, "drmMalloc");
  real_drmMap = dlsym(drm_compat_real_lib, "drmMap");
  real_drmMapBufs = dlsym(drm_compat_real_lib, "drmMapBufs");
  real_drmMarkBufs = dlsym(drm_compat_real_lib, "drmMarkBufs");
  real_drmModeAddFB = dlsym(drm_compat_real_lib, "drmModeAddFB");
  real_drmModeAtomicAddProperty = dlsym(drm_compat_real_lib, "drmModeAtomicAddProperty");
  real_drmModeAtomicAlloc = dlsym(drm_compat_real_lib, "drmModeAtomicAlloc");
  real_drmModeAtomicCommit = dlsym(drm_compat_real_lib, "drmModeAtomicCommit");
  real_drmModeAtomicDuplicate = dlsym(drm_compat_real_lib, "drmModeAtomicDuplicate");
  real_drmModeAtomicFree = dlsym(drm_compat_real_lib, "drmModeAtomicFree");
  real_drmModeAtomicGetCursor = dlsym(drm_compat_real_lib, "drmModeAtomicGetCursor");
  real_drmModeAtomicMerge = dlsym(drm_compat_real_lib, "drmModeAtomicMerge");
  real_drmModeAtomicSetCursor = dlsym(drm_compat_real_lib, "drmModeAtomicSetCursor");
  real_drmModeAttachMode = dlsym(drm_compat_real_lib, "drmModeAttachMode");
  real_drmModeCloseFB = dlsym(drm_compat_real_lib, "drmModeCloseFB");
  real_drmModeConnectorGetPossibleCrtcs = dlsym(drm_compat_real_lib, "drmModeConnectorGetPossibleCrtcs");
  real_drmModeConnectorSetProperty = dlsym(drm_compat_real_lib, "drmModeConnectorSetProperty");
  real_drmModeCreateDumbBuffer = dlsym(drm_compat_real_lib, "drmModeCreateDumbBuffer");
  real_drmModeCreateLease = dlsym(drm_compat_real_lib, "drmModeCreateLease");
  real_drmModeCreatePropertyBlob = dlsym(drm_compat_real_lib, "drmModeCreatePropertyBlob");
  real_drmModeCrtcGetGamma = dlsym(drm_compat_real_lib, "drmModeCrtcGetGamma");
  real_drmModeCrtcSetGamma = dlsym(drm_compat_real_lib, "drmModeCrtcSetGamma");
  real_drmModeDestroyDumbBuffer = dlsym(drm_compat_real_lib, "drmModeDestroyDumbBuffer");
  real_drmModeDestroyPropertyBlob = dlsym(drm_compat_real_lib, "drmModeDestroyPropertyBlob");
  real_drmModeDetachMode = dlsym(drm_compat_real_lib, "drmModeDetachMode");
  real_drmModeDirtyFB = dlsym(drm_compat_real_lib, "drmModeDirtyFB");
  real_drmModeFormatModifierBlobIterNext = dlsym(drm_compat_real_lib, "drmModeFormatModifierBlobIterNext");
  real_drmModeFreeConnector = dlsym(drm_compat_real_lib, "drmModeFreeConnector");
  real_drmModeFreeCrtc = dlsym(drm_compat_real_lib, "drmModeFreeCrtc");
  real_drmModeFreeEncoder = dlsym(drm_compat_real_lib, "drmModeFreeEncoder");
  real_drmModeFreeFB = dlsym(drm_compat_real_lib, "drmModeFreeFB");
  real_drmModeFreeFB2 = dlsym(drm_compat_real_lib, "drmModeFreeFB2");
  real_drmModeFreeModeInfo = dlsym(drm_compat_real_lib, "drmModeFreeModeInfo");
  real_drmModeFreeObjectProperties = dlsym(drm_compat_real_lib, "drmModeFreeObjectProperties");
  real_drmModeFreePlane = dlsym(drm_compat_real_lib, "drmModeFreePlane");
  real_drmModeFreePlaneResources = dlsym(drm_compat_real_lib, "drmModeFreePlaneResources");
  real_drmModeFreeProperty = dlsym(drm_compat_real_lib, "drmModeFreeProperty");
  real_drmModeFreePropertyBlob = dlsym(drm_compat_real_lib, "drmModeFreePropertyBlob");
  real_drmModeFreeResources = dlsym(drm_compat_real_lib, "drmModeFreeResources");
  real_drmModeGetConnector = dlsym(drm_compat_real_lib, "drmModeGetConnector");
  real_drmModeGetConnectorCurrent = dlsym(drm_compat_real_lib, "drmModeGetConnectorCurrent");
  real_drmModeGetConnectorTypeName = dlsym(drm_compat_real_lib, "drmModeGetConnectorTypeName");
  real_drmModeGetCrtc = dlsym(drm_compat_real_lib, "drmModeGetCrtc");
  real_drmModeGetEncoder = dlsym(drm_compat_real_lib, "drmModeGetEncoder");
  real_drmModeGetFB = dlsym(drm_compat_real_lib, "drmModeGetFB");
  real_drmModeGetFB2 = dlsym(drm_compat_real_lib, "drmModeGetFB2");
  real_drmModeGetLease = dlsym(drm_compat_real_lib, "drmModeGetLease");
  real_drmModeGetPlane = dlsym(drm_compat_real_lib, "drmModeGetPlane");
  real_drmModeGetPlaneResources = dlsym(drm_compat_real_lib, "drmModeGetPlaneResources");
  real_drmModeGetProperty = dlsym(drm_compat_real_lib, "drmModeGetProperty");
  real_drmModeGetPropertyBlob = dlsym(drm_compat_real_lib, "drmModeGetPropertyBlob");
  real_drmModeGetResources = dlsym(drm_compat_real_lib, "drmModeGetResources");
  real_drmModeListLessees = dlsym(drm_compat_real_lib, "drmModeListLessees");
  real_drmModeMapDumbBuffer = dlsym(drm_compat_real_lib, "drmModeMapDumbBuffer");
  real_drmModeMoveCursor = dlsym(drm_compat_real_lib, "drmModeMoveCursor");
  real_drmModeObjectGetProperties = dlsym(drm_compat_real_lib, "drmModeObjectGetProperties");
  real_drmModeObjectSetProperty = dlsym(drm_compat_real_lib, "drmModeObjectSetProperty");
  real_drmModePageFlip = dlsym(drm_compat_real_lib, "drmModePageFlip");
  real_drmModePageFlipTarget = dlsym(drm_compat_real_lib, "drmModePageFlipTarget");
  real_drmModeRevokeLease = dlsym(drm_compat_real_lib, "drmModeRevokeLease");
  real_drmModeRmFB = dlsym(drm_compat_real_lib, "drmModeRmFB");
  real_drmModeSetCrtc = dlsym(drm_compat_real_lib, "drmModeSetCrtc");
  real_drmModeSetCursor = dlsym(drm_compat_real_lib, "drmModeSetCursor");
  real_drmModeSetCursor2 = dlsym(drm_compat_real_lib, "drmModeSetCursor2");
  real_drmModeSetPlane = dlsym(drm_compat_real_lib, "drmModeSetPlane");
  real_drmMsg = dlsym(drm_compat_real_lib, "drmMsg");
  real_drmOpen = dlsym(drm_compat_real_lib, "drmOpen");
  real_drmOpenControl = dlsym(drm_compat_real_lib, "drmOpenControl");
  real_drmOpenOnce = dlsym(drm_compat_real_lib, "drmOpenOnce");
  real_drmOpenOnceWithType = dlsym(drm_compat_real_lib, "drmOpenOnceWithType");
  real_drmOpenRender = dlsym(drm_compat_real_lib, "drmOpenRender");
  real_drmOpenWithType = dlsym(drm_compat_real_lib, "drmOpenWithType");
  real_drmPrimeFDToHandle = dlsym(drm_compat_real_lib, "drmPrimeFDToHandle");
  real_drmPrimeHandleToFD = dlsym(drm_compat_real_lib, "drmPrimeHandleToFD");
  real_drmRandom = dlsym(drm_compat_real_lib, "drmRandom");
  real_drmRandomCreate = dlsym(drm_compat_real_lib, "drmRandomCreate");
  real_drmRandomDestroy = dlsym(drm_compat_real_lib, "drmRandomDestroy");
  real_drmRandomDouble = dlsym(drm_compat_real_lib, "drmRandomDouble");
  real_drmRmMap = dlsym(drm_compat_real_lib, "drmRmMap");
  real_drmScatterGatherAlloc = dlsym(drm_compat_real_lib, "drmScatterGatherAlloc");
  real_drmScatterGatherFree = dlsym(drm_compat_real_lib, "drmScatterGatherFree");
  real_drmSetBusid = dlsym(drm_compat_real_lib, "drmSetBusid");
  real_drmSetClientCap = dlsym(drm_compat_real_lib, "drmSetClientCap");
  real_drmSetContextFlags = dlsym(drm_compat_real_lib, "drmSetContextFlags");
  real_drmSetInterfaceVersion = dlsym(drm_compat_real_lib, "drmSetInterfaceVersion");
  real_drmSetMaster = dlsym(drm_compat_real_lib, "drmSetMaster");
  real_drmSetServerInfo = dlsym(drm_compat_real_lib, "drmSetServerInfo");
  real_drmSLCreate = dlsym(drm_compat_real_lib, "drmSLCreate");
  real_drmSLDelete = dlsym(drm_compat_real_lib, "drmSLDelete");
  real_drmSLDestroy = dlsym(drm_compat_real_lib, "drmSLDestroy");
  real_drmSLDump = dlsym(drm_compat_real_lib, "drmSLDump");
  real_drmSLFirst = dlsym(drm_compat_real_lib, "drmSLFirst");
  real_drmSLInsert = dlsym(drm_compat_real_lib, "drmSLInsert");
  real_drmSLLookup = dlsym(drm_compat_real_lib, "drmSLLookup");
  real_drmSLLookupNeighbors = dlsym(drm_compat_real_lib, "drmSLLookupNeighbors");
  real_drmSLNext = dlsym(drm_compat_real_lib, "drmSLNext");
  real_drmSwitchToContext = dlsym(drm_compat_real_lib, "drmSwitchToContext");
  real_drmSyncobjCreate = dlsym(drm_compat_real_lib, "drmSyncobjCreate");
  real_drmSyncobjDestroy = dlsym(drm_compat_real_lib, "drmSyncobjDestroy");
  real_drmSyncobjEventfd = dlsym(drm_compat_real_lib, "drmSyncobjEventfd");
  real_drmSyncobjExportSyncFile = dlsym(drm_compat_real_lib, "drmSyncobjExportSyncFile");
  real_drmSyncobjFDToHandle = dlsym(drm_compat_real_lib, "drmSyncobjFDToHandle");
  real_drmSyncobjHandleToFD = dlsym(drm_compat_real_lib, "drmSyncobjHandleToFD");
  real_drmSyncobjImportSyncFile = dlsym(drm_compat_real_lib, "drmSyncobjImportSyncFile");
  real_drmSyncobjQuery = dlsym(drm_compat_real_lib, "drmSyncobjQuery");
  real_drmSyncobjQuery2 = dlsym(drm_compat_real_lib, "drmSyncobjQuery2");
  real_drmSyncobjReset = dlsym(drm_compat_real_lib, "drmSyncobjReset");
  real_drmSyncobjSignal = dlsym(drm_compat_real_lib, "drmSyncobjSignal");
  real_drmSyncobjTimelineSignal = dlsym(drm_compat_real_lib, "drmSyncobjTimelineSignal");
  real_drmSyncobjTimelineWait = dlsym(drm_compat_real_lib, "drmSyncobjTimelineWait");
  real_drmSyncobjTransfer = dlsym(drm_compat_real_lib, "drmSyncobjTransfer");
  real_drmSyncobjWait = dlsym(drm_compat_real_lib, "drmSyncobjWait");
  real_drmUnlock = dlsym(drm_compat_real_lib, "drmUnlock");
  real_drmUnmap = dlsym(drm_compat_real_lib, "drmUnmap");
  real_drmUnmapBufs = dlsym(drm_compat_real_lib, "drmUnmapBufs");
  real_drmUpdateDrawableInfo = dlsym(drm_compat_real_lib, "drmUpdateDrawableInfo");
  real_drmWaitVBlank = dlsym(drm_compat_real_lib, "drmWaitVBlank");
  real_drmModeAddFB2 = dlsym(drm_compat_real_lib, "drmModeAddFB2");
  real_drmModeAddFB2WithModifiers = dlsym(drm_compat_real_lib, "drmModeAddFB2WithModifiers");
  dlog("drm-addfb-compat: loaded ioctl=%p addfb2=%p addfb2mod=%p\n", real_drmIoctl,
       (void *)real_drmModeAddFB2, (void *)real_drmModeAddFB2WithModifiers);
}

int drmModeAddFB2(int fd, uint32_t width, uint32_t height, uint32_t pixel_format,
                  const uint32_t bo_handles[4], const uint32_t pitches[4],
                  const uint32_t offsets[4], uint32_t *buf_id, uint32_t flags) {
  int r;
  uint64_t mods[4] = {0, 0, 0, 0};
  if (real_drmModeAddFB2WithModifiers) {
    r = real_drmModeAddFB2WithModifiers(fd, width, height, pixel_format, bo_handles,
                                        pitches, offsets, mods, buf_id,
                                        flags | DRM_MODE_FB_MODIFIERS);
    if (r == 0)
      return 0;
    dlog("drm-addfb-compat: AddFB2WithModifiers LINEAR failed %ux%u fmt=0x%x errno=%d\n",
         width, height, pixel_format, errno);
  }
  if (!real_drmModeAddFB2)
    return -22;
  r = real_drmModeAddFB2(fd, width, height, pixel_format, bo_handles, pitches, offsets,
                         buf_id, flags);
  if (r != 0)
    dlog("drm-addfb-compat: AddFB2 failed %ux%u fmt=0x%x errno=%d\n",
         width, height, pixel_format, errno);
  return r;
}

int drmModeAddFB2WithModifiers(int fd, uint32_t width, uint32_t height, uint32_t pixel_format,
                               const uint32_t bo_handles[4], const uint32_t pitches[4],
                               const uint32_t offsets[4], const uint64_t modifier[4],
                               uint32_t *buf_id, uint32_t flags) {
  int r;
  if (!real_drmModeAddFB2WithModifiers)
    return drmModeAddFB2(fd, width, height, pixel_format, bo_handles, pitches, offsets,
                         buf_id, flags);
  r = real_drmModeAddFB2WithModifiers(fd, width, height, pixel_format, bo_handles, pitches,
                                      offsets, modifier, buf_id, flags);
  dlog("drm-addfb-compat: AddFB2WithModifiers %ux%u fmt=0x%x flags=0x%x mod=0x%llx r=%d\n",
       width, height, pixel_format, flags,
       (unsigned long long)(modifier ? modifier[0] : 0), r);
  if (r != 0) {
    dlog("drm-addfb-compat: AddFB2WithModifiers failed errno=%d; retry LINEAR\n", errno);
    uint64_t mods[4] = {0, 0, 0, 0};
    r = real_drmModeAddFB2WithModifiers(fd, width, height, pixel_format, bo_handles, pitches,
                                        offsets, mods, buf_id, flags | DRM_MODE_FB_MODIFIERS);
    dlog("drm-addfb-compat: LINEAR retry r=%d fb=%u\n", r, buf_id ? *buf_id : 0);
  }
  if (r == 0 && buf_id && real_drmIoctl)
    auto_present(fd, *buf_id, width, height,
                 (int (*)(int, unsigned long, void *))real_drmIoctl);
  return r;
}

int drmModeSetCrtc(int fd, uint32_t crtc_id, uint32_t fb_id, uint32_t x, uint32_t y,
                   uint32_t *connectors, int count, void *mode) {
  int (*real)(int, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t *, int, void *) =
      (int (*)(int, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t *, int, void *))
          real_drmModeSetCrtc;
  int r;
  uint32_t conn = g_auto_conn;
  int blocked_blank = 0;
  if (!real) {
    errno = 38;
    return -1;
  }
  if (fb_id == 0 && g_auto_fb && g_auto_have_mode && !g_chrome_real_modeset) {
    dlog("drm-addfb-compat: block blank drmModeSetCrtc; reapply fb=%u\n", g_auto_fb);
    fb_id = g_auto_fb;
    crtc_id = g_auto_crtc ? g_auto_crtc : crtc_id;
    connectors = &conn;
    count = 1;
    mode = &g_auto_mode;
    blocked_blank = 1;
  }
  r = real(fd, crtc_id, fb_id, x, y, connectors, count, mode);
  dlog("drm-addfb-compat: SetCrtc crtc=%u fb=%u conn0=%u count=%d r=%d errno=%d\n",
       crtc_id, fb_id, (connectors && count > 0) ? connectors[0] : 0, count, r,
       r ? errno : 0);
  if (r == 0 && fb_id != 0 && !blocked_blank && fb_id != g_auto_fb)
    g_chrome_real_modeset = 1;
  return r;
}

int drmModeAtomicCommit(int fd, void *req, uint32_t flags, void *user_data) {
  int (*real)(int, void *, uint32_t, void *) =
      (int (*)(int, void *, uint32_t, void *))real_drmModeAtomicCommit;
  int r;
  if (!real) {
    errno = 38;
    return -1;
  }
  r = real(fd, req, flags, user_data);
  dlog("drm-addfb-compat: AtomicCommit flags=0x%x r=%d errno=%d\n", flags, r, r ? errno : 0);
  return r;
}

int drmModePageFlip(int fd, uint32_t crtc_id, uint32_t fb_id, uint32_t flags,
                    void *user_data) {
  int (*real)(int, uint32_t, uint32_t, uint32_t, void *) =
      (int (*)(int, uint32_t, uint32_t, uint32_t, void *))real_drmModePageFlip;
  int r;
  if (!real) {
    errno = 38;
    return -1;
  }
  r = real(fd, crtc_id, fb_id, flags, user_data);
  dlog("drm-addfb-compat: PageFlip crtc=%u fb=%u flags=0x%x r=%d errno=%d\n", crtc_id, fb_id,
       flags, r, r ? errno : 0);
  return r;
}

int drmModeSetPlane(int fd, uint32_t plane_id, uint32_t crtc_id, uint32_t fb_id,
                    uint32_t flags, int32_t crtc_x, int32_t crtc_y, uint32_t crtc_w,
                    uint32_t crtc_h, uint32_t src_x, uint32_t src_y, uint32_t src_w,
                    uint32_t src_h) {
  int (*real)(int, uint32_t, uint32_t, uint32_t, uint32_t, int32_t, int32_t, uint32_t,
              uint32_t, uint32_t, uint32_t, uint32_t, uint32_t) =
      (int (*)(int, uint32_t, uint32_t, uint32_t, uint32_t, int32_t, int32_t, uint32_t,
               uint32_t, uint32_t, uint32_t, uint32_t, uint32_t))real_drmModeSetPlane;
  int r;
  if (!real) {
    errno = 38;
    return -1;
  }
  r = real(fd, plane_id, crtc_id, fb_id, flags, crtc_x, crtc_y, crtc_w, crtc_h, src_x, src_y,
           src_w, src_h);
  dlog("drm-addfb-compat: SetPlane plane=%u crtc=%u fb=%u r=%d errno=%d\n", plane_id, crtc_id,
       fb_id, r, r ? errno : 0);
  return r;
}

int drmIoctl(int fd, unsigned long request, void *arg) {
  int (*real)(int, unsigned long, void *) = (int (*)(int, unsigned long, void *))real_drmIoctl;
  int r;
  if (!real) {
    errno = 38;
    return -1;
  }
  if (request == DRM_IOCTL_MODE_GETCONNECTOR && arg) {
    struct drm_mode_get_connector *c = arg;
    uint32_t want_conn = 0, want_crtc = 0;
    struct drm_mode_modeinfo want_mode;
    int have_tgt = (load_modeset_target(&want_conn, &want_crtc, &want_mode) == 0);
    r = real(fd, request, arg);
    if (have_tgt && (c->connector_id == want_conn ||
                     (r == 0 && c->connection != 1 && c->count_modes == 0))) {
      /* Force the probed HDMI connector to look connected with a real mode. */
      if (c->connector_id == want_conn || c->connector_id == 0)
        c->connector_id = want_conn;
      if (c->connector_id == want_conn) {
        uint32_t enc = g_tgt_encoder ? g_tgt_encoder : 126;
        c->connection = 1;
        if (c->count_modes < 1)
          c->count_modes = 1;
        if (c->modes_ptr) {
          struct drm_mode_modeinfo *dst =
              (struct drm_mode_modeinfo *)(uintptr_t)c->modes_ptr;
          dst[0] = want_mode;
        }
        /* Ozone GetCrtcs needs encoders[] + possible_crtcs; connection alone
         * is not enough — empty encoders → best_crtc=0 → display dropped. */
        if (!c->encoder_id)
          c->encoder_id = enc;
        if (c->count_encoders < 1)
          c->count_encoders = 1;
        if (c->encoders_ptr) {
          uint32_t *encs = (uint32_t *)(uintptr_t)c->encoders_ptr;
          encs[0] = enc;
        }
        dlog("drm-addfb-compat: fake GETCONNECTOR id=%u conn=1 modes=%u enc=%u "
             "encoders=%u %ux%u r=%d\n",
             c->connector_id, c->count_modes, c->encoder_id, c->count_encoders,
             want_mode.hdisplay, want_mode.vdisplay, r);
        return 0;
      }
    }
    return r;
  }
  if (request == DRM_IOCTL_MODE_GETENCODER && arg) {
    struct drm_mode_get_encoder *e = arg;
    uint32_t want_conn = 0, want_crtc = 0;
    struct drm_mode_modeinfo want_mode;
    r = real(fd, request, arg);
    if (load_modeset_target(&want_conn, &want_crtc, &want_mode) == 0 &&
        g_tgt_encoder && e->encoder_id == g_tgt_encoder) {
      e->crtc_id = want_crtc;
      dlog("drm-addfb-compat: fake GETENCODER id=%u crtc=%u\n", e->encoder_id, want_crtc);
      return 0;
    }
    return r;
  }
  if (request == DRM_IOCTL_MODE_ADDFB2 && arg) {
    struct drm_mode_fb_cmd2 *fb = arg;
    struct drm_mode_fb_cmd2 try = *fb;
    try.flags |= DRM_MODE_FB_MODIFIERS;
    r = real(fd, request, &try);
    dlog("drm-addfb-compat: ioctl ADDFB2 %ux%u fmt=0x%x flags=0x%x->0x%x h=%u r=%d errno=%d fb=%u\n",
         fb->width, fb->height, fb->pixel_format, fb->flags, try.flags, fb->handles[0], r,
         r ? errno : 0, try.fb_id);
    if (r == 0) {
      *fb = try;
      auto_present(fd, try.fb_id, try.width, try.height, real);
      return 0;
    }
  }
  if (request == DRM_IOCTL_MODE_SETCRTC && arg) {
    struct drm_mode_crtc *c = arg;
    /* Chrome blanks CRTC after stealing master; put last FB back. */
    if (c->fb_id == 0 && g_auto_fb && g_auto_have_mode && !g_chrome_real_modeset) {
      uint32_t conn = g_auto_conn;
      dlog("drm-addfb-compat: block blank SetCrtc; reapply fb=%u\n", g_auto_fb);
      c->fb_id = g_auto_fb;
      c->crtc_id = g_auto_crtc ? g_auto_crtc : c->crtc_id;
      c->set_connectors_ptr = (uint64_t)(uintptr_t)&conn;
      c->count_connectors = 1;
      c->mode = g_auto_mode;
      c->mode_valid = 1;
    }
    r = real(fd, request, arg);
    dlog("drm-addfb-compat: ioctl SETCRTC crtc=%u fb=%u r=%d errno=%d\n", c->crtc_id,
         c->fb_id, r, r ? errno : 0);
    if (r == 0 && c->fb_id != 0 && c->fb_id != g_auto_fb)
      g_chrome_real_modeset = 1;
    return r;
  }
  if (request == DRM_IOCTL_MODE_PAGE_FLIP && arg) {
    struct drm_mode_crtc_page_flip *p = arg;
    r = real(fd, request, arg);
    dlog("drm-addfb-compat: ioctl PAGE_FLIP crtc=%u fb=%u flags=0x%x r=%d errno=%d\n",
         p->crtc_id, p->fb_id, p->flags, r, r ? errno : 0);
    if (r == 0 && p->fb_id != 0)
      g_chrome_real_modeset = 1;
    return r;
  }
#ifdef DRM_IOCTL_MODE_ATOMIC
  if (request == DRM_IOCTL_MODE_ATOMIC && arg) {
    struct drm_mode_atomic *a = arg;
    r = real(fd, request, arg);
    dlog("drm-addfb-compat: ioctl ATOMIC flags=0x%x objs=%u r=%d errno=%d\n", a->flags,
         a->count_objs, r, r ? errno : 0);
    return r;
  }
#endif
  if (request == DRM_IOCTL_SET_MASTER) {
    r = real(fd, request, arg);
    dlog("drm-addfb-compat: ioctl SET_MASTER fd=%d r=%d errno=%d\n", fd, r, r ? errno : 0);
    return r;
  }
  if (request == DRM_IOCTL_DROP_MASTER) {
    r = real(fd, request, arg);
    dlog("drm-addfb-compat: ioctl DROP_MASTER fd=%d r=%d errno=%d\n", fd, r, r ? errno : 0);
    return r;
  }
  return real(fd, request, arg);
}
