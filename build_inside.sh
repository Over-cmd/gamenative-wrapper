#!/bin/bash
set -e

BUILD_DIR="${1:-${BUILD_DIR:-build}}"
WSI_CORE="src/vulkan/wsi/wsi_common.c"
WSI_ANDR="src/vulkan/wsi/wsi_common_android.c"

git checkout HEAD -- "$WSI_CORE" "$WSI_ANDR" 2>/dev/null || true

# 🟢 PARCHE DE ANULACIÓN DE LOGS Y CACHÉ EN WSI_COMMON (v42)
if [ -f "$WSI_CORE" ]; then
    echo "-> Aplicando parches dinámicos en wsi_common.c..."
    echo '#define RTLD_NOW 2' > wsi_patch.h
    echo 'extern void* dlopen(const char*, int);' >> wsi_patch.h
    echo 'extern void* dlsym(void*, const char*);' >> wsi_patch.h
    echo 'struct AHardwareBuffer;' >> wsi_patch.h
    echo 'struct AHardwareBuffer_Desc;' >> wsi_patch.h
    echo 'int MALI_AHardwareBuffer_allocate(const struct AHardwareBuffer_Desc* d, struct AHardwareBuffer** o);' >> wsi_patch.h
    echo 'void MALI_AHardwareBuffer_release(struct AHardwareBuffer* b);' >> wsi_patch.h
    echo 'int MALI_AHardwareBuffer_sendHandleToUnixSocket(const struct AHardwareBuffer* b, int s);' >> wsi_patch.h
    echo 'int MALI_AHardwareBuffer_allocate(const struct AHardwareBuffer_Desc* d, struct AHardwareBuffer** o) {' >> wsi_patch.h
    echo '    static int (*f)(const struct AHardwareBuffer_Desc*, struct AHardwareBuffer**) = (void*)-2;' >> wsi_patch.h
    echo '    if (f == (void*)-2) { void* h = dlopen("libandroid.so", 2); if(!h) h=dlopen("libnativewindow.so", 2); f = h ? dlsym(h, "AHardwareBuffer_allocate") : 0; }' >> wsi_patch.h
    echo '    return f ? f(d, o) : -1;' >> wsi_patch.h
    echo '}' >> wsi_patch.h
    echo 'void MALI_AHardwareBuffer_release(struct AHardwareBuffer* b) {' >> wsi_patch.h
    echo '    static void (*f)(struct AHardwareBuffer*) = (void*)-2;' >> wsi_patch.h
    echo '    if (f == (void*)-2) { void* h = dlopen("libandroid.so", 2); if(!h) h=dlopen("libnativewindow.so", 2); f = h ? dlsym(h, "AHardwareBuffer_release") : 0; }' >> wsi_patch.h
    echo '    if (f) f(b);' >> wsi_patch.h
    echo '}' >> wsi_patch.h
    echo 'int MALI_AHardwareBuffer_sendHandleToUnixSocket(const struct AHardwareBuffer* b, int s) {' >> wsi_patch.h
    echo '    static int (*f)(const struct AHardwareBuffer*, int) = (void*)-2;' >> wsi_patch.h
    echo '    if (f == (void*)-2) { void* h = dlopen("libandroid.so", 2); if(!h) h=dlopen("libnativewindow.so", 2); f = h ? dlsym(h, "AHardwareBuffer_sendHandleToUnixSocket") : 0; }' >> wsi_patch.h
    echo '    return f ? f(b, s) : -1;' >> wsi_patch.h
    echo '}' >> wsi_patch.h
    
    # 🟢 HACK DE LÍNEA 70: Metemos el macro de elisión después de las cabeceras para que pise wrapper_log.h con total autoridad matemática
    cat wsi_patch.h "$WSI_CORE" > wsi_patched.c
    echo '#undef WRAPPER_LOG' >> wsi_patched.c
    echo '#define WRAPPER_LOG(level, fmt, ...) do { } while(0)' >> wsi_patched.c
    mv -f wsi_patched.c "$WSI_CORE"
    rm -f wsi_patch.h
fi

# 🟢 PARCHE DE ANULACIÓN DE LOGS EN WSI_COMMON_ANDROID
if [ -f "$WSI_ANDR" ]; then
    echo "-> Aplicando elisión local de logs en wsi_common_android.c..."
    echo '#define WRAPPER_LOG(level, fmt, ...) do { } while(0)' > andr_patch.h
    echo '#include "../wrapper/wrapper_private.h"' >> andr_patch.h
    cat andr_patch.h "$WSI_ANDR" > andr_patched.c
    mv -f andr_patched.c "$WSI_ANDR"
    rm -f andr_patch.h
fi

if [ ! -d "${BUILD_DIR}" ]; then
  meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_file.txt \
      -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled \
      -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers=panfrost \
      -Dxmlconfig=disabled -Dvulkan-drivers=panfrost,wrapper
fi
ninja -C "${BUILD_DIR}"

echo "-> Iniciando extracción y empaque de la estructura de raíz..."
python3 -c '
import os, shutil
src = "'"${BUILD_DIR}"'/src/panfrost/vulkan/libvulkan_panfrost.so"
dst = "'"${BUILD_DIR}"'/libvulkan_wrapper.so.unstripped"
if os.path.exists(src):
    shutil.copy2(src, dst)
    print("-> Binario real localizado con éxito.")
else:
    for r, d, fs in os.walk("'"${BUILD_DIR}"'"):
        if "libvulkan_panfrost.so" in fs:
            shutil.copy2(os.path.join(r, "libvulkan_panfrost.so"), dst)
            exit(0)
    exit(1)
'

NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)
STRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
if [ ! -f "$STRIP" ]; then STRIP=$(find "${NDK_DIR}" -name "llvm-strip" | head -n 1); fi
$STRIP --strip-unneeded -o "${BUILD_DIR}/libvulkan_wrapper.so" "${BUILD_DIR}/libvulkan_wrapper.so.unstripped"

ROOTFS_DIR="${BUILD_DIR}/rootfs_export"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}/usr/lib"
mkdir -p "${ROOTFS_DIR}/usr/share/vulkan/icd.d"
cp "${BUILD_DIR}/libvulkan_wrapper.so" "${ROOTFS_DIR}/usr/lib/libvulkan_wrapper.so"

cat << 'EOF' > "${ROOTFS_DIR}/usr/share/vulkan/icd.d/panfrost_icd.aarch64.json"
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/libvulkan_wrapper.so",
        "api_version": "1.3.255"
    }
}
EOF

echo "-> Forjando el paquete comprimido gamenative_driver_rootfs.tar.zst..."
cd "${ROOTFS_DIR}"
tar -cvf - usr | zstd -o "../gamenative_driver_rootfs.tar.zst"
cd - > /dev/null
cp "${BUILD_DIR}/gamenative_driver_rootfs.tar.zst" ./gamenative_driver_rootfs.tar.zst

echo "=========================================================="
echo " 🟢 FORJA BIÓNICA EXITOSA: ¡usr/lib Y JSON EMPAQUETADOS EN TAR.ZST! "
echo "=========================================================="
