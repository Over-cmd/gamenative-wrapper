FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar herramientas del sistema y asegurar dependencias de Python para Mesa
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Enlazar estructuralmente el Sysroot preinstalado local de Termux para que coincida con las rutas de Mesa
RUN mkdir -p /data/data/com.termux/files && \
    rm -rf /data/data/com.termux/files/usr || true && \
    ln -s /home/builder/.termux-build/_cache/14-aarch64/bootstrap/data/data/com.termux/files/usr /data/data/com.termux/files/usr

# 3. Generar el archivo de configuración cruzada de Meson mapeando el NDK y las librerías locales de Termux
RUN NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1) && \
    NDK_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin" && \
    SYS_DIR="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot" && \
    mkdir -p /root/build-config && \
    \
    printf "[binaries]\n\
c = '%s/aarch64-linux-android30-clang'\n\
cpp = '%s/aarch64-linux-android30-clang++'\n\
ar = '%s/llvm-ar'\n\
strip = '%s/llvm-strip'\n\
pkg-config = 'pkg-config'\n\n\
[constants]\n\
termux_dir = '/data/data/com.termux/files/usr'\n\
sys_dir = '%s'\n\n\
[properties]\n\
pkg_config_libdir = termux_dir + '/lib/pkgconfig:' + termux_dir + '/share/pkgconfig'\n\n\
[built-in options]\n\
c_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-I' + sys_dir + '/usr/include', '-include', 'fcntl.h', '-include', 'unistd.h']\n\
cpp_args = ['-D__TERMUX__', '-D__USE_GNU', '-U__ANDROID__', '-I' + termux_dir + '/include', '-I' + sys_dir + '/usr/include', '-include', 'fcntl.h', '-include', 'unistd.h']\n\
c_link_args = ['-L' + termux_dir + '/lib', '-L' + sys_dir + '/usr/lib/aarch64-linux-android/30', '-landroid-shmem']\n\
cpp_link_args = ['-L' + termux_dir + '/lib', '-L' + sys_dir + '/usr/lib/aarch64-linux-android/30', '-landroid-shmem']\n\n\
[host_machine]\n\
system = 'android'\n\
cpu_family = 'aarch64'\n\
cpu = 'armv8-a'\n\
endian = 'little'\n" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$NDK_BIN" "$SYS_DIR" > /root/build-config/cross_file.txt

# 4. Generar el script de compilación inyectando el parche de silicio para anon_file.c
RUN printf '#!/bin/bash\n\
set -e\n\
BUILD_DIR="${1:-build}"\n\
ANON_FILE=$(find src/ -name "anon_file.c" | head -n 1)\n\
if [ -n "$ANON_FILE" ] && [ -f "$ANON_FILE" ]; then\n\
  echo "-> Parcheando flags MFD_ALLOW_SEALING en anon_file.c..."\n\
  sed -i "s/memfd_create(debug_name, MFD_CLOEXEC);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g" "$ANON_FILE"\n\
fi\n\
if [ ! -d "${BUILD_DIR}" ]; then\n\
  meson setup "${BUILD_DIR}" --cross-file /root/build-config/cross_file.txt \\\n\
      -Dcpp_rtti=false \\\n\
      -Dgbm=disabled \\\n\
      -Dopengl=false \\\n\
      -Dllvm=disabled \\\n\
      -Dshared-llvm=disabled \\\n\
      -Dplatforms=x11 \\\n\
      -Dgallium-drivers= \\\n\
      -Dxmlconfig=disabled \\\n\
      -Dvulkan-drivers=wrapper\n\
fi\n\
ninja -C "${BUILD_DIR}" src/vulkan/wrapper/libvulkan_wrapper.so\n\
cp "${BUILD_DIR}/src/vulkan/wrapper/libvulkan_wrapper.so" "${BUILD_DIR}/libvulkan_wrapper.so.unstripped"\n\
NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)\n\
STRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"\n\
$STRIP --strip-unneeded -o "${BUILD_DIR}/libvulkan_wrapper.so" "${BUILD_DIR}/libvulkan_wrapper.so.unstripped"\n\
echo "Build successful:"\n\
echo " - libvulkan_wrapper.so"\n\
echo " - libvulkan_wrapper.so.unstripped"\n' > /root/build.sh

# 5. Otorgar permisos de ejecución finales
RUN chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
