FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar herramientas base y dependencias de Python
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build xxd && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Descargar e instalar Sysroots aislados de Termux (32 y 64 bits) usando el espejo CDN de Cloudflare
RUN mkdir -p /tmp/sysroot_64 /tmp/sysroot_32 /termux_64 /termux_32 /data/data/com.termux/files && \
    \
    cd /tmp/sysroot_64 && curl -sL "https://termux.dev" > Packages && \
    for p in libdrm libandroid-shmem libxcb libx11 libxshmfence libxext libxrandr libxrender xorgproto libxau libxdmcp; do \
        path=$(awk -v pkg="Package: $p" '$0==pkg{f=1} f && /^Filename:/{print $2; exit}' Packages) && \
        curl -sL -O "https://termux.dev{path}"; \
    done && dpkg-deb -x *.deb /termux_64 && ln -s /termux_64/data/data/com.termux/files/usr /data/data/com.termux/files/usr64 && \
    \
    cd /tmp/sysroot_32 && curl -sL "https://termux.dev" > Packages && \
    for p in libdrm libandroid-shmem libxcb libx11 libxshmfence libxext libxrandr libxrender xorgproto libxau libxdmcp; do \
        path=$(awk -v pkg="Package: $p" '$0==pkg{f=1} f && /^Filename:/{print $2; exit}' Packages) && \
        curl -sL -O "https://termux.dev{path}"; \
    done && dpkg-deb -x *.deb /termux_32 && ln -s /termux_32/data/data/com.termux/files/usr /data/data/com.termux/files/usr32 && \
    rm -rf /tmp/sysroot_64 /tmp/sysroot_32

# 3. Configurar perfiles cruzados mediante generadores compactos (Inyección de -landroid nativo de Android)
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    mkdir -p /root/build-config && \
    \
    printf "[binaries]\nc = '%s/aarch64-linux-android30-clang'\ncpp = '%s/aarch64-linux-android30-clang++'\nar = '%s/llvm-ar'\nstrip = '%s/llvm-strip'\npkg-config = 'pkg-config'\n[constants]\ntermux_dir = '/termux_64/data/data/com.termux/files/usr'\n[properties]\npkg_config_libdir = termux_dir + '/lib/pkgconfig:' + termux_dir + '/share/pkgconfig'\n[built-in options]\nc_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h']\ncpp_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h']\nc_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem', '-landroid']\ncpp_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem', '-landroid']\n[host_machine]\nsystem = 'android'\ncpu_family = 'aarch64'\ncpu = 'armv8-a'\nendian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" > /root/build-config/cross_aarch64.txt && \
    \
    printf "[binaries]\nc = '%s/armv7a-linux-android30-clang'\ncpp = '%s/armv7a-linux-android30-clang++'\nar = '%s/llvm-ar'\nstrip = '%s/llvm-strip'\npkg-config = 'pkg-config'\n[constants]\ntermux_dir = '/termux_32/data/data/com.termux/files/usr'\n[properties]\npkg_config_libdir = termux_dir + '/lib/pkgconfig:' + termux_dir + '/share/pkgconfig'\n[built-in options]\nc_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h', '-march=armv7-a', '-mfpu=neon']\ncpp_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h', '-march=armv7-a', '-mfpu=neon']\nc_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem', '-landroid']\ncpp_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem', '-landroid']\n[host_machine]\nsystem = 'android'\ncpu_family = 'arm'\ncpu = 'armv7-a'\nendian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" > /root/build-config/cross_arm.txt

