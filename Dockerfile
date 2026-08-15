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

# 3. Generar el archivo de configuración de compilación cruzada original de Termux
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    mkdir -p /root/build-config && \
    cat << EOF > /root/build-config/cross_file.txt
[binaries]
c = '${NDK_BIN}/aarch64-linux-android30-clang'
cpp = '${NDK_BIN}/aarch64-linux-android30-clang++'
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'
pkg-config = 'pkg-config'

[constants]
termux_dir = '/data/data/com.termux/files/usr'

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

# 4. Script de compilación original atómica
RUN cat << 'EOF' > /root/build.sh
#!/bin/bash
set -e

BUILD_DIR="${1:-build}"

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
