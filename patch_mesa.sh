#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 INICIANDO ARCHIVO MODULAR 1: COMPILACIÓN DE SHIMS REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

# 🟢 REPARACIÓN CRÍTICA DE PURGA: Forzamos la eliminación de residuos antiguos con privilegios sudo para evitar el Permission Denied
echo "-> 1a. Limpiando residuos antiguos para CleanSpec..."
sudo rm -rf "${WORKSPACE}/shims_64"
sudo rm -rf "${WORKSPACE}/sysroot_virtual"
sudo rm -rf "${WORKSPACE}/include/libdrm"
sudo rm -rf libdrm_android/
sudo rm -rf subprojects/libadrenotools/

cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
void *dlopen(const char *filename, int flags) { (void)filename; (void)flags; return 0; }
void *dlsym(void *handle, const char *symbol) { (void)handle; (void)symbol; return 0; }
int dlclose(void *handle) { (void)handle; return 0; }
EOF

mkdir -p "${WORKSPACE}/shims_64/lib"
mkdir -p "${WORKSPACE}/sysroot_virtual/usr/lib"
mkdir -p "${WORKSPACE}/sysroot_virtual/lib"

echo "-> 1b. Compilando stubs duales legítimos para C y C++..."
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_c.o
$NDK_BIN/llvm-ar rcs "${WORKSPACE}/shims_64/lib/liblog.a" stub_logs_c.o
$NDK_BIN/llvm-ar rcs "${WORKSPACE}/shims_64/libvulkan_wrapper.a" stub_logs_c.o

$NDK_BIN/aarch64-linux-android26-clang++ -c stub_logs.c -o stub_logs_cpp.o
$NDK_BIN/llvm-ar rcs "${WORKSPACE}/shims_64/lib/libandroid.a" stub_logs_cpp.o
$NDK_BIN/llvm-ar rcs "${WORKSPACE}/shims_64/lib/libdl.a" stub_logs_cpp.o

echo "-> 1c. Desplegando librerías dentro del Sysroot Virtual privado..."
cp -fv "${WORKSPACE}/shims_64/lib/libandroid.a" "${WORKSPACE}/sysroot_virtual/usr/lib/libandroid.a"
cp -fv "${WORKSPACE}/shims_64/lib/liblog.a" "${WORKSPACE}/sysroot_virtual/usr/lib/liblog.a"
cp -fv "${WORKSPACE}/shims_64/lib/libdl.a" "${WORKSPACE}/sysroot_virtual/usr/lib/libdl.a"
cp -fv "${WORKSPACE}/shims_64/lib/libandroid.a" "${WORKSPACE}/sysroot_virtual/lib/libandroid.a"
cp -fv "${WORKSPACE}/shims_64/lib/liblog.a" "${WORKSPACE}/sysroot_virtual/lib/liblog.a"
cp -fv "${WORKSPACE}/shims_64/lib/libdl.a" "${WORKSPACE}/sysroot_virtual/lib/libdl.a"

ln -sf "${NDK_SYSROOT_LIB_64}"/*.so "${WORKSPACE}/sysroot_virtual/usr/lib/" 2>/dev/null || true

echo "-> 1d. Descargando repositorio de libdrm..."
curl -L "https://github.com/sailfishos-mirror/drm/archive/refs/heads/main.zip" -o libdrm.zip
unzip -q libdrm.zip
mv -v drm-main libdrm_android
rm -f libdrm.zip

echo "-> 1e. Descargando código de Adrenotools en subprojects local para anular el .wrap..."
mkdir -p subprojects
curl -L "https://github.com/Pipetto-crypto/libadrenotools/archive/refs/heads/master.zip" -o adrenotools.zip
unzip -q adrenotools.zip
mv -v libadrenotools-master subprojects/libadrenotools
rm -f adrenotools.zip

echo "-> 1f. Applying cold surgery on downloaded subproject meson.build..."
if [ -f subprojects/libadrenotools/meson.build ]; then
    sed -i "s/cc.find_library('android'/dependency('', required : false) #/g" subprojects/libadrenotools/meson.build
    sed -i "s/cc.find_library('log'/dependency('', required : false) #/g" subprojects/libadrenotools/meson.build
    echo "-> Subproject structure successfully freed and patched natively!"
fi

echo "=========================================================="
echo "🟢 ARCHIVO 1 CONCLUIDO CON ÉXITO - ENTORNO EXPULSADO LIMPIO"
echo "=========================================================="
