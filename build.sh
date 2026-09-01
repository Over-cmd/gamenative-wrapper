#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ARCHIVO MODULAR 2: MOTOR DE COMPILACIÓN MESA"
echo "=========================================================="

WORKSPACE="$(pwd)"

echo "-> 1. Compilando el Interceptor oficial en Docker..."
docker run --rm -v "${WORKSPACE}:/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

# 🟢 LLAMADA MAESTRA: Invocamos el primer script modular para poblar los Shims e instalar dependencias reales
chmod +x patch_mesa.sh
./patch_mesa.sh

export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

rm -rf build-libdrm/
rm -rf build-64/

# Receta de compilación cruzada para libdrm
cat << EOF > cross_libdrm.txt
[binaries]
c       = '${NDK_BIN}/aarch64-linux-android26-clang'
cpp     = '${NDK_BIN}/aarch64-linux-android26-clang++'
ar      = '${NDK_BIN}/llvm-ar'
strip   = '${NDK_BIN}/llvm-strip'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = '${NDK_SYSROOT}'
[built-in options]
c_args = ['--sysroot=${NDK_SYSROOT}', '-DANDROID', '-D_GNU_SOURCE', '-DBIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD=1', '-DHAVE_LIBDRM_ATOMIC_PRIMITIVES=1']
EOF

echo "-> 2. Compilando e instalando libdrm original de forma aislada..."
meson setup build-libdrm libdrm_android --cross-file cross_libdrm.txt --prefix="${WORKSPACE}/shims_64" \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false
meson install -C build-libdrm

mkdir -p include
cp -rf shims_64/include/libdrm/* include/ 2>/dev/null || cp -rf shims_64/include/* include/
mkdir -p include/libdrm
cp -rf include/* include/libdrm/ 2>/dev/null || true

# Reparación nativa de trazas del subsistema wrapper para corregir el NDK r28
python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
f=open(p,"r"); c=f.read(); f.close()
if "fcntl.h" not in c:
    c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
    f=open(p,"w"); f.write(c); f.close()
'

echo "-> 3. Generando cross_64.txt definitivo con tu arquitectura de constantes..."
cat << EOF > cross_64.txt
[constants]
ndk_path = '/usr/local/lib/android/sdk/ndk/28.2.13676358'
toolchain = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/bin'
sysroot_ndk = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/sysroot'
shims_path = '${WORKSPACE}/shims_64'
virtual_sysroot = '${WORKSPACE}/sysroot_virtual'
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
sys_root = virtual_sysroot
libdir = virtual_sysroot + '/usr/lib'
pkg_config_path = shims_path + '/lib/pkgconfig'
pkg_config_libdir = shims_path + '/lib/pkgconfig'

[built-in options]
c_args = ['--sysroot=' + sysroot_ndk, '-I' + virtual_sysroot + '/usr/lib', '-D__TERMUX__', '-I' + shims_path + '/include', '-I' + shims_path + '/include/libdrm']
cpp_args = ['--sysroot=' + sysroot_ndk, '-I' + virtual_sysroot + '/usr/lib', '-D__TERMUX__', '-I' + shims_path + '/include', '-I' + shims_path + '/include/libdrm']
c_link_args = ['--sysroot=' + virtual_sysroot, '-L' + virtual_sysroot + '/usr/lib', '-L' + shims_path + '/lib', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
cpp_link_args = ['--sysroot=' + virtual_sysroot, '-L' + virtual_sysroot + '/usr/lib', '-L' + shims_path + '/lib', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
EOF

# Reparación de librerías del sistema del core de Mesa
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 4. Compilando Panfrost Mesa 25 con Adrenotools Limpio..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload \
  -Dbuildtype=release \
  -Dplatforms=android \
  -Dglx=disabled \
  -Dgbm=disabled \
  -Degl=disabled \
  -Dllvm=disabled \
  -Dgallium-drivers=[] \
  -Dvulkan-drivers=panfrost,wrapper \
  -Dvulkan-layers=[]
meson compile -C build-64

echo "-> 5. Maquetando empaque con arquitectura de proximidad unificada..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/share/vulkan/icd.d

cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
cp -v shims_64/lib/libdrm.so pkg/usr/lib/libdrm.so 2>/dev/null || cp -v shims_64/lib/aarch64-linux-gnu/libdrm.so pkg/usr/lib/libdrm.so 2>/dev/null || true
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost.so

cd pkg/usr/lib/aarch64-linux-android
ln -sf ../libvulkan_panfrost.so libvulkan_wrapper.so
cd "${WORKSPACE}"

patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-soname libdrm.so pkg/usr/lib/libdrm.so 2>/dev/null || true

patchelf --add-needed libdrm.so pkg/usr/lib/libvulkan_panfrost.so 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/libvulkan_panfrost.so 2>/dev/null || true
patchelf --add-needed libdrm.so pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true

$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

cat << 'EOF' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
{
    "ICD": { "api_version": "1.3.289", "library_path": "libvulkan_wrapper.so" },
    "file_format_version": "1.0.0"
}
EOF

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🏆¡EMPAQUE MODULAR INTEGRAL CONCLUIDO CON ÉXITO TOTAL! 🏆"
echo "=========================================================="
