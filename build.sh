#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR HÍBRIDO MESA 25 CON CIRUGÍA ATÓMICA"
echo "=========================================================="

echo "-> 1. Ordenando al Contenedor de Docker compilar el Interceptor oficial..."
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK en el Host..."
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

echo "-> 2b. Ejecutando cirugía atómica con Python en archivos DRM..."
echo " " > src/vulkan/runtime/vk_drm_syncobj.c
mkdir -p src/util
echo " " > src/util/libdrm.h

# 🟢 CIRUGÍA 1: Extirpar e inmunizar vk_instance.c contra el escáner de escritorio
python3 -c '
with open("src/vulkan/runtime/vk_instance.c", "r") as f:
    code = f.read()

start_pattern = "enumerate_drm_physical_devices_locked(struct vk_instance *instance)"
end_pattern = "enumerate_physical_devices_locked(struct vk_instance *instance)"

if start_pattern in code and end_pattern in code:
    parts_start = code.split(start_pattern)
    before_func = parts_start[0]
    rest_of_code = parts_start[1]
    
    parts_end = rest_of_code.split(end_pattern)
    after_func = parts_end[1]
    
    before_func = before_func.rsplit("static VkResult", 1)[0]
    
    code = before_func + "static VkResult\nenumerate_drm_physical_devices_locked(struct vk_instance *instance)\n{\n   return VK_SUCCESS;\n}\n\nstatic VkResult\n" + end_pattern + after_func
    print("-> Python: ¡vk_instance.c parchado con éxito!")
else:
    code = code.replace("drmDevicePtr devices;", "return VK_SUCCESS; //")
    print("-> Python: Fallback aplicado en vk_instance.c")

with open("src/vulkan/runtime/vk_instance.c", "w") as f:
    f.write(code)
'

# 🟢 CIRUGÍA 2: Neutralizar wsi_common_drm.c manteniendo firmas vivas para el Linker
python3 -c '
with open("src/vulkan/wsi/wsi_common_drm.c", "r") as f:
    code = f.read()

# Envolvemos el cuerpo completo del archivo en un macro de apagado #if 0 para Clang
patched_code = "#if 0\n" + code + "\n#endif\n"

# Le reinyectamos los cascarones vacíos reglamentarios para que el Linker no tire referencias huerfanas
stubs = """
#include <stdint.h>
#include "vk_device.h"
#include "wsi_common_private.h"

VkResult wsi_drm_configure_image(const struct wsi_swapchain *chain, const void *pCreateInfo, const void *params, void *info) { return 0; }
int wsi_prepare_signal_dma_buf_from_semaphore(struct wsi_swapchain *chain, const void *image) { return 0; }
int wsi_signal_dma_buf_from_semaphore(const struct wsi_swapchain *chain, const void *image) { return 0; }
int wsi_create_sync_for_dma_buf_wait(const struct wsi_swapchain *chain, const void *image, uint32_t req_features, void **sync_out) { return 0; }
int wsi_create_image_explicit_sync_drm(const struct wsi_swapchain *chain, void *image) { return 0; }
void wsi_destroy_image_explicit_sync_drm(const struct wsi_swapchain *chain, void *image) {}
int wsi_create_sync_for_image_syncobj(const struct wsi_swapchain *chain, const void *image, uint32_t req_features, void **sync_out) { return 0; }
_Bool wsi_common_drm_devices_equal(int fd_a, int fd_b) { return 0; }
_Bool wsi_device_matches_drm_fd(void *physicalDevice, int drm_fd) { return 0; }
_Bool wsi_drm_image_needs_buffer_blit(const void *wsi, const void *params) { return 0; }
"""

with open("src/vulkan/wsi/wsi_common_drm.c", "w") as f:
    f.write(patched_code + stubs)
print("-> Python: ¡wsi_common_drm.c neutralizado quirúrgicamente!")
'

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

# Fabricamos el .pc ficticio local purificado libre de prefijos corruptos de Google
cat << EOF > $(pwd)/shims_64/libdrm.pc
Name: libdrm
Description: Userspace interface to kernel DRM services
Version: 2.4.120
Libs: -L$(pwd)/shims_64 -lvulkan_wrapper
Cflags: -I.
EOF

echo "-> 3. Generando cross_64.txt purificado con flags limpios..."
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
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
EOF

sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 4. Compilando el driver físico de Panfrost con el Wrapper de Adrenotools..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper
meson compile -C build-64

echo "-> 5. Maquetando empaque compatible ICD plano multi-directorio..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/lib/arm-linux-androideabi
mkdir -p pkg/usr/share/vulkan/icd.d

# Colocamos los binarios finales unificados bajo las identidades correspondientes en sus subcarpetas de forma idéntica
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/arm-linux-androideabi/libvulkan_wrapper.so

patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/arm-linux-androideabi/libvulkan_wrapper.so

$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/arm-linux-androideabi/*.so 2>/dev/null || true

echo "-> [E] Escribiendo manifiestos ICD limpios..."
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 BYPASS, PURGAS COMPLETAS Y SONAMES UNIFICADOS EN VERDE"
echo "=========================================================="
