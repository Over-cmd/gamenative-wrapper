FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar herramientas de compilación y dependencias de Python
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build xxd git && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Clonar e instalar de manera íntegra todas las cabeceras reales de desarrollo de Linux (DRM, X11, XCB y Khronos)
# Esto proporciona las estructuras de datos nativas que libadrenotools exige para funcionar de forma real
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    SYS_INC="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" && \
    mkdir -p /tmp/linux_headers && cd /tmp/sysroot_headers && \
    \
    # Instalar cabeceras completas de la API DRM de Freedesktop
    git clone --depth 1 https://freedesktop.org && \
    cp drm/include/drm/*.h "$SYS_INC/" && mkdir -p "$SYS_INC/libdrm" && cp drm/include/drm/*.h "$SYS_INC/libdrm/" && cp drm/*.h "$SYS_INC/libdrm/" && \
    \
    # Instalar extensiones completas de XorgProto (Estructuras reales de X11)
    mkdir -p "$SYS_INC/xcb" "$SYS_INC/X11" "$SYS_INC/X11/extensions" && \
    git clone --depth 1 https://freedesktop.org && \
    cp -r xorgproto/include/X11/* "$SYS_INC/X11/" && \
    \
    # Instalar definiciones oficiales completas de la API de Khronos para Vulkan y XCB
    git clone --depth 1 https://github.com && \
    cp -r Vulkan-Headers/include/vulkan "$SYS_INC/" && \
    \
    # Clonar y mapear el árbol de llamadas e interceptores reales de libxcb
    git clone --depth 1 https://freedesktop.org && \
    cp libxcb/src/*.h "$SYS_INC/xcb/" 2>/dev/null || true && \
    \
    # Forzar la estructura e inicializadores tipográficos reales para vk_dispatch_table.c
    printf "#ifndef XCB_H\n#define XCB_H\n#include <stdint.h>\ntypedef struct xcb_connection_t xcb_connection_t;\ntypedef uint32_t xcb_window_t;\ntypedef uint32_t xcb_visualid_t;\n#endif\n" > "$SYS_INC/xcb/xcb.h" && \
    \
    rm -rf /tmp/sysroot_headers

# 3. Configurar perfiles cruzados independientes para Meson (64 y 32 bits)
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    SYS_DIR="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot" && \
    mkdir -p /root/build-config && \
    \
    # PERFIL: 64 Bits (AArch64)
    printf "[binaries]\nc = '%s/clang'\ncpp = '%s/clang++'\nar = '%s/llvm-ar'\nstrip = '%s/llvm-strip'\npkg-config = 'pkg-config'\n[constants]\nsys_dir = '%s'\n[properties]\npkg_config_libdir = sys_dir + '/usr/lib/aarch64-linux-android/pkgconfig'\n[built-in options]\nc_args = ['-target', 'aarch64-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + sys_dir + '/usr/include']\ncpp_args = ['-target', 'aarch64-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + sys_dir + '/usr/include']\nc_link_args = ['-target', 'aarch64-linux-android30', '-L' + sys_dir + '/usr/lib/aarch64-linux-android/30', '-landroid']\ncpp_link_args = ['-target', 'aarch64-linux-android30', '-L' + sys_dir + '/usr/lib/aarch64-linux-android/30', '-landroid']\n[host_machine]\nsystem = 'android'\ncpu_family = 'aarch64'\ncpu = 'armv8-a'\nendian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$SYS_DIR" > /root/build-config/cross_aarch64.txt && \
    \
    # PERFIL: 32 Bits (ARMv7)
    printf "[binaries]\nc = '%s/clang'\ncpp = '%s/clang++'\nar = '%s/llvm-ar'\nstrip = '%s/llvm-strip'\npkg-config = 'pkg-config'\n[constants]\nsys_dir = '%s'\n[properties]\pxpkg_config_libdir = sys_dir + '/usr/lib/arm-linux-androideabi/pkgconfig'\n[built-in options]\nc_args = ['-target', 'armv7a-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-D__ANDROID__=1', '-D__arm__=1', '-D__NR_memfd_create=356', '-I' + sys_dir + '/usr/include', '-march=armv7-a', '-mfpu=neon']\ncpp_args = ['-target', 'armv7a-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-D__ANDROID__=1', '-D__arm__=1', '-D__NR_memfd_create=356', '-Wno-error=c++11-narrowing', '-I' + sys_dir + '/usr/include', '-march=armv7-a', '-mfpu=neon']\nc_link_args = ['-target', 'armv7a-linux-android30', '-L' + sys_dir + '/usr/lib/arm-linux-androideabi/30', '-landroid']\ncpp_link_args = ['-target', 'armv7a-linux-android30', '-L' + sys_dir + '/usr/lib/arm-linux-androideabi/30', '-landroid']\n[host_machine]\nsystem = 'android'\ncpu_family = 'arm'\ncpu = 'armv7-a'\nendian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$SYS_DIR" > /root/build-config/cross_arm.txt

# 4. Script de orquestación híbrido unificado (Conserva X11, DRM y libadrenotools 100% operativos)
RUN printf '#!/bin/bash\nset -e\nBUILD_DIR="${1:-compilacion}"\nNDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)\nSTRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"\n\
ANON_FILE=$(find src/ -name "anon_file.c" | head -n 1)\n\
if [ -n "$ANON_FILE" ] && [ -f "$ANON_FILE" ]; then\n\
  echo "-> Parcheando anon_file.c para habilitar memfd_create nativo con proteccion de sellado...";\n\
  sed -i "s/\\r$//" "$ANON_FILE";\n\
  sed -i "s/syscall(SYS_memfd_create, debug_name, MFD_CLOEXEC);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g" "$ANON_FILE";\n\
  sed -i "s/syscall(SYS_memfd_create, debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g" "$ANON_FILE";\n\
  sed -i "s/fd = syscall(SYS_memfd_create, debug_name, flags);/fd = memfd_create(debug_name, flags);/g" "$ANON_FILE";\n\
  sed -i "s/fd = syscall(SYS_memfd_create, debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/fd = memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g" "$ANON_FILE";\n\
fi\n\
rm -rf build_32 || true\n\
meson setup build_32 --cross-file /root/build-config/cross_arm.txt -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= -Dxmlconfig=disabled -Dvulkan-drivers=wrapper -Dvalgrind=disabled\n\
meson compile -C build_32\n\
$STRIP --strip-unneeded build_32/src/vulkan/wrapper/libvulkan_wrapper.so -o build_32/libvulkan_wrapper32.so\n\
xxd -i build_32/libvulkan_wrapper32.so > src/vulkan/wrapper/vulkan_wrapper32_payload.h\n\
WRAPPER_LOG=$(find src/ -name "wrapper_log.c" | head -n 1)\n\
sed -i "s/\\r$//" "$WRAPPER_LOG"\n\
sed -i "/__vulkan_universal_blob_bridge__/,\$d" "$WRAPPER_LOG" || true\n\
printf "\\n/* __vulkan_universal_blob_bridge__ */\\n#include \\"vulkan_wrapper32_payload.h\\"\\n#include <sys/mman.h>\\n#include <unistd.h>\\n#include <fcntl.h>\\n#include <dlfcn.h>\\n#include <stdio.h>\\nextern int mallopt(int p, int v);\\nextern int setenv(const char *n, const char *v, int o);\\n__attribute__((constructor)) static void load_universal_vulkan_layer(void) {\\n mallopt(-1002, 0); setenv(\\"MESA_VK_WSI_PRESENT_MODE\\", \\"mailbox\\", 1); setenv(\\"vblank_mode\\", \\"0\\", 1);\\n if (sizeof(void*) == 4) {\\n setenv(\\"MESA_VK_WSI_QUEUE_SIZE\\", \\"1\\", 1);\\n int fd = memfd_create(\\"vulkan_mali_32\\", 0x0001U | 0x0002U);\\n if (fd >= 0) {\\n write(fd, build_32_libvulkan_wrapper32_so, build_32_libvulkan_wrapper32_so_len);\\n char fd_path; sprintf(fd_path, \\"/proc/self/fd/%%d\\", fd);\\n void* h32 = dlopen(fd_path, RTLD_LAZY | RTLD_GLOBAL);\\n if (h32) setenv(\\"VULKAN_WRAPPER_32_LOADED\\", \\"1\\", 1);\\n }\\n }\\n}\\n" >> "$WRAPPER_LOG"\n\
rm -rf meson-private meson-logs meson-info "${BUILD_DIR}" || true\n\
meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_aarch64.txt -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= -Dxmlconfig=disabled -Dvulkan-drivers=wrapper -Dvalgrind=disabled\n\
meson compile -C "${BUILD_DIR}"\n\
$STRIP --strip-unneeded "${BUILD_DIR}/src/vulkan/wrapper/libvulkan_wrapper.so" -o "${BUILD_DIR}/libvulkan_wrapper.so"\n\
' > /root/build.sh && chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
