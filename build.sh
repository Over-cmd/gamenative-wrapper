#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR MESA 25 - BLINDAJE DE ADRENOTOOLS"
echo "=========================================================="

# Fijamos la ruta absoluta calculada al inicio para blindar cambios accidentales de directorio
WORKSPACE="$(pwd)"

echo "-> 1. Compilando el Interceptor oficial en Docker..."
docker run --rm -v "${WORKSPACE}:/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

echo "-> 2a. Ejecutando directivas CleanSpec sobre el espacio de trabajo..."
rm -rf "${WORKSPACE}/shims_64"
rm -rf "${WORKSPACE}/include"
rm -rf libdrm_android/
rm -rf build-libdrm/
rm -rf build-64/

# Creamos stubs puros solo para los logs internos de Adrenotools
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
EOF

mkdir -p "${WORKSPACE}/shims_64/lib"
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_64.o
$NDK_BIN/llvm-ar rcs "${WORKSPACE}/shims_64/lib/libvulkan_wrapper.a" stub_logs_64.o

echo "-> 2b. Descargando código legítimo de libdrm SailfishOS vía Zipball Real..."
curl -L "https://github.com/sailfishos-mirror/drm/archive/refs/heads/main.zip" -o libdrm.zip
unzip -q libdrm.zip
mv -v drm-main libdrm_android
rm -f libdrm.zip

# Receta de compilación cruzada nativa móvil con los macros atómicos legítimos
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

# Compilamos la librería real de forma limpia
meson setup build-libdrm libdrm_android --cross-file cross_libdrm.txt --prefix="${WORKSPACE}/shims_64" \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false
meson install -C build-libdrm

# Enlazamos las cabeceras originales directamente en las rutas de Mesa para que Clang las lea de golpe
mkdir -p include
cp -rf shims_64/include/libdrm/* include/ 2>/dev/null || cp -rf shims_64/include/* include/
mkdir -p include/libdrm
cp -rf include/* include/libdrm/ 2>/dev/null || true

# Reparación nativa de trazas del subsistema wrapper para corregir el NDK r28
if [ -f "src/vulkan/wrapper/wrapper_log.c" ]; then
python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
f=open(p,"r"); c=f.read(); f.close()
if "fcntl.h" not in c:
    c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
    f=open(p,"w"); f.write(c); f.close()
'
fi

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

echo "-> 3. Generando cross_64.txt definitivo con dependencias legítimas..."
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
pkg_config_path = '${WORKSPACE}/shims_64/lib/pkgconfig'
pkg_config_libdir = '${WORKSPACE}/shims_64/lib/pkgconfig'
[built-in options]
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I${WORKSPACE}/shims_64/include', '-I${WORKSPACE}/shims_64/include/libdrm']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I${WORKSPACE}/shims_64/include', '-I${WORKSPACE}/shims_64/include/libdrm']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L${WORKSPACE}/shims_64/lib', '-latomic']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L${WORKSPACE}/shims_64/lib', '-latomic']
EOF

# Reparación de librerías del sistema ausentes en el Host
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

# Neutralizamos la búsqueda rígida de 'android' en libadrenotools porque el linker ya la hereda nativamente
sed -i "s/cc.find_library('android'/dependency('', required : false) #/g" subprojects/libadrenotools/meson.build 2>/dev/null || true

# Compilando la pila oficial de Panfrost
echo "-> 4. Compilando Panfrost Mesa 25 amarrado a libdrm real..."
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

echo "-> 5. Maquetando empaque unificado de integración reglamentaria..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/share/vulkan/icd.d

# Copiamos el interceptor principal (el escudo de entrada suelto en la raíz de usr/lib)
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

# Guardamos la librería real bajo el nombre plano libdrm.so para Bionic
find shims_64/lib/ -name "libdrm.so" -exec cp -v {} pkg/usr/lib/libdrm.so \;

# 🟢 CORRECCIÓN: Conservamos el nombre original único en disco para evitar que dlopen() entre en bucle circular infinito en Android
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so

# Sellamos las firmas internas de SONAME limpias e independientes para cada componente
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-soname libdrm.so pkg/usr/lib/libdrm.so

# Amarramos libdrm.so de forma local mediante RUNPATH con retroceso $ORIGIN en el driver físico (sin barras de escape corruptas)
patchelf --add-needed libdrm.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-rpath '$ORIGIN/..' pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so

# Sello local $ORIGIN en el interceptor suelto para amarrar sus llamadas a su mismo nivel jerárquico
patchelf --add-needed libdrm.so pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/libvulkan_wrapper.so

# Strip final para aligerar espacio y eliminar símbolos de desarrollo redundantes
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true

# Manifiesto ICD oficial de Bannerlator
cat << 'EOF' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
{
    "ICD": {
        "api_version": "1.3.289",
        "library_path": "libvulkan_wrapper.so"
    },
    "file_format_version": "1.0.0"
}
EOF

# Guardamos la firma de versión, aplicamos permisos y empaquetamos con zstd extremo
echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "  778/778 COMPLETO - DRIVER MONOLÍTICO HÍBRIDO LISTO    "
echo "=========================================================="
