FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Herramientas base del sistema y dependencias de Python para Mesa
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build xxd && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Descargar Sysroots de Termux aislados para evitar colisiones
RUN TERMUX_REPO="https://termux.dev" && \
    PACKAGES="libdrm libandroid-shmem libxcb libx11 libxshmfence libxext libxrandr libxrender xorgproto libxau libxdmcp" && \
    \
    # --- SYSROOT 64 BITS ---
    mkdir -p /tmp/sysroot_64 && cd /tmp/sysroot_64 && \
    curl -s "${TERMUX_REPO}/dists/stable/main/binary-aarch64/Packages" > Packages && \
    for pkg in $PACKAGES; do \
        pkg_path=$(awk -v p="Package: $pkg" '$0==p{flag=1} flag && /^Filename:/{print $2; exit}' Packages) && \
        curl -L -O "${TERMUX_REPO}/${pkg_path}"; \
    done && \
    mkdir -p /termux_64 && dpkg-deb -x *.deb /termux_64 && \
    mkdir -p /data/data/com.termux/files && \
    ln -s /termux_64/data/data/com.termux/files/usr /data/data/com.termux/files/usr64 && \
    \
    # --- SYSROOT 32 BITS ---
    mkdir -p /tmp/sysroot_32 && cd /tmp/sysroot_32 && \
    curl -s "${TERMUX_REPO}/dists/stable/main/binary-arm/Packages" > Packages && \
    for pkg in $PACKAGES; do \
        pkg_path=$(awk -v p="Package: $pkg" '$0==p{flag=1} flag && /^Filename:/{print $2; exit}' Packages) && \
        curl -L -O "${TERMUX_REPO}/${pkg_path}"; \
    done && \
    mkdir -p /termux_32 && dpkg-deb -x *.deb /termux_32 && \
    ln -s /termux_32/data/data/com.termux/files/usr /data/data/com.termux/files/usr32 && \
    \
    rm -rf /tmp/sysroot_64 /tmp/sysroot_32

# 3. Configurar perfiles cruzados independientes para Meson
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    mkdir -p /root/build-config && \
    \
    # CONFIGURACIÓN: 64 Bits
    cat << EOF > /root/build-config/cross_aarch64.txt && \
[binaries]
c = '${NDK_BIN}/aarch64-linux-android30-clang'
cpp = '${NDK_BIN}/aarch64-linux-android30-clang++'
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'
pkg-config = 'pkg-config'
[constants]
termux_dir = '/termux_64/data/data/com.termux/files/usr'
[properties]
pkg_config_libdir = termux_dir + '/lib/pkgconfig:' + termux_dir + '/share/pkgconfig'
[built-in options]
c_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h']
cpp_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h']
c_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem']
cpp_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF
    \
    # CONFIGURACIÓN: 32 Bits
    cat << EOF > /root/build-config/cross_arm.txt
[binaries]
c = '${NDK_BIN}/armv7a-linux-android30-clang'
cpp = '${NDK_BIN}/armv7a-linux-android30-clang++'
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'
pkg-config = 'pkg-config'
[constants]
termux_dir = '/termux_32/data/data/com.termux/files/usr'
[properties]
pkg_config_libdir = termux_dir + '/lib/pkgconfig:' + termux_dir + '/share/pkgconfig'
[built-in options]
c_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h', '-march=armv7-a', '-mfpu=neon']
cpp_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h', '-march=armv7-a', '-mfpu=neon']
c_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem']
cpp_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem']
[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7-a'
endian = 'little'
EOF

# 4. Script de orquestación híbrido atómico (Compilación secuencial fusionada)
RUN cat << 'EOF' > /root/build.sh
#!/bin/bash
set -e

BUILD_DIR="${1:-compilacion}"
NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)
STRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

# A. PARCHE LEGADO: Modificar anon_file.c preventivamente en el código fuente
ANON_FILE=$(find src/ -name "anon_file.c" | head -n 1)
if [ -n "$ANON_FILE" ] && [ -f "$ANON_FILE" ]; then
  echo "-> Parcheando flags MFD_ALLOW_SEALING en anon_file.c..."
  sed -i 's/memfd_create(debug_name, MFD_CLOEXEC);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g' "$ANON_FILE"
fi

