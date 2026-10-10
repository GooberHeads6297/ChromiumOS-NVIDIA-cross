/* libgbm.so.1 stand-in: Mesa GBM + NVIDIA allocator for renderable scanout.
 *
 * Dumb BOs SetCrtc OK but GL FBO incomplete (0x8CD6) — NVIDIA cannot render
 * into kernel dumb memory. NVIDIA allocator BOs are GPU-renderable; pair with
 * NVIDIA-first EGL so eglCreateImage works (Mesa returned 0x3003/0x3009).
 *
 * Real Mesa frontend: libgbm-mesa.so.1 beside this file.
 * GBM_BACKENDS_PATH must contain nvidia-drm_gbm.so.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct gbm_device;
struct gbm_bo;
struct gbm_surface;

#define LOAD()                                                                 \
  do {                                                                         \
    if (!real_gbm_create_device)                                               \
      load_mesa();                                                             \
  } while (0)

static void *mesa;

static struct gbm_device *(*real_gbm_create_device)(int);
static void (*real_gbm_device_destroy)(struct gbm_device *);
static int (*real_gbm_device_get_fd)(struct gbm_device *);
static const char *(*real_gbm_device_get_backend_name)(struct gbm_device *);
static int (*real_gbm_device_is_format_supported)(struct gbm_device *, uint32_t,
                                                  uint32_t);
static int (*real_gbm_device_get_format_modifier_plane_count)(struct gbm_device *,
                                                              uint32_t, uint64_t);
static struct gbm_bo *(*real_gbm_bo_create)(struct gbm_device *, uint32_t,
                                            uint32_t, uint32_t, uint32_t);
static struct gbm_bo *(*real_gbm_bo_create_with_modifiers)(struct gbm_device *,
                                                           uint32_t, uint32_t,
                                                           uint32_t,
                                                           const uint64_t *,
                                                           unsigned int);
static struct gbm_bo *(*real_gbm_bo_create_with_modifiers2)(struct gbm_device *,
                                                            uint32_t, uint32_t,
                                                            uint32_t,
                                                            const uint64_t *,
                                                            unsigned int,
                                                            uint32_t);
static struct gbm_bo *(*real_gbm_bo_import)(struct gbm_device *, uint32_t, void *,
                                            uint32_t);
static void (*real_gbm_bo_destroy)(struct gbm_bo *);
static uint32_t (*real_gbm_bo_get_width)(struct gbm_bo *);
static uint32_t (*real_gbm_bo_get_height)(struct gbm_bo *);
static uint32_t (*real_gbm_bo_get_stride)(struct gbm_bo *);
static uint32_t (*real_gbm_bo_get_stride_for_plane)(struct gbm_bo *, int);
static uint32_t (*real_gbm_bo_get_format)(struct gbm_bo *);
static uint32_t (*real_gbm_bo_get_bpp)(struct gbm_bo *);
static uint32_t (*real_gbm_bo_get_offset)(struct gbm_bo *, int);
static uint32_t (*real_gbm_bo_get_plane_count)(struct gbm_bo *);
static int (*real_gbm_bo_get_fd)(struct gbm_bo *);
static int (*real_gbm_bo_get_fd_for_plane)(struct gbm_bo *, int);
static uint64_t (*real_gbm_bo_get_modifier)(struct gbm_bo *);
typedef union gbm_bo_handle {
  void *ptr;
  int32_t s32;
  uint32_t u32;
  int64_t s64;
  uint64_t u64;
} gbm_bo_handle;
static gbm_bo_handle (*real_gbm_bo_get_handle)(struct gbm_bo *);
static gbm_bo_handle (*real_gbm_bo_get_handle_for_plane)(struct gbm_bo *, int);
static struct gbm_device *(*real_gbm_bo_get_device)(struct gbm_bo *);
static void (*real_gbm_bo_set_user_data)(struct gbm_bo *, void *,
                                         void (*)(struct gbm_bo *, void *));
static void *(*real_gbm_bo_get_user_data)(struct gbm_bo *);
static void *(*real_gbm_bo_map)(struct gbm_bo *, uint32_t, uint32_t, uint32_t,
                                uint32_t, uint32_t, uint32_t *, void **);
static void (*real_gbm_bo_unmap)(struct gbm_bo *, void *);
static int (*real_gbm_bo_write)(struct gbm_bo *, const void *, size_t);
static struct gbm_surface *(*real_gbm_surface_create)(struct gbm_device *,
                                                      uint32_t, uint32_t,
                                                      uint32_t, uint32_t);
static void (*real_gbm_surface_destroy)(struct gbm_surface *);
static struct gbm_bo *(*real_gbm_surface_lock_front_buffer)(struct gbm_surface *);
static void (*real_gbm_surface_release_buffer)(struct gbm_surface *,
                                               struct gbm_bo *);
static int (*real_gbm_surface_has_free_buffers)(struct gbm_surface *);

#define GBM_BO_USE_SCANOUT (1u << 0)
#define GBM_BO_USE_RENDERING (1u << 2)
#define GBM_BO_USE_LINEAR (1u << 4)
#define GBM_BO_USE_PROTECTED (1u << 5)

static void glog(const char *fmt, ...) {
  FILE *fp = fopen("/usr/local/tmp/gbm-compat.log", "a");
  va_list ap;
  va_start(ap, fmt);
  if (fp) {
    vfprintf(fp, fmt, ap);
    fclose(fp);
  }
  va_end(ap);
}

static void load_mesa(void) {
  const char *path = getenv("MESA_GBM_LIB");
  if (!path)
    path = "/usr/local/lib64/libgbm-mesa.so.1";
  mesa = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!mesa) {
    fprintf(stderr, "gbm-minigbm-compat: dlopen %s: %s\n", path, dlerror());
    return;
  }
#define S(name) real_##name = dlsym(mesa, #name)
  S(gbm_create_device);
  S(gbm_device_destroy);
  S(gbm_device_get_fd);
  S(gbm_device_get_backend_name);
  S(gbm_device_is_format_supported);
  S(gbm_device_get_format_modifier_plane_count);
  S(gbm_bo_create);
  S(gbm_bo_create_with_modifiers);
  S(gbm_bo_create_with_modifiers2);
  S(gbm_bo_import);
  S(gbm_bo_destroy);
  S(gbm_bo_get_width);
  S(gbm_bo_get_height);
  S(gbm_bo_get_stride);
  S(gbm_bo_get_stride_for_plane);
  S(gbm_bo_get_format);
  S(gbm_bo_get_bpp);
  S(gbm_bo_get_offset);
  S(gbm_bo_get_plane_count);
  S(gbm_bo_get_fd);
  S(gbm_bo_get_fd_for_plane);
  S(gbm_bo_get_modifier);
  S(gbm_bo_get_handle);
  S(gbm_bo_get_handle_for_plane);
  S(gbm_bo_get_device);
  S(gbm_bo_set_user_data);
  S(gbm_bo_get_user_data);
  S(gbm_bo_map);
  S(gbm_bo_unmap);
  S(gbm_bo_write);
  S(gbm_surface_create);
  S(gbm_surface_destroy);
  S(gbm_surface_lock_front_buffer);
  S(gbm_surface_release_buffer);
  S(gbm_surface_has_free_buffers);
#undef S
}

struct gbm_device *gbm_create_device(int fd) {
  LOAD();
  const char *prev = getenv("GBM_BACKEND");
  char *saved = prev ? strdup(prev) : NULL;
  /* Prefer nvidia-drm when creating on an unknown fd after fallback. */
  setenv("GBM_BACKEND", "nvidia-drm", 1);
  struct gbm_device *d = real_gbm_create_device ? real_gbm_create_device(fd) : NULL;
  if (!d) {
    unsetenv("GBM_BACKEND");
    d = real_gbm_create_device ? real_gbm_create_device(fd) : NULL;
  }
  if (!d) {
    static const char *fallbacks[] = {"/dev/dri/renderD129", "/dev/dri/card2",
                                      NULL};
    for (int i = 0; fallbacks[i]; i++) {
      int nfd = open(fallbacks[i], O_RDWR | O_CLOEXEC);
      if (nfd < 0)
        continue;
      setenv("GBM_BACKEND", "nvidia-drm", 1);
      d = real_gbm_create_device ? real_gbm_create_device(nfd) : NULL;
      if (d) {
        glog("gbm-minigbm-compat: gbm_create_device fd=%d -> fallback %s\n", fd,
             fallbacks[i]);
        break;
      }
      close(nfd);
    }
  }
  if (saved) {
    setenv("GBM_BACKEND", saved, 1);
    free(saved);
  } else {
    unsetenv("GBM_BACKEND");
  }
  glog("gbm-minigbm-compat: gbm_create_device fd=%d -> %p\n", fd, (void *)d);
  return d;
}

