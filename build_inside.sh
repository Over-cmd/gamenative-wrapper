#!/bin/bash
set -e

BUILD_DIR="${1:-${BUILD_DIR:-build}}"

# 🟢 1. MOTOR DE CONFIGURACIÓN DE MESON Y CONSTRUCCIÓN NINJA (BASADO EN v39)
if [ ! -d "${BUILD_DIR}" ]; then
  meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_file.txt \
      -Dcpp_rtti=false \
      -Dgbm=disabled \
      -Dopengl=false \
      -Dllvm=disabled \
      -Dshared-llvm=disabled \
      -Dplatforms=x11 \
      -Dgallium-drivers=panfrost \
      -Dxmlconfig=disabled \
      -Dvulkan-drivers=panfrost,wrapper
fi

ninja -C "${BUILD_DIR}"

# 🟢 2. EXTRACCIÓN ELÁSTICA DEL BINARIO DE 9.3 MB REALES
python3 -c '
import os, shutil
src = "'"${BUILD_DIR}"'/src/panfrost/vulkan/libvulkan_panfrost.so"
dst = "'"${BUILD_DIR}"'/libvulkan_wrapper.so.unstripped"

if os.path.exists(src):
    size_mb = os.path.getsize(src) / (1024 * 1024)
    shutil.copy2(src, dst)
    print(f"-> [Forja Real] ¡Silicio de Mesa 25 de {size_mb:.2f} MB extraído con éxito!")
else:
    for r, d, fs in os.walk("'"${BUILD_DIR}"'"):
        if "libvulkan_panfrost.so" in fs:
            shutil.copy2(os.path.join(r, "libvulkan_panfrost.so"), dst)
            print("-> [Forja Real - Rescate] Binario de 9.3 MB localizado de forma elástica.")
            exit(0)
    print("-> [❌ ERROR CRÍTICO] El compilador cruzado no logró forjar el driver real.")
    exit(1)
'

# 🟢 3. LIMPIEZA DE SÍMBOLOS CON LLVM-STRIP
NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)
STRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
if [ ! -f "$STRIP" ]; then
    STRIP=$(find "${NDK_DIR}" -name "llvm-strip" | head -n 1)
fi
$STRIP --strip-unneeded -o "${BUILD_DIR}/libvulkan_wrapper.so" "${BUILD_DIR}/libvulkan_wrapper.so.unstripped"

# 🟢 4. CREACIÓN DEL ÁRBOL DE DIRECTORIOS RIGIDO (usr/lib y usr/share/vulkan/icd.d)
ROOTFS_DIR="${BUILD_DIR}/rootfs_export"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}/usr/lib"
mkdir -p "${ROOTFS_DIR}/usr/share/vulkan/icd.d"

# 🟢 5. COPIAR BINARIO Y GENERAR MANIFIESTO ACTIVADOR JSON DE VULKAN
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

# 🟢 6. EMPAQUETADO COMPRIMIDO TAR.ZST MANTENIENDO LA ESTRUCTURA DE RAÍZ
echo "-> Forjando el paquete comprimido gamenative_driver_rootfs.tar.zst..."
cd "${ROOTFS_DIR}"
tar -cvf - usr | zstd -o "../gamenative_driver_rootfs.tar.zst"
cd - > /dev/null

# Copiamos el paquete al directorio raíz para que lo capture la Action
cp "${BUILD_DIR}/gamenative_driver_rootfs.tar.zst" ./gamenative_driver_rootfs.tar.zst

echo "=========================================================="
echo " 🟢 FORJA EXITOSA v43: ¡ESTRUCTURA DE RAÍZ COMPLETA Y SELLADA! "
echo "=========================================================="
