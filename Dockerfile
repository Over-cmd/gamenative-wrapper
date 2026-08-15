FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar herramientas del sistema y dependencias de Python para Mesa
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Descargar e instalar las dependencias gráficas de Termux (AArch64) desde el CDN oficial de Cloudflare
RUN mkdir -p /tmp/sysroot /data/data/com.termux/files/usr && \
    cd /tmp/sysroot && \
    curl -sL "https://termux.dev" > Packages && \
    for p in libdrm libandroid-shmem libxcb libx11 libxshmfence libxext libxrandr libxrender xorgproto libxau libxdmcp; do \
        path=$(awk -v pkg="Package: $p" '$0==pkg{f=1} f && /^Filename:/{print $2; exit}' Packages) && \
        curl -sL -O "https://termux.dev{path}"; \
    done && \
    for f in *.deb; do dpkg-deb -x "$f" /; done && \
    rm -rf /tmp/sysroot

# 3. Generar el archivo de configuración cruzada de Meson usando Python (Evita fallos de sintaxis de Docker)
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    mkdir -p /root/build-config && \
    python3 -c " \
import os; \
ndk_bin = '${NDK_BIN}'; \
t_dir = '/data/data/com.termux/files/usr'; \
config = f'''[binaries]\n\
c = '{ndk_bin}/aarch64-linux-android30-clang'\n\
cpp = '{ndk_bin}/aarch64-linux-android30-clang++'\n\
ar = '{ndk_bin}/llvm-ar'\n\
strip = '{ndk_bin}/llvm-strip'\n\
pkg-config = 'pkg-config'\n\n\
[constants]\n\
termux_dir = '{t_dir}'\n\n\
[properties]\n\
pkg_config_libdir = termux_dir + '/lib/pkgconfig:' + termux_dir + '/share/pkgconfig'\n\n\
[built-in options]\n\
c_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h']\n\
cpp_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-include', 'fcntl.h', '-include', 'unistd.h']\n\
c_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem']\n\
cpp_link_args = ['-L' + termux_dir + '/lib', '-landroid-shmem']\n\n\
[host_machine]\n\
system = 'android'\n\
cpu_family = 'aarch64'\n\
cpu = 'armv8-a'\n\
endian = 'little'\n'''; \
with open('/root/build-config/cross_file.txt', 'w') as f: f.write(config); \
"

# 4. Script de compilación original atómica con el parche del legado para anon_file.c
RUN cat << 'EOF' > /root/build.sh
#!/bin/bash
set -e

BUILD_DIR="${1:-build}"

# PARCHE LEGADO: Asegurar la correcta asignación de anon_file en Android para evitar cierres
ANON_FILE=$(find src/ -name "anon_file.c" | head -n 1)
if [ -n "$ANON_FILE" ] && [ -f "$ANON_FILE" ]; then
  echo "-> Parcheando flags MFD_ALLOW_SEALING en anon_file.c..."
  sed -i 's/memfd_create(debug_name, MFD_CLOEXEC);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g' "$ANON_FILE"
fi

if [ ! -d "${BUILD_DIR}" ]; then
  meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_file.txt \
      -Dcpp_rtti=false \
      -Dgbm=disabled \
      -Dopengl=false \
      -Dllvm=disabled \
      -Dshared-llvm=disabled \
      -Dplatforms=x11 \
      -Dgallium-drivers= \
      -Dxmlconfig=disabled \
      -Dvulkan-drivers=wrapper
fi

ninja -C "${BUILD_DIR}" src/vulkan/wrapper/libvulkan_wrapper.so

cp "${BUILD_DIR}/src/vulkan/wrapper/libvulkan_wrapper.so" "${BUILD_DIR}/libvulkan_wrapper.so.unstripped"

NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)
STRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
$STRIP --strip-unneeded -o "${BUILD_DIR}/libvulkan_wrapper.so" "${BUILD_DIR}/libvulkan_wrapper.so.unstripped"

echo "Build successful:"
echo " - libvulkan_wrapper.so"
echo " - libvulkan_wrapper.so.unstripped"
EOF
RUN chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