# ==========================================
# PASO 1: COMPILAR LA VARIANTE PURA DE 32 BITS
# ==========================================
echo "-> [1/4] Inicializando entorno dinámico para 32 BITS (ARM)..."
rm -f /data/data/com.termux/files/usr || true
ln -s /data/data/com.termux/files/usr32 /data/data/com.termux/files/usr

rm -rf build_32 || true
meson setup build_32 --cross-file /root/build-config/cross_arm.txt \
    -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled \
    -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= \
    -Dxmlconfig=disabled -Dvulkan-drivers=wrapper

meson compile -C build_32
$STRIP --strip-unneeded src/vulkan/wrapper/libvulkan_wrapper.so -o build_32/libvulkan_wrapper32.so

# Convertir el archivo .so binario de 32 bits a una matriz hexadecimal de C (.h)
echo "-> [2/4] Convirtiendo binario de 32 bits a matriz hexadecimal..."
xxd -i build_32/libvulkan_wrapper32.so > src/vulkan/wrapper/vulkan_wrapper32_payload.h

# ==========================================
# PASO 2: INYECTAR LA PASARELA HÍBRIDA EN C
# ==========================================
echo "-> [3/4] Soldando cargador de memoria virtual anon_file en wrapper_log.c..."
WRAPPER_LOG=$(find src/ -name "wrapper_log.c" | head -n 1)
sed -i 's/\r$//' "$WRAPPER_LOG"
sed -i '/__vulkan_universal_blob_bridge__/,$d' "$WRAPPER_LOG" || true

cat <<-'INNER_EOF' >> "$WRAPPER_LOG"

/* __vulkan_universal_blob_bridge__ */
#include "vulkan_wrapper32_payload.h"
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>

extern int mallopt(int param, int value);
extern int setenv(const char *name, const char *value, int overwrite);

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif
#ifndef MFD_ALLOW_SEALING
#define MFD_ALLOW_SEALING 0x0002U
#endif

// Constructor de carga atómica ultra-temprana
__attribute__((constructor)) static void load_universal_vulkan_layer(void) {
    mallopt(-1002, 0);
    setenv("MESA_VK_WSI_PRESENT_MODE", "mailbox", 1);
    setenv("vblank_mode", "0", 1);
    
    // Si la arquitectura del juego pide ejecutar bloques de 32 bits (Box86)
    if (sizeof(void*) == 4) {
        setenv("MESA_VK_WSI_QUEUE_SIZE", "1", 1);
        
        // Creamos un archivo anónimo directamente en la memoria virtual protegido (RAM)
        int fd = memfd_create("vulkan_mali_32", MFD_CLOEXEC | MFD_ALLOW_SEALING);
        if (fd >= 0) {
            // Volcamos el array hexadecimal empaquetado del driver de 32 bits
            write(fd, build_32_libvulkan_wrapper32_so, build_32_libvulkan_wrapper32_so_len);
            
            // Creamos una ruta descriptor de archivo segura en /proc/self/fd/ para engañar al sistema
            char fd_path[64];
            snprintf(fd_path, sizeof(fd_path), "/proc/self/fd/%d", fd);
            
            // Cargamos la librería en caliente directo de la RAM virtual
            void* handle32 = dlopen(fd_path, RTLD_LAZY | RTLD_GLOBAL);
            if (handle32) {
                setenv("VULKAN_WRAPPER_32_LOADED", "1", 1);
            }
        }
    }
}
INNER_EOF

# ==========================================
# PASO 3: COMPILAR LA VARIANTE MAESTRA DE 64 BITS
# ==========================================
echo "-> [4/4] Inicializando entorno dinámico para 64 BITS (AArch64)..."
rm -f /data/data/com.termux/files/usr || true
ln -s /data/data/com.termux/files/usr64 /data/data/com.termux/files/usr

rm -rf meson-private meson-logs meson-info || true
rm -rf "${BUILD_DIR}" || true

meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_aarch64.txt \
    -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled \
    -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= \
    -Dxmlconfig=disabled -Dvulkan-drivers=wrapper

meson compile -C "${BUILD_DIR}"
$STRIP --strip-unneeded "${BUILD_DIR}/src/vulkan/wrapper/libvulkan_wrapper.so" -o "${BUILD_DIR}/libvulkan_wrapper.so"

echo "-> ¡Hibridación atómica completada! Un solo archivo maestro generado en: ${BUILD_DIR}/libvulkan_wrapper.so"
EOF
RUN chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
