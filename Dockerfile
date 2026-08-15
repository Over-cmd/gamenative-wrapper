FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar herramientas del sistema y asegurar dependencias de Python para Mesa
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Enlazar las librerías preinstaladas locales de Termux al entorno de compilación
RUN mkdir -p /data/data/com.termux/files && \
    (ln -s /home/builder/.termux-build/_cache/14-aarch64/bootstrap/data/data/com.termux/files/usr /data/data/com.termux/files/usr || \
     ln -s /home/builder/lib /data/data/com.termux/files/usr) || true

# 3. Generar el archivo de configuración cruzada de Meson de forma limpia (Blindado con 'EOF')
RUN mkdir -p /root/build-config && \
    NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    cat << 'EOF' > /root/build-config/cross_file.txt
[binaries]
c = 'NDK_BIN_PLACEHOLDER/aarch64-linux-android30-clang'
cpp = 'NDK_BIN_PLACEHOLDER/aarch64-linux-android30-clang++'
ar = 'NDK_BIN_PLACEHOLDER/llvm-ar'
strip = 'NDK_BIN_PLACEHOLDER/llvm-strip'
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
    sed -i "s|NDK_BIN_PLACEHOLDER|${NDK_BIN}|g" /root/build-config/cross_file.txt

# 4. Generar el script de compilación original atómica con el parche de silicio de anon_file
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
