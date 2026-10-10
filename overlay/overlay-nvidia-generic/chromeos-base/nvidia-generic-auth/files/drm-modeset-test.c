/* Root probe: modeset a solid-color dumb FB on nvidia-drm.
 * Usage:
 *   drm-modeset-test [/dev/dri/card2]           # flash ~1s then tear down
 *   drm-modeset-test --keep [/dev/dri/card2]    # SetCrtc, drop master, hold FB
 *                                               # until killed (Chrome can steal)
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
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

struct drm_mode_fb_cmd {
  uint32_t fb_id;
  uint32_t width, height;
  uint32_t pitch;
  uint32_t bpp;
  uint32_t depth;
  uint32_t handle;
};

struct drm_mode_create_dumb {
  uint32_t height, width, bpp;
  uint32_t flags;
  uint32_t handle;
  uint32_t pitch;
  uint64_t size;
};

struct drm_mode_map_dumb {
  uint32_t handle;
  uint32_t pad;
  uint64_t offset;
};

struct drm_mode_destroy_dumb {
  uint32_t handle;
};

#define DRM_IOCTL_MODE_GETRESOURCES DRM_IOWR(0xA0, struct drm_mode_card_res)
#define DRM_IOCTL_MODE_GETCONNECTOR DRM_IOWR(0xA7, struct drm_mode_get_connector)
#define DRM_IOCTL_MODE_GETENCODER DRM_IOWR(0xA6, struct drm_mode_get_encoder)
#define DRM_IOCTL_MODE_SETCRTC DRM_IOWR(0xA2, struct drm_mode_crtc)
#define DRM_IOCTL_MODE_ADDFB DRM_IOWR(0xAE, struct drm_mode_fb_cmd)
#define DRM_IOCTL_MODE_RMFB DRM_IOWR(0xAF, unsigned int)
#define DRM_IOCTL_MODE_CREATE_DUMB DRM_IOWR(0xB2, struct drm_mode_create_dumb)
#define DRM_IOCTL_MODE_MAP_DUMB DRM_IOWR(0xB3, struct drm_mode_map_dumb)
#define DRM_IOCTL_MODE_DESTROY_DUMB DRM_IOWR(0xB4, struct drm_mode_destroy_dumb)

#define DRM_MODE_CONNECTED 1

static volatile sig_atomic_t g_stop;

static void on_sig(int sig) {
  (void)sig;
  g_stop = 1;
}

int main(int argc, char **argv) {
  const char *path = "/dev/dri/card2";
  int keep = 0;
  int fd;
  struct drm_mode_card_res res;
  uint32_t conn_ids[32], crtc_ids[32], enc_ids[32];
  uint32_t i;
  uint32_t conn_id = 0, crtc_id = 0, enc_id = 0;
  struct drm_mode_modeinfo mode;
  struct drm_mode_create_dumb creq;
  struct drm_mode_map_dumb mreq;
  struct drm_mode_fb_cmd fb;
  struct drm_mode_crtc dcrtc;
  void *map;
  uint32_t *px;
  uint64_t n, k;
  int argi;

  for (argi = 1; argi < argc; argi++) {
    if (strcmp(argv[argi], "--keep") == 0)
      keep = 1;
    else
      path = argv[argi];
  }

  memset(&mode, 0, sizeof(mode));
  fd = open(path, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    perror(path);
    return 1;
  }
  if (ioctl(fd, DRM_IOCTL_SET_MASTER, 0) != 0)
    printf("drm-modeset-test: SET_MASTER errno=%d (%s)\n", errno, strerror(errno));
  else
    printf("drm-modeset-test: SET_MASTER ok\n");
  fflush(stdout);

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
  printf("drm-modeset-test: crtcs=%u connectors=%u encoders=%u\n", res.count_crtcs,
         res.count_connectors, res.count_encoders);

  for (i = 0; i < res.count_connectors && i < 32; i++) {
    struct drm_mode_get_connector c;
    struct drm_mode_modeinfo modes[64];
    uint32_t encoders[8];
    memset(&c, 0, sizeof(c));
    c.connector_id = conn_ids[i];
    if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0) {
      printf("  connector id=%u GETCONNECTOR errno=%d\n", conn_ids[i], errno);
      continue;
    }
    if (c.count_modes > 64)
      c.count_modes = 64;
    if (c.count_encoders > 8)
      c.count_encoders = 8;
    memset(modes, 0, sizeof(modes));
    memset(encoders, 0, sizeof(encoders));
    c.modes_ptr = (uint64_t)(uintptr_t)modes;
    c.encoders_ptr = (uint64_t)(uintptr_t)encoders;
    c.props_ptr = 0;
    c.prop_values_ptr = 0;
    c.count_props = 0;
    if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0) {
      printf("  connector id=%u GETCONNECTOR(fill) errno=%d\n", conn_ids[i], errno);
      continue;
    }
    printf("  connector id=%u type=%u connection=%u modes=%u encoder=%u\n",
           c.connector_id, c.connector_type, c.connection, c.count_modes,
           c.encoder_id);
    fflush(stdout);
    if (!conn_id && c.count_modes > 0 && c.connection != 2) {
      conn_id = c.connector_id;
      mode = modes[0];
      enc_id = c.encoder_id ? c.encoder_id : (c.count_encoders ? encoders[0] : 0);
      if (c.connection == DRM_MODE_CONNECTED)
        break;
    }
  }
  if (!conn_id) {
    printf("drm-modeset-test: no usable connector\n");
    fflush(stdout);
    return 1;
  }
  printf("drm-modeset-test: using %ux%u connector=%u\n", mode.hdisplay, mode.vdisplay,
         conn_id);

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
  if (!crtc_id) {
    printf("drm-modeset-test: no crtc\n");
    return 1;
  }
  printf("drm-modeset-test: crtc=%u encoder=%u\n", crtc_id, enc_id);

  memset(&creq, 0, sizeof(creq));
  creq.width = mode.hdisplay;
  creq.height = mode.vdisplay;
  creq.bpp = 32;
  if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq) != 0) {
    perror("CREATE_DUMB");
    return 1;
  }
  memset(&fb, 0, sizeof(fb));
  fb.width = creq.width;
  fb.height = creq.height;
  fb.pitch = creq.pitch;
  fb.bpp = 32;
  fb.depth = 24;
  fb.handle = creq.handle;
  if (ioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb) != 0) {
    perror("ADDFB");
    return 1;
  }
  memset(&mreq, 0, sizeof(mreq));
  mreq.handle = creq.handle;
  if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq) != 0) {
    perror("MAP_DUMB");
    return 1;
  }
  map = mmap(0, creq.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mreq.offset);
  if (map == MAP_FAILED) {
    perror("mmap");
    return 1;
  }
  /* Hot pink / magenta-ish XRGB — matches what you photographed. */
  px = map;
  n = creq.size / 4;
  for (k = 0; k < n; k++)
    px[k] = 0x00ff39c6;
  printf("drm-modeset-test: dumb fb=%u\n", fb.fb_id);

  memset(&dcrtc, 0, sizeof(dcrtc));
  dcrtc.crtc_id = crtc_id;
  dcrtc.fb_id = fb.fb_id;
  dcrtc.set_connectors_ptr = (uint64_t)(uintptr_t)&conn_id;
  dcrtc.count_connectors = 1;
  dcrtc.mode = mode;
  dcrtc.mode_valid = 1;
  if (ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &dcrtc) != 0) {
    printf("drm-modeset-test: SetCrtc FAILED errno=%d (%s)\n", errno, strerror(errno));
    return 1;
  }
  printf("drm-modeset-test: SetCrtc OK color=0xff39c6 keep=%d\n", keep);
  fflush(stdout);

  /* Chrome's GETCONNECTOR often sees 0 connected; persist what worked. */
  {
    FILE *tf = fopen("/usr/local/tmp/drm-modeset-target", "w");
    if (tf) {
      fprintf(tf,
              "crtc=%u\nconnector=%u\nencoder=%u\n"
              "clock=%u\n"
              "hdisplay=%u\nhsync_start=%u\nhsync_end=%u\nhtotal=%u\nhskew=%u\n"
              "vdisplay=%u\nvsync_start=%u\nvsync_end=%u\nvtotal=%u\nvscan=%u\n"
              "vrefresh=%u\nflags=%u\ntype=%u\n",
              crtc_id, conn_id, enc_id, mode.clock, mode.hdisplay, mode.hsync_start,
              mode.hsync_end, mode.htotal, mode.hskew, mode.vdisplay,
              mode.vsync_start, mode.vsync_end, mode.vtotal, mode.vscan,
              mode.vrefresh, mode.flags, mode.type);
      fclose(tf);
      printf("drm-modeset-test: wrote /usr/local/tmp/drm-modeset-target\n");
    }
  }

  /* Release master so Chrome can claim it; keep FB alive if --keep. */
  ioctl(fd, DRM_IOCTL_DROP_MASTER, 0);

  if (keep) {
    FILE *pf = fopen("/usr/local/tmp/drm-modeset-hold.pid", "w");
    if (pf) {
      fprintf(pf, "%d\n", getpid());
      fclose(pf);
    }
    signal(SIGTERM, on_sig);
    signal(SIGINT, on_sig);
    printf("drm-modeset-test: holding FB (pid=%d); pink stays until Chrome modesets or kill\n",
           getpid());
    fflush(stdout);
    while (!g_stop)
      sleep(1);
    printf("drm-modeset-test: hold ending\n");
  } else {
    sleep(1);
  }

  munmap(map, creq.size);
  {
    unsigned int rm = fb.fb_id;
    ioctl(fd, DRM_IOCTL_MODE_RMFB, &rm);
  }
  {
    struct drm_mode_destroy_dumb dreq;
    memset(&dreq, 0, sizeof(dreq));
    dreq.handle = creq.handle;
    ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);
  }
  close(fd);
  unlink("/usr/local/tmp/drm-modeset-hold.pid");
  printf("drm-modeset-test: done\n");
  return 0;
}