void gbm_device_destroy(struct gbm_device *d) {
  LOAD();
  if (real_gbm_device_destroy)
    real_gbm_device_destroy(d);
}
int gbm_device_get_fd(struct gbm_device *d) {
  LOAD();
  return real_gbm_device_get_fd ? real_gbm_device_get_fd(d) : -1;
}
const char *gbm_device_get_backend_name(struct gbm_device *d) {
  LOAD();
  return real_gbm_device_get_backend_name ? real_gbm_device_get_backend_name(d)
                                          : "nvidia-drm";
}
int gbm_device_is_format_supported(struct gbm_device *d, uint32_t f, uint32_t u) {
  LOAD();
  return real_gbm_device_is_format_supported
             ? real_gbm_device_is_format_supported(d, f, u)
             : 0;
}
int gbm_device_get_format_modifier_plane_count(struct gbm_device *d, uint32_t f,
                                               uint64_t m) {
  LOAD();
  return real_gbm_device_get_format_modifier_plane_count
             ? real_gbm_device_get_format_modifier_plane_count(d, f, m)
             : 1;
}

static void log_fail(const char *what, uint32_t w, uint32_t h, uint32_t f,
                     uint32_t u) {
  glog("gbm-minigbm-compat: %s failed %ux%u fmt=0x%x use=0x%x\n", what, w, h, f,
       u);
}

