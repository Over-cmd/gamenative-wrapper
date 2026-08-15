FROM ghcr.io/termux/package-builder:latest

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# Descarga y aislamiento de Sysroot para 64 bits (aarch64) y 32 bits (arm)
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

# Generación de perfiles de compilación cruzada independientes (Meson Cross Files)
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    mkdir -p /root/build-config && \
    \
    # PERFIL: 64 Bits (aarch64)
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
    # PERFIL: 32 Bits (armv7a)
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

# Script de compilación inteligente
RUN cat << 'EOF' > /root/build.sh
#!/bin/bash
set -e

BUILD_DIR="${1:-${BUILD_DIR:-build}}"
ARCH_ENV="${TARGET_ARCH:-aarch64}"

CROSS_FILE="/root/build-config/cross_${ARCH_ENV}.txt"

if [ ! -f "$CROSS_FILE" ]; then
  echo "Error: Arquitectura '$ARCH_ENV' no soportada."
  exit 1
fi

rm -f /data/data/com.termux/files/usr || true
if [ "$ARCH_ENV" = "arm" ]; then
  ln -s /data/data/com.termux/files/usr32 /data/data/com.termux/files/usr
else
  ln -s /data/data/com.termux/files/usr64 /data/data/com.termux/files/usr
fi

if [ ! -d "${BUILD_DIR}" ]; then
  meson setup "${BUILD_DIR}" --cross-file "$CROSS_FILE" \
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
EOF
RUN chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
