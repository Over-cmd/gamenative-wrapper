#!/bin/bash
set -e

echo "-> [Cirugía] Creando directorio include local..."
mkdir -p include

# 🟢 CABECERA CONTROLADORA DEFINITIVA: Fabricamos un xf86drm.h local falso impecable con TODOS los ioctls y macros que exigen pan_kmod, vk_instance, panvk y csf
cat << 'EOF' > include/xf86drm.h
#ifndef xf86drm_h
#define xf86drm_h
#include <stdint.h>

#define DRM_SYNCOBJ_CREATE_SIGNALED (1 << 0)

#ifndef DRM_NODE_PRIMARY
#define DRM_NODE_PRIMARY 0
#endif
#ifndef DRM_NODE_RENDER
#define DRM_NODE_RENDER 2
#endif
#ifndef DRM_BUS_PLATFORM
#define DRM_BUS_PLATFORM 3
#endif

struct _drmDevice {
    char **nodes;
    int available_nodes;
    int bustype;
};
typedef struct _drmDevice *drmDevicePtr;
typedef struct _drmVersion { int version_major; int version_minor; int version_patchlevel; char *name; char *date; char *desc; } *drmVersionPtr;

static inline drmVersionPtr drmGetVersion(int fd) { (void)fd; return 0; }
static inline void drmFreeVersion(drmVersionPtr v) { (void)v; }
static inline int drmCloseBufferHandle(int fd, uint32_t handle) { (void)fd; (void)handle; return 0; }
static inline int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle) { (void)fd; (void)prime_fd; (void)handle; return 0; }
static inline int drmGetDevices2(uint32_t flags, drmDevicePtr devices[], int max_devices) { (void)flags; (void)devices; (void)max_devices; return -1; }
static inline void drmFreeDevices(drmDevicePtr devices[], int count) { (void)devices; (void)count; }
static inline int drmPrimeHandleToFD(int fd, uint32_t handle, uint32_t flags, int *prime_fd) { (void)fd; (void)handle; (void)flags; if(prime_fd) *prime_fd = -1; return 0; }
static inline int drmIoctl(int fd, unsigned long request, void *arg) { (void)fd; (void)request; (void)arg; return 0; }
static inline int drmCommandWriteRead(int fd, unsigned long cmd, void *data, unsigned long size) { (void)fd; (void)cmd; (void)data; (void)size; return 0; }
static inline int drmCommandWrite(int fd, unsigned long cmd, void *data, unsigned long size) { (void)fd; (void)cmd; (void)data; (void)size; return 0; }
static inline int drmCommandRead(int fd, unsigned long cmd, void *data, unsigned long size) { (void)fd; (void)cmd; (void)data; (void)size; return 0; }

static inline int drmSyncobjDestroy(int fd, uint32_t handle) { (void)fd; (void)handle; return 0; }
static inline int drmSyncobjCreate(int fd, uint32_t flags, uint32_t *handle) { (void)fd; (void)flags; if(handle) *handle = 1; return 0; }
static inline int drmSyncobjWait(int fd, uint32_t *handles, uint32_t count, int64_t timeout_ns, uint32_t flags, uint32_t *first_signaled) { (void)fd; (void)handles; (void)count; (void)timeout_ns; (void)flags; (void)first_signaled; return 0; }

static inline int drmSyncobjTimelineWait(int fd, uint32_t *handles, uint64_t *points, uint32_t count, int64_t timeout_ns, uint32_t flags, uint32_t *first_signaled) { (void)fd; (void)handles; (void)points; (void)count; (void)timeout_ns; (void)flags; (void)first_signaled; return 0; }
static inline int drmSyncobjTransfer(int fd, uint32_t dst_handle, uint64_t dst_point, uint32_t src_handle, uint64_t src_point, uint32_t flags) { (void)fd; (void)dst_handle; (void)dst_point; (void)src_handle; (void)src_point; (void)flags; return 0; }
static inline int drmSyncobjResult(int fd, void *arg) { (void)fd; (void)arg; return 0; }
static inline int drmSyncobjReset(int fd, uint32_t *handles, uint32_t count) { (void)fd; (void)handles; (void)count; return 0; }
#endif
EOF

# 🟢 REPARACIÓN CRÍTICA ADRENOTOOLS: Inyectamos fcntl.h y unistd.h en wrapper_log.c para proveer open() y O_RDONLY en el NDK r28
echo "-> [Cirugía] Inyectando cabeceras de control de archivos en wrapper_log.c..."
python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
f=open(p,"r"); c=f.read(); f.close()
if "fcntl.h" not in c:
    c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
    f=open(p,"w"); f.write(c); f.close()
print("-> wrapper_log.c parchado")
'

# Duplicamos la cabecera en las carpetas nativas de Mesa para garantizar cobertura total de Clang
mkdir -p src/vulkan/runtime && cp -fv include/xf86drm.h src/vulkan/runtime/xf86drm.h
mkdir -p src/panfrost/lib/kmod && cp -fv include/xf86drm.h src/panfrost/lib/kmod/xf86drm.h
mkdir -p src/panfrost/vulkan/jm && cp -fv include/xf86drm.h src/panfrost/vulkan/jm/xf86drm.h
mkdir -p src/panfrost/vulkan/csf && cp -fv include/xf86drm.h src/panfrost/vulkan/csf/xf86drm.h

echo "-> [Cirugía] Prototipos biónicos locales inyectados correctamente."