struct gbm_bo *gbm_bo_create(struct gbm_device *d, uint32_t w, uint32_t h,
                             uint32_t f, uint32_t u) {
  LOAD();
  if (!real_gbm_bo_create)
    return NULL;
  /* Strip PROTECTED (login FB). Prefer SCANOUT|RENDERING so NVIDIA GL can
   * complete an FBO (dumb → 0x8CD6). Do not force LINEAR — that broke SetCrtc. */
  uint32_t base = u & ~GBM_BO_USE_PROTECTED;
  uint32_t tries[] = {
      base | GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT,
      GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT,
      base | GBM_BO_USE_SCANOUT,
      base | GBM_BO_USE_LINEAR | GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT,
      base,
  };
  for (unsigned i = 0; i < sizeof(tries) / sizeof(tries[0]); i++) {
    struct gbm_bo *bo = real_gbm_bo_create(d, w, h, f, tries[i]);
    if (bo) {
      glog("gbm-minigbm-compat: nvidia-bo ok %ux%u fmt=0x%x use=0x%x try=0x%x\n",
           w, h, f, u, tries[i]);
      return bo;
    }
  }
  log_fail("gbm_bo_create", w, h, f, u);
  return NULL;
}

struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *d, uint32_t w,
                                            uint32_t h, uint32_t f,
                                            const uint64_t *m, unsigned int n) {
  LOAD();
  struct gbm_bo *bo = NULL;
  if (real_gbm_bo_create_with_modifiers && m && n)
    bo = real_gbm_bo_create_with_modifiers(d, w, h, f, m, n);
  if (!bo)
    bo = gbm_bo_create(d, w, h, f,
                       GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT);
  if (!bo)
    log_fail("gbm_bo_create_with_modifiers", w, h, f, 0);
  else
    glog("gbm-minigbm-compat: nvidia-bo+mod ok %ux%u fmt=0x%x\n", w, h, f);
  return bo;
}

struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *d, uint32_t w,
                                             uint32_t h, uint32_t f,
                                             const uint64_t *m, unsigned int n,
                                             uint32_t u) {
  LOAD();
  struct gbm_bo *bo = NULL;
  uint32_t u2 = (u & ~GBM_BO_USE_PROTECTED) | GBM_BO_USE_RENDERING |
                GBM_BO_USE_SCANOUT;
  if (real_gbm_bo_create_with_modifiers2 && m && n)
    bo = real_gbm_bo_create_with_modifiers2(d, w, h, f, m, n, u2);
  if (!bo)
    bo = gbm_bo_create(d, w, h, f, u2);
  if (!bo)
    log_fail("gbm_bo_create_with_modifiers2", w, h, f, u);
  else
    glog("gbm-minigbm-compat: nvidia-bo+mod2 ok %ux%u fmt=0x%x use=0x%x\n", w, h,
         f, u);
  return bo;
}

