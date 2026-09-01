#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO COMPILACIÓN REGLAMENTARIA MESA 25 SIN OVERLAY"
echo "=========================================================="

echo "-> 1. Compilando el Interceptor oficial en Docker..."
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Limpiamos los archivos modificados para dejar el árbol en su estado puro oficial
git checkout src/vulkan/runtime/vk_instance.c 2>/dev/null || true
git checkout src/vulkan/wsi/wsi_common_drm.c 2>/dev/null || true
git checkout src/panfrost/lib/kmod/pan_kmod.c 2>/dev/null || true
git checkout src/panfrost/lib/kmod/panfrost_kmod.c 2>/dev/null || true
git checkout src/panfrost/lib/kmod/panthor_kmod.c 2>/dev/null || true
git checkout src/panfrost/vulkan/jm/panvk_queue.h 2>/dev/null || true
git checkout src/vulkan/wrapper/wrapper_log.c 2>/dev/null || true

# Fabricamos el stub biónico mínimo de logs que ld.lld exige resolver en el wrapper
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
EOF

mkdir -p "$(pwd)/shims_64"
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_64.o
$NDK_BIN/llvm-ar rcs "$(pwd)/shims_64/libvulkan_wrapper.a" stub_logs_64.o

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

# Configuración del pkg-config local apuntando a los recursos de adrenotools
cat << EOF > $(pwd)/shims_64/libdrm.pc
Name: libdrm
Description: Userspace interface to kernel DRM services
Version: 2.4.120
Libs: -L$(pwd)/shims_64 -lvulkan_wrapper
Cflags: -I.
EOF

echo "-> 3. Generando cross_64.txt..."
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
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '${NDK_SYSROOT}'
libdir = '${NDK_SYSROOT_LIB_64}'
pkg_config_path = '$(pwd)/shims_64'
pkg_config_libdir = '$(pwd)/shims_64'
[built-in options]
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
EOF

# Parches rápidos sobre meson.build para saltarnos librerías de escritorio ausentes en móviles
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

# 🟢 CONFIGURACIÓN CORREGIDA: Removida la bandera extinta -Dgallium-vulkan-overlay de la receta de Mesa 25
echo "-> 4. Compilando la pila oficial de Panfrost para Android..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload \
  -Dbuildtype=release \
  -Dplatforms=android \
  -Dandroid-stub=true \
  -Dglx=disabled \
  -Dgbm=disabled \
  -Degl=disabled \
  -Dllvm=disabled \
  -Dgallium-drivers=[] \
  -Dvulkan-drivers=panfrost,wrapper \
  -Dvulkan-layers=[]
meson compile -C build-64

# Maquetado de integración oficial de Bannerlator
echo "-> 5. Maquetando empaque unificado compatible con la app..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/share/vulkan/icd.d

# Colocamos el interceptor en la raíz de la arquitectura biónica
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
# Colocamos el driver físico real de Panfrost dentro de su ranura correspondiente
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

# Firmamos el SONAME dinámico interno de los binarios
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

# Aplicamos strip definitivo para optimizar espacio en el teléfono
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true

# Escribimos el manifiesto ICD oficial con la ruta esperada por Bannerlator
cat << 'EOF' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
{
    "ICD": {
        "api_version": "1.3.289",
        "library_path": "libvulkan_wrapper.so"
    },
    "file_format_version": "1.0.0"
}
EOF

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡FAT PACK INTEGRAL REGLAMENTARIO COMPLETADO CON ÉXITO!"
echo "=========================================================="
