#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO PIPELINE MULTI-ETAPA FIEL AL DOCKERFILE ORIGINAL"
echo "=========================================================="

echo "-> STAGE 1: Inicializando submódulos y aplicando parches base..."
cd subprojects/libadrenotools && git submodule update --init --recursive && cd ../..

# Parches críticos de hardware para la GPU Mali-G52
sed -i 's/fd = syscall(SYS_memfd_create.*/fd = memfd_create(debug_name, MFD_CLOEXEC \| MFD_ALLOW_SEALING);/g' src/util/anon_file.c 2>/dev/null || true
sed -i '1s|^|static int sync_wait(int fd, int timeout) { return 0; }\n|' src/panfrost/lib/kmod/panthor_kmod.c
sed -i '1s|^|#include <fcntl.h>\n|' src/vulkan/wrapper/wrapper_log.c

# Neutralizar las búsquedas rígidas de librerías del sistema que rompen el setup cruzado
sed -i "s|libandroid_dep = .*|libandroid_dep = dependency('', required : false)|g" subprojects/libadrenotools/meson.build
sed -i "s|liblog_dep = .*|liblog_dep = dependency('', required : false)|g" subprojects/libadrenotools/meson.build
find subprojects/libadrenotools/ -name "meson.build" -exec sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" {} + 2>/dev/null || true

# Sanear las búsquedas de librerías obsoletas en el meson.build central de Mesa
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> Instalando herramientas de Python requeridas..."
python -m pip install --upgrade pip && pip install mako PyYAML 'meson>=1.4.0' ninja packaging

