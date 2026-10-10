/* After Chrome AddFB but no SetCrtc: force legacy modeset of a given FB.
 * Usage: drm-force-scanout /dev/dri/card2 [fb_id]
 * If fb_id omitted, reads last "fb=N" from /usr/local/tmp/drm-addfb.log
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifndef DRM_IOCTL_BASE
#define DRM_IOCTL_BASE 'd'
#define DRM_IO(nr) _IO(DRM_IOCTL_BASE, nr)
#define DRM_IOWR(nr, type) _IOWR(DRM_IOCTL_BASE, nr, type)
#define DRM_IOCTL_SET_MASTER DRM_IO(0x1e)
#define DRM_IOCTL_DROP_MASTER DRM_IO(0x1f)
#endif

struct drm_mode_modeinfo {
  uint32_t clock;
  uint16_t hdisplay, hsync_start, hsync_end, htotal, hskew;
  uint16_t vdisplay, vsync_start, vsync_end, vtotal, vscan;
  uint32_t vrefresh;
  uint32_t flags;
  uint32_t type;
  char name[32];
};

struct drm_mode_card_res {
  uint64_t fb_id_ptr;
  uint64_t crtc_id_ptr;
  uint64_t connector_id_ptr;
  uint64_t encoder_id_ptr;
  uint32_t count_fbs;
  uint32_t count_crtcs;
  uint32_t count_connectors;
  uint32_t count_encoders;
  uint32_t min_width, max_width;
  uint32_t min_height, max_height;
};

struct drm_mode_get_connector {
  uint64_t encoders_ptr;
  uint64_t modes_ptr;
  uint64_t props_ptr;
  uint64_t prop_values_ptr;
  uint32_t count_modes;
  uint32_t count_props;
  uint32_t count_encoders;
  uint32_t encoder_id;
  uint32_t connector_id;
  uint32_t connector_type;
  uint32_t connector_type_id;
  uint32_t connection;
  uint32_t mm_width, mm_height;
  uint32_t subpixel;
  uint32_t pad;
};

struct drm_mode_get_encoder {
  uint32_t encoder_id;
  uint32_t encoder_type;
  uint32_t crtc_id;
  uint32_t possible_crtcs;
  uint32_t possible_clones;
};

struct drm_mode_crtc {
  uint64_t set_connectors_ptr;
  uint32_t count_connectors;
  uint32_t crtc_id;
  uint32_t fb_id;
  uint32_t x, y;
  uint32_t gamma_size;
  uint32_t mode_valid;
  struct drm_mode_modeinfo mode;
};

#define DRM_IOCTL_MODE_GETRESOURCES DRM_IOWR(0xA0, struct drm_mode_card_res)
#define DRM_IOCTL_MODE_GETCONNECTOR DRM_IOWR(0xA7, struct drm_mode_get_connector)
#define DRM_IOCTL_MODE_GETENCODER DRM_IOWR(0xA6, struct drm_mode_get_encoder)
#define DRM_IOCTL_MODE_SETCRTC DRM_IOWR(0xA2, struct drm_mode_crtc)

static uint32_t last_fb_from_log(void) {
  FILE *f = fopen("/usr/local/tmp/drm-addfb.log", "r");
  char line[512];
  uint32_t fb = 0, v;
  if (!f)
    return 0;
  while (fgets(line, sizeof(line), f)) {
    char *p = strstr(line, "fb=");
    if (p && sscanf(p, "fb=%u", &v) == 1 && v > 0)
      fb = v;
  }
  fclose(f);
  return fb;
}

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : "/dev/dri/card2";
  uint32_t fb_id = 0;
  int fd;
  struct drm_mode_card_res res;
  uint32_t conn_ids[32], crtc_ids[32], enc_ids[32];
  uint32_t i, conn_id = 0, crtc_id = 0, enc_id = 0;
  struct drm_mode_modeinfo mode;
  struct drm_mode_crtc dcrtc;

  if (argc > 2)
    fb_id = (uint32_t)strtoul(argv[2], NULL, 0);
  if (!fb_id)
    fb_id = last_fb_from_log();
  if (!fb_id) {
    printf("drm-force-scanout: no fb id (pass fb or need drm-addfb.log)\n");
    return 1;
  }

  memset(&mode, 0, sizeof(mode));
  fd = open(path, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    perror(path);
    return 1;
  }
  if (ioctl(fd, DRM_IOCTL_SET_MASTER, 0) != 0)
    printf("drm-force-scanout: SET_MASTER errno=%d (%s)\n", errno, strerror(errno));
  else
    printf("drm-force-scanout: SET_MASTER ok\n");

  memset(&res, 0, sizeof(res));
  res.count_connectors = 32;
  res.count_crtcs = 32;
  res.count_encoders = 32;
  res.connector_id_ptr = (uint64_t)(uintptr_t)conn_ids;
  res.crtc_id_ptr = (uint64_t)(uintptr_t)crtc_ids;
  res.encoder_id_ptr = (uint64_t)(uintptr_t)enc_ids;
  if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) != 0) {
    perror("GETRESOURCES");
    return 1;
  }

  /* Prefer modeset-target from drm-modeset-test (Chrome often sees 0 connectors). */
  {
    FILE *tf = fopen("/usr/local/tmp/drm-modeset-target", "r");
    char line[128];
    if (tf) {
      while (fgets(line, sizeof(line), tf)) {
        unsigned v;
        if (sscanf(line, "crtc=%u", &v) == 1)
          crtc_id = v;
        else if (sscanf(line, "connector=%u", &v) == 1)
          conn_id = v;
        else if (sscanf(line, "clock=%u", &v) == 1)
          mode.clock = v;
        else if (sscanf(line, "hdisplay=%u", &v) == 1)
          mode.hdisplay = (uint16_t)v;
        else if (sscanf(line, "hsync_start=%u", &v) == 1)
          mode.hsync_start = (uint16_t)v;
        else if (sscanf(line, "hsync_end=%u", &v) == 1)
          mode.hsync_end = (uint16_t)v;
        else if (sscanf(line, "htotal=%u", &v) == 1)
          mode.htotal = (uint16_t)v;
        else if (sscanf(line, "hskew=%u", &v) == 1)
          mode.hskew = (uint16_t)v;
        else if (sscanf(line, "vdisplay=%u", &v) == 1)
          mode.vdisplay = (uint16_t)v;
        else if (sscanf(line, "vsync_start=%u", &v) == 1)
          mode.vsync_start = (uint16_t)v;
        else if (sscanf(line, "vsync_end=%u", &v) == 1)
          mode.vsync_end = (uint16_t)v;
        else if (sscanf(line, "vtotal=%u", &v) == 1)
          mode.vtotal = (uint16_t)v;
        else if (sscanf(line, "vscan=%u", &v) == 1)
          mode.vscan = (uint16_t)v;
        else if (sscanf(line, "vrefresh=%u", &v) == 1)
          mode.vrefresh = v;
        else if (sscanf(line, "flags=%u", &v) == 1)
          mode.flags = v;
        else if (sscanf(line, "type=%u", &v) == 1)
          mode.type = v;
      }
      fclose(tf);
      if (conn_id && crtc_id && mode.hdisplay)
        printf("drm-force-scanout: using modeset-target crtc=%u conn=%u %ux%u\n",
               crtc_id, conn_id, mode.hdisplay, mode.vdisplay);
    }
  }
  if (!conn_id) {
    for (i = 0; i < res.count_connectors && i < 32; i++) {
      struct drm_mode_get_connector c;
      struct drm_mode_modeinfo modes[64];
      uint32_t encoders[8];
      memset(&c, 0, sizeof(c));
      c.connector_id = conn_ids[i];
      if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0)
        continue;
      if (c.count_modes > 64)
        c.count_modes = 64;
      if (c.count_encoders > 8)
        c.count_encoders = 8;
      c.modes_ptr = (uint64_t)(uintptr_t)modes;
      c.encoders_ptr = (uint64_t)(uintptr_t)encoders;
      if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0)
        continue;
      if (c.count_modes > 0 && c.connection != 2) {
        conn_id = c.connector_id;
        mode = modes[0];
        enc_id = c.encoder_id ? c.encoder_id : (c.count_encoders ? encoders[0] : 0);
        if (c.connection == 1)
          break;
      }
    }
  }
  if (!conn_id) {
    printf("drm-force-scanout: no connector\n");
    return 1;
  }
  if (enc_id) {
    struct drm_mode_get_encoder e;
    memset(&e, 0, sizeof(e));
    e.encoder_id = enc_id;
    if (ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0) {
      crtc_id = e.crtc_id;
      if (!crtc_id) {
        for (i = 0; i < res.count_crtcs && i < 32; i++) {
          if (e.possible_crtcs & (1u << i)) {
            crtc_id = crtc_ids[i];
            break;
          }
        }
      }
    }
  }
  if (!crtc_id && res.count_crtcs)
    crtc_id = crtc_ids[0];

  printf("drm-force-scanout: fb=%u crtc=%u connector=%u mode=%ux%u\n", fb_id, crtc_id,
         conn_id, mode.hdisplay, mode.vdisplay);
  memset(&dcrtc, 0, sizeof(dcrtc));
  dcrtc.crtc_id = crtc_id;
  dcrtc.fb_id = fb_id;
  dcrtc.set_connectors_ptr = (uint64_t)(uintptr_t)&conn_id;
  dcrtc.count_connectors = 1;
  dcrtc.mode = mode;
  dcrtc.mode_valid = 1;
  if (ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &dcrtc) != 0) {
    printf("drm-force-scanout: SetCrtc FAILED errno=%d (%s)\n", errno, strerror(errno));
    close(fd);
    return 1;
  }
  printf("drm-force-scanout: SetCrtc OK — Chrome FB should be on panel\n");
  /* Drop master so Chrome can pageflip later; leave CRTC armed with this FB. */
  ioctl(fd, DRM_IOCTL_DROP_MASTER, 0);
  close(fd);
  return 0;
}
