/* Probe DRM + NVIDIA node access the way Ash/chronos needs it.
 * Usage: drm-chronos-probe [/dev/dri/card2]
 * Exit 0 only if open(card) + open(nvidiactl) + SET_MASTER + CREATE_DUMB succeed.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef DRM_IOCTL_BASE
#define DRM_IOCTL_BASE 'd'
#define DRM_IO(nr) _IO(DRM_IOCTL_BASE, nr)
#define DRM_IOWR(nr, type) _IOWR(DRM_IOCTL_BASE, nr, type)
#define DRM_IOCTL_SET_MASTER DRM_IO(0x1e)
#define DRM_IOCTL_DROP_MASTER DRM_IO(0x1f)
#endif

struct drm_mode_create_dumb {
  uint32_t height;
  uint32_t width;
  uint32_t bpp;
  uint32_t flags;
  uint32_t handle;
  uint32_t pitch;
  uint64_t size;
};

#ifndef DRM_IOCTL_MODE_CREATE_DUMB
#define DRM_IOCTL_MODE_CREATE_DUMB DRM_IOWR(0xB2, struct drm_mode_create_dumb)
#endif
#ifndef DRM_IOCTL_MODE_DESTROY_DUMB
struct drm_mode_destroy_dumb {
  uint32_t handle;
};
#define DRM_IOCTL_MODE_DESTROY_DUMB DRM_IOWR(0xB4, struct drm_mode_destroy_dumb)
#endif

static void show(const char *path) {
  struct stat st;
  if (stat(path, &st) != 0)
    printf("drm-chronos-probe: stat %s: %s\n", path, strerror(errno));
  else
    printf("drm-chronos-probe: %s mode=%04o uid=%u gid=%u\n", path,
           (unsigned)(st.st_mode & 07777), (unsigned)st.st_uid,
           (unsigned)st.st_gid);
}

int main(int argc, char **argv) {
  const char *card = argc > 1 ? argv[1] : "/dev/dri/card2";
  int fail = 0;

  printf("drm-chronos-probe: uid=%d euid=%d gid=%d\n", (int)getuid(),
         (int)geteuid(), (int)getgid());
  show(card);
  show("/dev/nvidiactl");
  show("/dev/nvidia0");
  show("/dev/nvidia-modeset");

  for (const char **p = (const char *[]){"/dev/nvidiactl", "/dev/nvidia0",
                                         "/dev/nvidia-modeset", NULL};
       *p; p++) {
    int nfd = open(*p, O_RDWR | O_CLOEXEC);
    if (nfd < 0) {
      printf("drm-chronos-probe: open %s FAIL errno=%d (%s)\n", *p, errno,
             strerror(errno));
      fail = 1;
    } else {
      printf("drm-chronos-probe: open %s ok fd=%d\n", *p, nfd);
      close(nfd);
    }
  }

  int fd = open(card, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    printf("drm-chronos-probe: open %s FAIL errno=%d (%s)\n", card, errno,
           strerror(errno));
    return 2;
  }
  printf("drm-chronos-probe: open %s ok fd=%d\n", card, fd);

  if (ioctl(fd, DRM_IOCTL_SET_MASTER, 0) != 0) {
    printf("drm-chronos-probe: SET_MASTER FAIL errno=%d (%s)\n", errno,
           strerror(errno));
    fail = 1;
  } else {
    printf("drm-chronos-probe: SET_MASTER ok\n");
  }

  struct drm_mode_create_dumb creq;
  memset(&creq, 0, sizeof(creq));
  creq.width = 64;
  creq.height = 64;
  creq.bpp = 32;
  if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq) != 0) {
    printf("drm-chronos-probe: CREATE_DUMB FAIL errno=%d (%s)\n", errno,
           strerror(errno));
    fail = 1;
  } else {
    printf("drm-chronos-probe: CREATE_DUMB ok handle=%u size=%llu\n",
           creq.handle, (unsigned long long)creq.size);
    struct drm_mode_destroy_dumb dreq;
    memset(&dreq, 0, sizeof(dreq));
    dreq.handle = creq.handle;
    ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);
  }

  ioctl(fd, DRM_IOCTL_DROP_MASTER, 0);
  close(fd);
  printf("drm-chronos-probe: %s\n", fail ? "FAIL" : "PASS");
  return fail ? 1 : 0;
}
