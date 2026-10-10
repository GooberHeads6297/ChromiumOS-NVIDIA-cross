/* Root helper: try SET_MASTER / DROP_MASTER on nvidia card.
 * Usage: drm-take-master /dev/dri/card2
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

/* From drm.h — no libdrm headers required on the build host. */
#ifndef DRM_IOCTL_SET_MASTER
#define DRM_IOCTL_BASE 'd'
#define DRM_IO(nr) _IO(DRM_IOCTL_BASE, nr)
#define DRM_IOCTL_SET_MASTER DRM_IO(0x1e)
#define DRM_IOCTL_DROP_MASTER DRM_IO(0x1f)
#endif

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : "/dev/dri/card2";
  int fd = open(path, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    perror(path);
    return 1;
  }
  printf("drm-take-master: opened %s fd=%d\n", path, fd);
  if (ioctl(fd, DRM_IOCTL_DROP_MASTER, 0) != 0)
    printf("drm-take-master: DROP_MASTER errno=%d (%s)\n", errno, strerror(errno));
  else
    printf("drm-take-master: DROP_MASTER ok\n");
  if (ioctl(fd, DRM_IOCTL_SET_MASTER, 0) != 0)
    printf("drm-take-master: SET_MASTER errno=%d (%s)\n", errno, strerror(errno));
  else
    printf("drm-take-master: SET_MASTER ok\n");
  /* Release so Chrome can become master. */
  ioctl(fd, DRM_IOCTL_DROP_MASTER, 0);
  close(fd);
  printf("drm-take-master: released\n");
  return 0;
}
