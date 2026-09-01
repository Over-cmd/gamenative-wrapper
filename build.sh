#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR MESA 25 CON LIBDRM NATIVO DE ANDROID"
echo "=========================================================="

echo "-> 1. Compilando el Interceptor oficial en Docker..."
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Creamos stubs puros solo para los logs internos de Adrenotools
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
EOF

mkdir -p "$(pwd)/shims_64"
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_64.o
$NDK_BIN/llvm-ar rcs "$(pwd)/shims_64/libvulkan_wrapper.a" stub_logs_64.o

# 🟢 FASE DE INGENIERÍA PURA: Clonamos y compilamos LIBDRM OFICIAL DE WAYDROID PARA ANDROID
echo "-> 2b. Descargando y compilando libdrm nativo de Android (Waydroid)..."
if [ ! -d "libdrm_android" ]; then
    git clone --depth 1 https://github.com libdrm_android
fi

# Receta de compilación cruzada limpia para el libdrm de Android
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
[built-in options]
c_args = ['--sysroot=${NDK_SYSROOT}']
EOF

# Compilamos libdrm apagando las opciones de PC tradicionales de escritorio
meson setup build-libdrm libdrm_android --cross-file cross_libdrm.txt --prefix="$(pwd)/shims_64" \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled
meson install -C build-libdrm

# Enlazamos las cabeceras nativas originales directamente en las rutas de Mesa para que Clang las absorba de golpe
mkdir -p include
cp -rf shims_64/include/libdrm/* include/
mkdir -p include/libdrm
cp -rf shims_64/include/libdrm/* include/libdrm/

# 🟢 REPARACIÓN TRASLACIÓN DE TRAZAS: Añadimos fcntl.h a wrapper_log.c de forma limpia para corregir el NDK r28
python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
f=open(p,"r"); c=f.read(); f.close()
if "fcntl.h" not in c:
    c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
    f=open(p,"w"); f.write(c); f.close()
'

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

echo "-> 3. Generando cross_64.txt definitivo acoplado a Waydroid..."
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
pkg_config_path = '$(pwd)/shims_64/lib/pkgconfig'
pkg_config_libdir = '$(pwd)/shims_64/lib/pkgconfig'
[built-in options]
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I$(pwd)/shims_64/include', '-I$(pwd)/shims_64/include/libdrm']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I$(pwd)/shims_64/include', '-I$(pwd)/shims_64/include/libdrm']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64/lib']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64/lib']
EOF

sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 4. Compilando Panfrost Mesa 25 sobre dependencias reales de Android..."
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

echo "-> 5. Maquetando empaque compatible de Bannerlator..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/share/vulkan/icd.d

# Copiamos el interceptor oficial y la librería libdrm de Android REAL que acabamos de compilar
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
cp -v shims_64/lib/libdrm.so pkg/usr/lib/libdrm.so.2

# Colocamos el driver físico real de Panfrost Mesa 25 en su ranura reglamentaria
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

# Firmamos las identidades dinámicas con patchelf para engranar los enlaces con libadrenotools
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

# Strip final para aligerar espacio y eliminar símbolos de desarrollo redundantes
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true

# Escribimos el manifiesto ICD oficial que Bannerlator exige leer
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
echo "🟢 ¡COMPILACIÓN PURA CON WAYDROID CONCLUIDA CON ÉXITO!"
echo "=========================================================="