# Detectar el Android NDK oficial preinstalado en el entorno de GitHub
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Extraer shims locales de contingencia
unzip -o shims.zip -d ./ && mkdir -p "$GITHUB_WORKSPACE/shims_target" && cp -rf ./shims/* "$GITHUB_WORKSPACE/shims_target/"

# ==========================================
# 🟢 STAGE 2: COMPILACIÓN DE 32 BITS (Mali-G52 MP2)
# ==========================================
echo "-> Generando archivo de configuración cruzada cross_32.txt..."
NDK_SYSROOT_LIB_32="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/30"
cat << EOF > cross_32.txt
[constants]
ndk_bin = '${NDK_BIN}'
ndk_sysroot = '${NDK_SYSROOT}'
[binaries]
c = [ndk_bin / 'armv7a-linux-androideabi30-clang', '-D__TERMUX__']
cpp = [ndk_bin / 'armv7a-linux-androideabi30-clang++', '-fno-exceptions', '--start-no-unused-arguments', '--end-no-unused-arguments', '-D__TERMUX__']
ar = ndk_bin / 'llvm-ar'
strip = ndk_bin / 'llvm-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'arm'
endian = 'little'
[properties]
sys_root = ndk_sysroot
libdir = '${NDK_SYSROOT_LIB_32}'
pkg_config_path = '$GITHUB_WORKSPACE/shims_target'
pkg_config_libdir = '$GITHUB_WORKSPACE/shims_target'
[built-in options]
c_args = ['--sysroot=' + ndk_sysroot, '-I$GITHUB_WORKSPACE/shims_target/include', '-Wl,-llog', '-Wl,-lsync']
cpp_args = ['--sysroot=' + ndk_sysroot, '-I$GITHUB_WORKSPACE/shims_target/include', '-Wl,-llog', '-Wl,-lsync']
c_link_args = ['-landroid', '-llog', '-lsync', '-L${NDK_SYSROOT_LIB_32}', '-L$GITHUB_WORKSPACE/shims_target']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-L${NDK_SYSROOT_LIB_32}', '-L$GITHUB_WORKSPACE/shims_target']
EOF

echo "-> Ejecutando Meson y Ninja para compilar el driver físico de 32 bits..."
meson setup build-32 --cross-file cross_32.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-32

# ==========================================
# 🟢 STAGE 3: COMPILACIÓN DE 64 BITS (Mali-G52 MP2)
# ==========================================
echo "-> Generando archivo de configuración cruzada cross_64.txt..."
NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/30"
cat << EOF > cross_64.txt
[constants]
ndk_bin = '${NDK_BIN}'
ndk_sysroot = '${NDK_SYSROOT}'
[binaries]
c = [ndk_bin / 'aarch64-linux-android30-clang', '-D__TERMUX__']
cpp = [ndk_bin / 'aarch64-linux-android30-clang++', '-fno-exceptions', '--start-no-unused-arguments', '--end-no-unused-arguments', '-D__TERMUX__']
ar = ndk_bin / 'llvm-ar'
strip = ndk_bin / 'llvm-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = ndk_sysroot
libdir = '${NDK_SYSROOT_LIB_64}'
pkg_config_path = '$GITHUB_WORKSPACE/shims_target'
pkg_config_libdir = '$GITHUB_WORKSPACE/shims_target'
[built-in options]
c_args = ['--sysroot=' + ndk_sysroot, '-I$GITHUB_WORKSPACE/shims_target/include', '-Wl,-llog', '-Wl,-lsync']
cpp_args = ['--sysroot=' + ndk_sysroot, '-I$GITHUB_WORKSPACE/shims_target/include', '-Wl,-llog', '-Wl,-lsync']
c_link_args = ['-landroid', '-llog', '-lsync', '-L${NDK_SYSROOT_LIB_64}', '-L$GITHUB_WORKSPACE/shims_target']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-L${NDK_SYSROOT_LIB_64}', '-L$GITHUB_WORKSPACE/shims_target/include']
EOF

echo "-> Ejecutando Meson y Ninja para compilar el driver físico de 64 bits..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-64

# ==========================================
# 🟢 STAGE 4: COMPILACIÓN DEL ENRUTADOR PUENTE DINÁMICO EN C
# ==========================================
echo "-> Fabricando el código fuente del enrutador dinámico (wrapper.c) extraído del Dockerfile..."
cat << 'EOF' > wrapper.c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

static void* handle = NULL;

__attribute__((constructor)) void init_wrapper() {
    // Forzar variables de entorno nativas de Mesa para despertar el bus gráfico de Panfrost
    setenv("PAN_I_WANT_A_BROKEN_VULKAN_DRIVER", "1", 1);
    setenv("MESA_VK_IGNORE_CONFORMANCE_WARNING", "1", 1);
    setenv("PANVK_DEBUG", "sync,nir", 1);
    setenv("MESA_VK_FORCE_BLIT", "1", 1);
    setenv("MESA_LOADER_DRIVER_OVERRIDE", "panfrost", 1);
    setenv("GALLIUM_DRIVER", "panfrost", 1);

    if (sizeof(void*) == 8) {
        handle = dlopen("/usr/lib/libvulkan_panfrost_64.so", RTLD_NOW | RTLD_GLOBAL);
        if (!handle) handle = dlopen("./libvulkan_panfrost_64.so", RTLD_NOW | RTLD_GLOBAL);
    } else {
        handle = dlopen("/usr/lib/libvulkan_panfrost_32.so", RTLD_NOW | RTLD_GLOBAL);
        if (!handle) handle = dlopen("./libvulkan_panfrost_32.so", RTLD_NOW | RTLD_GLOBAL);
    }
}

// Interceptor universal de entrada ICD de Vulkan que redirige las llamadas hacia los drivers físicos reales de Mesa
void* vk_icdGetInstanceProcAddr(void* instance, const char* pName) {
    if (!handle) return NULL;
    typedef void* (*PFN_icdGet)(void*, const char*);
    PFN_icdGet real_icd = (PFN_icdGet)dlsym(handle, "vk_icdGetInstanceProcAddr");
    return real_icd ? real_icd(instance, pName) : NULL;
}
EOF

echo "-> Compilando el enrutador puente como 'libvulkan_wrapper.so' de 64 bits pura..."
$NDK_BIN/aarch64-linux-android30-clang -shared -fPIC -o libvulkan_wrapper.so wrapper.c -ldl --sysroot="$NDK_SYSROOT"

# ==========================================
# 🟢 STAGE 5: EMPAQUETADO COMPATIBLE BANNERLATOR
# ==========================================
echo "-> Maquetando la estructura plana limpia del paquete ICD..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d

# 1. Copiar los binarios reales renombrados exactamente como los requiere el dlopen() en runtime
cp -v libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so
cp -v build-32/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_32.so

# 2. Sellar identidades internas y remover símbolos muertos para optimizar peso
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost_64.so pkg/usr/lib/libvulkan_panfrost_64.so
patchelf --set-soname libvulkan_panfrost_32.so pkg/usr/lib/libvulkan_panfrost_32.so
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

# 3. Escribir los manifiestos JSON limpios sin la carpeta settings.d solicitada
echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

# 4. Comprimir el paquete en el formato definitivo .tzst
echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "$GITHUB_WORKSPACE/wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡ECOSISTEMA UNIFICADO DE 32/64 BITS GENERADO CON ÉXITO!"
echo "=========================================================="
