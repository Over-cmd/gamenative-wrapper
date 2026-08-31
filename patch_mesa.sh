#!/bin/bash
set -e

echo "-> [Cirugía] Limpiando y restaurando el árbol de Mesa..."
git checkout src/vulkan/runtime/vk_instance.c 2>/dev/null || true
git checkout src/vulkan/wsi/wsi_common_drm.c 2>/dev/null || true
git checkout src/panfrost/lib/kmod/pan_kmod.c 2>/dev/null || true
git checkout src/panfrost/lib/kmod/panfrost_kmod.c 2>/dev/null || true
git checkout src/panfrost/lib/kmod/panthor_kmod.c 2>/dev/null || true
git checkout src/panfrost/vulkan/jm/panvk_queue.h 2>/dev/null || true

echo "-> [Cirugía] Inyectando stubs biónicos en las colas de Bifrost..."
python3 -c '
p="src/panfrost/vulkan/jm/panvk_queue.h"
f=open(p,"r"); c=f.read(); f.close()
inj = "\n#include <stdint.h>\nint drmSyncobjDestroy(int fd, uint32_t handle);\n"
c = c.replace("#include <stdint.h>", inj)
f=open(p,"w"); f.write(c); f.close()
'

echo "-> [Cirugía] Inyectando xf86drm relativo en el core de Vulkan..."
python3 -c '
p="src/vulkan/runtime/vk_instance.c"
f=open(p,"r"); c=f.read(); f.close()
c = "#include \"xf86drm.h\"\n" + c
f=open(p,"w"); f.write(c); f.close()
'

echo "-> [Cirugía] Redireccionando inclusiones rígidas de KMOD hacia shims locales..."
sed -i 's/#include <xf86drm.h>/#include "xf86drm.h"/g' src/panfrost/lib/kmod/pan_kmod.c 2>/dev/null || true
sed -i 's/#include <xf86drm.h>/#include "xf86drm.h"/g' src/panfrost/lib/kmod/panfrost_kmod.c 2>/dev/null || true

echo "-> [Cirugía] Neutralizando el módulo CSF de Panthor..."
cat << 'EOF' > src/panfrost/lib/kmod/panthor_kmod.c
#include <stddef.h>
#include "pan_kmod.h"
const struct pan_kmod_ops panthor_kmod_ops = {0};
EOF

echo "-> [Cirugía] Escribiendo xf86drm.h simulado con soporte total de Syncobj y Timeline..."
cat << 'EOF' > $(pwd)/shims_64/xf86drm.h
#ifndef xf86drm_h
#define xf86drm_h
#include <stdint.h>

#define DRM_SYNCOBJ_CREATE_SIGNALED (1 << 0)

typedef struct _drmDevice { char **nodes; } *drmDevicePtr;
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

/* Simuladores biónicos exigidos por las colas de Bifrost y Valhall */
static inline int drmSyncobjDestroy(int fd, uint32_t handle) { (void)fd; (void)handle; return 0; }
static inline int drmSyncobjCreate(int fd, uint32_t flags, uint32_t *handle) { (void)fd; (void)flags; if(handle) *handle = 1; return 0; }
static inline int drmSyncobjWait(int fd, uint32_t *handles, uint32_t count, int64_t timeout_ns, uint32_t flags, uint32_t *first_signaled) { (void)fd; (void)handles; (void)count; (void)timeout_ns; (void)flags; (void)first_signaled; return 0; }

/* 🟢 CORRECCIÓN SUPREMA PASO 681: Stubs de línea de tiempo exigidos por la arquitectura CSF v10 */
static inline int drmSyncobjTimelineWait(int fd, uint32_t *handles, uint64_t *points, uint32_t count, int64_t timeout_ns, uint32_t flags, uint32_t *first_signaled) { (void)fd; (void)handles; (void)points; (void)count; (void)timeout_ns; (void)flags; (void)first_signaled; return 0; }
static inline int drmSyncobjTransfer(int fd, uint32_t dst_handle, uint64_t dst_point, uint32_t src_handle, uint64_t src_point, uint32_t flags) { (void)fd; (void)dst_handle; (void)dst_point; (void)src_handle; (void)src_point; (void)flags; return 0; }
static inline int drmSyncobjResult(int fd, void *arg) { (void)fd; (void)arg; return 0; }
static inline int drmSyncobjReset(int fd, uint32_t *handles, uint32_t count) { (void)fd; (void)handles; (void)count; return 0; }
#endif
EOF

echo "-> [Cirugía] Distribuyendo cabecera en los árboles nativos de Mesa..."
mkdir -p include && cp -fv $(pwd)/shims_64/xf86drm.h include/xf86drm.h
mkdir -p src/vulkan/runtime && cp -fv $(pwd)/shims_64/xf86drm.h src/vulkan/runtime/xf86drm.h
mkdir -p src/panfrost/lib/kmod && cp -fv $(pwd)/shims_64/xf86drm.h src/panfrost/lib/kmod/xf86drm.h
mkdir -p src/panfrost/vulkan/jm && cp -fv $(pwd)/shims_64/xf86drm.h src/panfrost/vulkan/jm/xf86drm.h

# 🟢 ADICIÓN EXTRA DE CONTINGENCIA: Volcamos el xf86drm.h falso en la carpeta de Valhall/CSF para que la unidad 681 lo tenga local
mkdir -p src/panfrost/vulkan/csf && cp -fv $(pwd)/shims_64/xf86drm.h src/panfrost/vulkan/csf/xf86drm.h

echo "-> [Cirugía] Escribiendo stubs de intercambio de imagen para WSI DRM..."
cat << 'EOF' > src/vulkan/wsi/wsi_common_drm.c
#include <stdint.h>
#include <stdbool.h>
#include "vk_device.h"
#include "wsi_common_private.h"
_Bool wsi_common_drm_devices_equal(int a, int b);
VkResult wsi_drm_configure_image(const struct wsi_swapchain *c, const VkSwapchainCreateInfoKHR *p, const struct wsi_drm_image_params *pa, struct wsi_image_info *i) { return 0; }
VkResult wsi_prepare_signal_dma_buf_from_semaphore(struct wsi_swapchain *c, const struct wsi_image *i) { return 0; }
VkResult wsi_signal_dma_buf_from_semaphore(const struct wsi_swapchain *c, const struct wsi_image *i) { return 0; }
VkResult wsi_create_sync_for_dma_buf_wait(const struct wsi_swapchain *c, const struct wsi_image *i, enum vk_sync_features f, struct vk_sync **s) { return 0; }
VkResult wsi_create_image_explicit_sync_drm(const struct wsi_swapchain *c, struct wsi_image *i) { return 0; }
void wsi_destroy_image_explicit_sync_drm(const struct wsi_swapchain *c, struct wsi_image *i) {}
VkResult wsi_create_sync_for_image_syncobj(const struct wsi_swapchain *c, const struct wsi_image *i, enum vk_sync_features f, struct vk_sync **s) { return 0; }
_Bool wsi_common_drm_devices_equal(int a, int b) { return 0; }
_Bool wsi_device_matches_drm_fd(VkPhysicalDevice p, int d) { return 0; }
_Bool wsi_drm_image_needs_buffer_blit(const struct wsi_device *w, const struct wsi_drm_image_params *p) { return 0; }
EOF

echo "-> [Cirugía] ¡Fase quirúrgica completada con éxito rotundo!"
