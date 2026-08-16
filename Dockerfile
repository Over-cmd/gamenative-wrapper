FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar solo dependencias base usando el gestor de paquetes ya configurado, evitando romper el entorno
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build xxd git pkg-config || true

# 2. Configurar perfiles cruzados independientes para Meson (64 y 32 bits)
# AGREGADO: [properties] needs_exe_wrapper = true para evitar que Meson intente ejecutar pruebas nativas invasivas
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    SYS_DIR="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot" && \
    mkdir -p /root/build-config && \
    \
    # PERFIL: 64 Bits (AArch64)
    printf "[binaries]\nc = '%s/clang'\ncpp = '%s/clang++'\nar = '%s/llvm-ar'\nstrip = '%s/llvm-strip'\npkg-config = 'pkg-config'\n[constants]\nsys_dir = '%s'\n[properties]\nneeds_exe_wrapper = true\npkg_config_libdir = sys_dir + '/usr/lib/aarch64-linux-android/pkgconfig'\n[built-in options]\nc_args = ['-target', 'aarch64-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + sys_dir + '/usr/include']\ncpp_args = ['-target', 'aarch64-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + sys_dir + '/usr/include']\nc_link_args = ['-target', 'aarch64-linux-android30', '-L' + sys_dir + '/usr/lib/aarch64-linux-android/30', '-landroid']\ncpp_link_args = ['-target', 'aarch64-linux-android30', '-L' + sys_dir + '/usr/lib/aarch64-linux-android/30', '-landroid']\n[host_machine]\nsystem = 'android'\ncpu_family = 'aarch64'\ncpu = 'armv8-a'\nendian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$SYS_DIR" > /root/build-config/cross_aarch64.txt && \
    \
    # PERFIL: 32 Bits (ARMv7)
    printf "[binaries]\nc = '%s/clang'\ncpp = '%s/clang++'\nar = '%s/llvm-ar'\nstrip = '%s/llvm-strip'\npkg-config = 'pkg-config'\n[constants]\nsys_dir = '%s'\n[properties]\nneeds_exe_wrapper = true\npkg_config_libdir = sys_dir + '/usr/lib/arm-linux-androideabi/pkgconfig'\n[built-in options]\nc_args = ['-target', 'armv7a-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-D__ANDROID__=1', '-D__arm__=1', '-D__NR_memfd_create=356', '-I' + sys_dir + '/usr/include', '-march=armv7-a', '-mfpu=neon']\ncpp_args = ['-target', 'armv7a-linux-android30', '-D__TERMUX__', '-D__USE_GNU', '-D__ANDROID__=1', '-D__arm__=1', '-D__NR_memfd_create=356', '-Wno-error=c++11-narrowing', '-I' + sys_dir + '/usr/include', '-march=armv7-a', '-mfpu=neon']\nc_link_args = ['-target', 'armv7a-linux-android30', '-L' + sys_dir + '/usr/lib/arm-linux-androideabi/30', '-landroid']\ncpp_link_args = ['-target', 'armv7a-linux-android30', '-L' + sys_dir + '/usr/lib/arm-linux-androideabi/30', '-landroid']\n[host_machine]\nsystem = 'android'\ncpu_family = 'arm'\ncpu = 'armv8-a'\nendian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$SYS_DIR" > /root/build-config/cross_arm.txt

# 3. Descargar, compilar e inyectar LIBDRM en el Sysroot del NDK de Android (Usa Meson nativo del NDK)
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    SYS_DIR="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot" && \
    git clone https://github.com/sailfishos-mirror/drm.git /tmp/libdrm && \
    \
    # Compilar libdrm de 32 bits e instalar en el sysroot correspondiente
    cd /tmp/libdrm && \
    meson setup build_32 --cross-file /root/build-config/cross_arm.txt --prefix="${SYS_DIR}/usr" --libdir="lib/arm-linux-androideabi" -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled && \
    ninja -C build_32 install && \
    \
    # Compilar libdrm de 64 bits e instalar en el sysroot correspondiente
    meson setup build_64 --cross-file /root/build-config/cross_aarch64.txt --prefix="${SYS_DIR}/usr" --libdir="lib/aarch64-linux-android" -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled && \
    ninja -C build_64 install && \
    rm -rf /tmp/libdrm

# 4. Script de orquestación híbrido unificado (Preserva HUD, inyecciones de memoria y parches de Box86)
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
printf "\\n/* __vulkan_universal_blob_bridge__ */\\n#include \\"vulkan_wrapper32_payload.h\\"\\n#include <sys/mman.h>\\n#include <unistd.h>\\n#include <fcntl.h>\\n#include <dlfcn.h>\\n#include <stdio.h>\\nextern int mallopt(int p, int v);\\nextern int setenv(const char *n, const char *v, int o);\\n__attribute__((constructor)) static void load_universal_vulkan_layer(void) {\\n mallopt(-1002, 0); setenv(\\"MESA_VK_WSI_PRESENT_MODE\\", \\"mailbox\\", 1); setenv(\\"vblank_mode\\", \\"0\\", 1);\\n if (sizeof(void*) == 4) {\\n setenv(\\"MESA_VK_WSI_QUEUE_SIZE\\", \\"1\\", 1);\\n int fd = memfd_create(\\"vulkan_mali_32\\", 0x0001U | 0x0002U);\\n if (fd >= 0) {\\n write(fd, build_32_libvulkan_wrapper32_so, build_32_libvulkan_wrapper32_so_len);\\n char fd_path[128]; sprintf(fd_path, \\"/proc/self/fd/%%d\\", fd);\\n void* h32 = dlopen(fd_path, RTLD_LAZY | RTLD_GLOBAL);\\n if (h32) setenv(\\"VULKAN_WRAPPER_32_LOADED\\", \\"1\\", 1);\\n }\\n }\\n}\\n" >> "$WRAPPER_LOG"\n\
rm -rf meson-private meson-logs meson-info "${BUILD_DIR}" || true\n\
meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_aarch64.txt -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= -Dxmlconfig=disabled -Dvulkan-drivers=wrapper -Dvalgrind=disabled\n\
meson compile -C "${BUILD_DIR}"\n\
$STRIP --strip-unneeded "${BUILD_DIR}/src/vulkan/wrapper/libvulkan_wrapper.so" -o "${BUILD_DIR}/libvulkan_wrapper.so"\n\
' > /root/build.sh && chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
