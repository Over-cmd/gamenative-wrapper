#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ACOPLADOR DOCKER + PANFROST MULTI-ARQUITECTURA"
echo "=========================================================="

echo "-> 1. Sincronizando submódulos gráficos..."
cd subprojects/libadrenotools && git submodule update --init --recursive && cd ../..

echo "-> 2. Inyectando parches biónicos de alineación de memoria (Mali Hybrid)..."
WRAPPER_DEVICE=$(find src/ -name "wrapper_device.c" | head -n 1)
if [ -n "$WRAPPER_DEVICE" ] && [ -f "$WRAPPER_DEVICE" ]; then
  sed -i 's/\r$//' "$WRAPPER_DEVICE"
  sed -i '1i#include <stdint.h>' "$WRAPPER_DEVICE"
  sed -i '1iextern int mallopt(int param, int value);' "$WRAPPER_DEVICE"
  sed -i '1iextern int setenv(const char *name, const char *value, int overwrite);' "$WRAPPER_DEVICE"
  sed -i '/vk_icdGetInstanceProcAddr/!b;n;i\\ extern int mallopt(int p, int v);\\n extern int setenv(const char *n, const char *v, int o);\\n mallopt(-1002, 0);\\n setenv("MESA_VK_WSI_PRESENT_MODE", "mailbox", 1);\\n setenv("vblank_mode", "0", 1);\\n if (sizeof(void*) == 4) {\\n   setenv("MESA_VK_WSI_QUEUE_SIZE", "1", 1);\\n }' "$WRAPPER_DEVICE"
fi

echo "-> 3. Lanzando el compilador atómico de Docker (ghcr.io/leegao)..."
# Esto generará el archivo Fat unificado 'libvulkan_wrapper.so' con el parche de mallopt integrado
docker run --rm -v "${{ github.workspace }}:/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 4. Compilando el driver físico real de Panfrost de 64 bits de respaldo..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Creamos stubs estáticos rápidos para alimentar el linker de Panfrost suelto
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
EOF
mkdir -p "$GITHUB_WORKSPACE/shims_64"
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_64.o
$NDK_BIN/llvm-ar rcs "$GITHUB_WORKSPACE/shims_64/libvulkan_wrapper.a" stub_logs_64.o

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"
cat << EOF > cross_64.txt
[constants]
ndk_path = '${ANDROID_NDK_HOME}'
toolchain = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/bin'
api = '26'
[binaries]
c       = toolchain + '/aarch64-linux-android' + api + '-clang'
cpp     = toolchain + '/aarch64-linux-android' + api + '-clang++'
ar      = toolchain + '/llvm-ar'
strip   = toolchain + '/llvm-strip'
pkgconfig = 'false'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '${NDK_SYSROOT}'
libdir = '${NDK_SYSROOT_LIB_64}'
[built-in options]
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$GITHUB_WORKSPACE/shims_64']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$GITHUB_WORKSPACE/shims_64']
EOF

# Purgamos validaciones rígidas y compilamos Panfrost en 64 bits pura
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-64

# ==========================================
# 🟢 FASE DE MAQUETADO DEFINITIVA DE ÉXITO
# ==========================================
echo "-> 5. Estructurando empaque plano reglamentario para Bannerlator..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d

echo "-> [A] Copiando el Wrapper legítimo protector de Docker como la puerta principal..."
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

echo "-> [B] Copiando el motor físico real de Panfrost de 64 bits para alimentar el renderizado..."
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so

# Ranura de 32 bits de contingencia usando el propio Wrapper híbrido
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_panfrost_32.so

echo "-> Estampando identidades de SONAME y limpiando binarios..."
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost_64.so pkg/usr/lib/libvulkan_panfrost_64.so
patchelf --set-soname libvulkan_panfrost_32.so pkg/usr/lib/libvulkan_panfrost_32.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

echo "-> [C] Escribiendo manifiestos ICD duales limpios para Box86/Box64..."
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "$GITHUB_WORKSPACE/wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡PACK COMPLETO DOCKER + PANFROST COMPLETADO CON ÉXITO!"
echo "=========================================================="