struct gbm_bo *gbm_bo_import(struct gbm_device *d, uint32_t t, void *b,
                             uint32_t u) {
  LOAD();
  return real_gbm_bo_import ? real_gbm_bo_import(d, t, b, u) : NULL;
}
void gbm_bo_destroy(struct gbm_bo *bo) {
  LOAD();
  if (real_gbm_bo_destroy)
    real_gbm_bo_destroy(bo);
}
uint32_t gbm_bo_get_width(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_width ? real_gbm_bo_get_width(bo) : 0;
}
uint32_t gbm_bo_get_height(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_height ? real_gbm_bo_get_height(bo) : 0;
}
uint32_t gbm_bo_get_stride(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_stride ? real_gbm_bo_get_stride(bo) : 0;
}
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int p) {
  LOAD();
  return real_gbm_bo_get_stride_for_plane ? real_gbm_bo_get_stride_for_plane(bo, p)
                                          : 0;
}
uint32_t gbm_bo_get_format(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_format ? real_gbm_bo_get_format(bo) : 0;
}
uint32_t gbm_bo_get_bpp(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_bpp ? real_gbm_bo_get_bpp(bo) : 0;
}
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int p) {
  LOAD();
  return real_gbm_bo_get_offset ? real_gbm_bo_get_offset(bo, p) : 0;
}
uint32_t gbm_bo_get_plane_count(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_plane_count ? real_gbm_bo_get_plane_count(bo) : 1;
}
int gbm_bo_get_fd(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_fd ? real_gbm_bo_get_fd(bo) : -1;
}
int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int p) {
  LOAD();
  return real_gbm_bo_get_fd_for_plane ? real_gbm_bo_get_fd_for_plane(bo, p) : -1;
}
int gbm_bo_get_plane_fd(struct gbm_bo *bo, size_t p) {
  return gbm_bo_get_fd_for_plane(bo, (int)p);
}
uint32_t gbm_bo_get_plane_size(struct gbm_bo *bo, size_t p) {
  uint32_t stride = gbm_bo_get_stride_for_plane(bo, (int)p);
  uint32_t height = gbm_bo_get_height(bo);
  if (p > 0)
    height = (height + 1) / 2;
  return stride * height;
}
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_modifier ? real_gbm_bo_get_modifier(bo) : 0;
}
gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo) {
  gbm_bo_handle z = {0};
  LOAD();
  return real_gbm_bo_get_handle ? real_gbm_bo_get_handle(bo) : z;
}
gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int p) {
  gbm_bo_handle z = {0};
  LOAD();
  return real_gbm_bo_get_handle_for_plane ? real_gbm_bo_get_handle_for_plane(bo, p)
                                          : z;
}
struct gbm_device *gbm_bo_get_device(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_device ? real_gbm_bo_get_device(bo) : NULL;
}
void gbm_bo_set_user_data(struct gbm_bo *bo, void *data,
                          void (*destroy)(struct gbm_bo *, void *)) {
  LOAD();
  if (real_gbm_bo_set_user_data)
    real_gbm_bo_set_user_data(bo, data, destroy);
}
void *gbm_bo_get_user_data(struct gbm_bo *bo) {
  LOAD();
  return real_gbm_bo_get_user_data ? real_gbm_bo_get_user_data(bo) : NULL;
}
void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t w, uint32_t h,
                 uint32_t flags, uint32_t *stride, void **map_data) {
  LOAD();
  return real_gbm_bo_map ? real_gbm_bo_map(bo, x, y, w, h, flags, stride, map_data)
                         : NULL;
}
void gbm_bo_unmap(struct gbm_bo *bo, void *map_data) {
  LOAD();
  if (real_gbm_bo_unmap)
    real_gbm_bo_unmap(bo, map_data);
}
int gbm_bo_write(struct gbm_bo *bo, const void *buf, size_t count) {
  LOAD();
  return real_gbm_bo_write ? real_gbm_bo_write(bo, buf, count) : -1;
}
struct gbm_surface *gbm_surface_create(struct gbm_device *d, uint32_t w, uint32_t h,
                                       uint32_t f, uint32_t u) {
  LOAD();
  return real_gbm_surface_create ? real_gbm_surface_create(d, w, h, f, u) : NULL;
}
void gbm_surface_destroy(struct gbm_surface *s) {
  LOAD();
  if (real_gbm_surface_destroy)
    real_gbm_surface_destroy(s);
}
struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *s) {
  LOAD();
  return real_gbm_surface_lock_front_buffer ? real_gbm_surface_lock_front_buffer(s)
                                            : NULL;
}
void gbm_surface_release_buffer(struct gbm_surface *s, struct gbm_bo *bo) {
  LOAD();
  if (real_gbm_surface_release_buffer)
    real_gbm_surface_release_buffer(s, bo);
}
int gbm_surface_has_free_buffers(struct gbm_surface *s) {
  LOAD();
  return real_gbm_surface_has_free_buffers ? real_gbm_surface_has_free_buffers(s)
                                           : 0;
}
