FROM ghcr.io/termux/package-builder:latest

USER root

# 1. Instalar herramientas del sistema y asegurar dependencias de Python para Mesa
RUN apt-get update && \
    apt-get install -y --no-install-recommends ninja-build && \
    pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging

# 2. Enlazar las librerías preinstaladas locales de Termux al entorno del sistema de compilación
RUN mkdir -p /data/data/com.termux/files && \
    ln -s /home/builder/.termux-build/_cache/14-aarch64/bootstrap/data/data/com.termux/files/usr /data/data/com.termux/files/usr || \
    ln -s /home/builder/lib /data/data/com.termux/files/usr || true

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

# 4. Generar el script de compilación usando Python aplicando el parche de silicio de anon_file
RUN python3 -c " \
script = '''#!/bin/bash\n\
set -e\n\
BUILD_DIR=\"${{1:-build}}\"\n\
ANON_FILE=$(find src/ -name \"anon_file.c\" | head -n 1)\n\
if [ -n \"$ANON_FILE\" ] && [ -f \"$ANON_FILE\" ]; then\n\
  echo \"-> Parcheando flags MFD_ALLOW_SEALING en anon_file.c...\"\n\
  sed -i 's/memfd_create(debug_name, MFD_CLOEXEC);/memfd_create(debug_name, MFD_CLOEXEC | MFD_ALLOW_SEALING);/g' \"$ANON_FILE\"\n\
fi\n\
if [ ! -d \"${{BUILD_DIR}}\" ]; then\n\
  meson setup \"${{BUILD_DIR}}\" --cross-file /root/build-config/cross_file.txt \\\n\
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
ninja -C \"${{BUILD_DIR}}\" src/vulkan/wrapper/libvulkan_wrapper.so\n\
cp \"${{BUILD_DIR}}\"/src/vulkan/wrapper/libvulkan_wrapper.so \"${{BUILD_DIR}}\"/libvulkan_wrapper.so.unstripped\n\
NDK_DIR=\$(find /home/builder/lib -maxdepth 2 -name \"android-ndk*\" 2>/dev/null | head -n 1)\n\
STRIP=\"\${{NDK_DIR}}\"/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip\n\
\$STRIP --strip-unneeded -o \"${{BUILD_DIR}}\"/libvulkan_wrapper.so \"${{BUILD_DIR}}\"/libvulkan_wrapper.so.unstripped\n\
echo \"Build successful:\"\n\
echo \" - libvulkan_wrapper.so\"\n\
echo \" - libvulkan_wrapper.so.unstripped\"\n'''; \
with open('/root/build.sh', 'w') as f: f.write(script); \
" && chmod +x /root/build.sh

WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
