#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR HÍBRIDO MESA 25 CON EXPANSIÓN DE STUBS"
echo "=========================================================="

echo "-> 1. Compilando el Interceptor oficial en Docker..."
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Micro-fuente C de trazas y funciones biónicas que ld.lld exige resolver
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
int wsi_get_android_blit_type(void* a, void* b) { (void)a; (void)b; return 0; }
int wsi_configure_android_image(void* a, void* b) { (void)a; (void)b; return 0; }
EOF

mkdir -p "$(pwd)/shims_64"
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_64.o
$NDK_BIN/llvm-ar rcs "$(pwd)/shims_64/libvulkan_wrapper.a" stub_logs_64.o

echo "-> 2b. Neutralizando dependencias DRM residuales mediante stubs simulados..."
echo " " > src/vulkan/runtime/vk_drm_syncobj.c
mkdir -p src/util && echo " " > src/util/libdrm.h

# 🟢 CABECERA BLINDADA: Agregamos drmPrimeHandleToFD y flags de control nativos para pan_kmod
cat << 'EOF' > $(pwd)/shims_64/xf86drm.h
#ifndef xf86drm_h
#define xf86drm_h
#include <stdint.h>

#define DRM_CLOEXEC 0x140000

typedef struct _drmDevice { char **nodes; } *drmDevicePtr;
typedef struct _drmVersion { int version_major; int version_minor; int version_patchlevel; char *name; char *date; char *desc; } *drmVersionPtr;

static inline drmVersionPtr drmGetVersion(int fd) { (void)fd; return 0; }
static inline void drmFreeVersion(drmVersionPtr v) { (void)v; }
static inline int drmCloseBufferHandle(int fd, uint32_t handle) { (void)fd; (void)handle; return 0; }
static inline int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle) { (void)fd; (void)prime_fd; (void)handle; return 0; }
static inline int drmGetDevices2(uint32_t flags, drmDevicePtr devices[], int max_devices) { (void)flags; (void)devices; (void)max_devices; return -1; }
static inline void drmFreeDevices(drmDevicePtr devices[], int count) { (void)devices; (void)count; }

/* 🟢 CORRECCIÓN SUPREMA: Inyectamos la firma e implementación que exige pan_kmod.h */
static inline int drmPrimeHandleToFD(int fd, uint32_t handle, uint32_t flags, int *prime_fd) { (void)fd; (void)handle; (void)flags; if(prime_fd) *prime_fd = -1; return 0; }
#endif
EOF

mkdir -p include && cp -fv $(pwd)/shims_64/xf86drm.h include/xf86drm.h
mkdir -p src/panfrost/lib/kmod && cp -fv $(pwd)/shims_64/xf86drm.h src/panfrost/lib/kmod/xf86drm.h

# STUBS DE WSI DRM COMPLETOS
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

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

cat << EOF > $(pwd)/shims_64/libdrm.pc
Name: libdrm
Description: Userspace interface to kernel DRM services
Version: 2.4.120
Libs: -L$(pwd)/shims_64 -lvulkan_wrapper
Cflags: -I$(pwd)/shims_64 -I$(pwd)/include
EOF

echo "-> 3. Generando cross_64.txt..."
cat << EOF > cross_64.txt
[constants]
ndk_path = '${ANDROID_NDK_HOME}'
toolchain = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/bin'
api = '26'

[binaries]
c       = toolchain + '/aarch64-linux-android' + api + '-clang'
cpp     = toolchain + '/aarch64-linux-android' + api + '-clang++'
ar      = toolchain + '/llvm-ar'
strip   = toolchain + '/llvm-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true
sys_root = '${NDK_SYSROOT}'
libdir = '${NDK_SYSROOT_LIB_64}'
pkg_config_path = '$(pwd)/shims_64'
pkg_config_libdir = '$(pwd)/shims_64'

[built-in options]
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I$(pwd)/shims_64', '-include', 'xf86drm.h']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I$(pwd)/shims_64', '-include', 'xf86drm.h']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
EOF

sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 4. Compilando Panfrost con el Wrapper de Adrenotools..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper
meson compile -C build-64

echo "-> 5. Maquetando empaque multi-directorio..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android pkg/usr/lib/arm-linux-androideabi pkg/usr/share/vulkan/icd.d

cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/arm-linux-androideabi/libvulkan_wrapper.so

patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/arm-linux-androideabi/libvulkan_wrapper.so

$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/arm-linux-androideabi/*.so 2>/dev/null || true

echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡FAT PACK INTEGRAL COMPLETADO EN VERDE COMPLETO!"
echo "=========================================================="