# 4. Script de orquestación híbrido (Compilación secuencial fusionada con bypass de libadrenotools)
RUN printf '#!/bin/bash\nset -e\nBUILD_DIR="${1:-compilacion}"\nNDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)\nSTRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"\n\
ANON_FILE=$(find src/ -name "anon_file.c" | head -n 1)\n\
if [ -n "$ANON_FILE" ]; then sed -i "s/memfd_create(debug_name, MFD_CLOEXEC);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g" "$ANON_FILE"; fi\n\
ADRENO_MESON=$(find subprojects/ -name "meson.build" | grep "libadrenotools" | head -n 1)\n\
if [ -n "$ADRENO_MESON" ] && [ -f "$ADRENO_MESON" ]; then echo "-> Aplicando bypass a libadrenotools..."; sed -i "s/cxx.find_library(\x27android\x27)/null_dep/g" "$ADRENO_MESON"; sed -i "s/compiler.find_library(\x27android\x27)/null_dep/g" "$ADRENO_MESON"; sed -i "s/cxx.find_library(\"android\")/null_dep/g" "$ADRENO_MESON"; sed -i "s/compiler.find_library(\"android\")/null_dep/g" "$ADRENO_MESON"; fi\n\
rm -f /data/data/com.termux/files/usr || true\n\
ln -s /data/data/com.termux/files/usr32 /data/data/com.termux/files/usr\n\
rm -rf build_32 || true\n\
meson setup build_32 --cross-file /root/build-config/cross_arm.txt -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= -Dxmlconfig=disabled -Dvulkan-drivers=wrapper\n\
meson compile -C build_32\n\
$STRIP --strip-unneeded src/vulkan/wrapper/libvulkan_wrapper.so -o build_32/libvulkan_wrapper32.so\n\
xxd -i build_32/libvulkan_wrapper32.so > src/vulkan/wrapper/vulkan_wrapper32_payload.h\n\
WRAPPER_LOG=$(find src/ -name "wrapper_log.c" | head -n 1)\n\
sed -i "s/\\r$//" "$WRAPPER_LOG"\n\
sed -i "/__vulkan_universal_blob_bridge__/,\$d" "$WRAPPER_LOG" || true\n\
printf "\\n/* __vulkan_universal_blob_bridge__ */\\n#include \\"vulkan_wrapper32_payload.h\\"\\n#include <sys/mman.h>\\n#include <unistd.h>\\n#include <fcntl.h>\\n#include <dlfcn.h>\\n#include <stdio.h>\\nextern int mallopt(int p, int v);\\nextern int setenv(const char *n, const char *v, int o);\\n__attribute__((constructor)) static void load_universal_vulkan_layer(void) {\\n mallopt(-1002, 0); setenv(\\"MESA_VK_WSI_PRESENT_MODE\\", \\"mailbox\\", 1); setenv(\\"vblank_mode\\", \\"0\\", 1);\\n if (sizeof(void*) == 4) {\\n setenv(\\"MESA_VK_WSI_QUEUE_SIZE\\", \\"1\\", 1);\\n int fd = memfd_create(\\"vulkan_mali_32\\", 0x0001U | 0x0002U);\\n if (fd >= 0) {\\n write(fd, build_32_libvulkan_wrapper32_so, build_32_libvulkan_wrapper32_so_len);\\n char fd_path; sprintf(fd_path, \\"/proc/self/fd/%%d\\", fd);\\n void* h32 = dlopen(fd_path, RTLD_LAZY | RTLD_GLOBAL);\\n if (h32) setenv(\\"VULKAN_WRAPPER_32_LOADED\\", \\"1\\", 1);\\n }\\n }\\n}\\n" >> "$WRAPPER_LOG"\n\
rm -f /data/data/com.termux/files/usr || true\n\
ln -s /data/data/com.termux/files/usr64 /data/data/com.termux/files/usr\n\
rm -rf meson-private meson-logs meson-info "${BUILD_DIR}" || true\n\
meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_aarch64.txt -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= -Dxmlconfig=disabled -Dvulkan-drivers=wrapper\n\
meson compile -C "${BUILD_DIR}"\n\
$STRIP --strip-unneeded "${BUILD_DIR}/src/vulkan/wrapper/libvulkan_wrapper.so" -o "${BUILD_DIR}/libvulkan_wrapper.so"\n\
' > /root/build.sh && chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
