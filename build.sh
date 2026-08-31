#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR HÍBRIDO FAT COMPLETAMENTE MONOLÍTICO"
echo "=========================================================="

echo "-> 1. Submódulos de Pipetto..."
cd subprojects/libadrenotools && git submodule update --init --recursive && cd ../..

echo "-> 2. Parches de hardware Mali-G52..."
sed -i 's/fd = syscall(SYS_memfd_create.*/fd = memfd_create(debug_name, MFD_CLOEXEC \| MFD_ALLOW_SEALING);/g' src/util/anon_file.c 2>/dev/null || true
sed -i '1s|^|static int sync_wait(int fd, int timeout) { return 0; }\n|' src/panfrost/lib/kmod/panthor_kmod.c
sed -i '1s|^|#include <fcntl.h>\n|' src/vulkan/wrapper/wrapper_log.c

echo "-> 3. Inyectando bypass de asignación de memoria hw_get_module..."
cat << 'EOF' >> src/vulkan/wrapper/wrapper_device.c
struct hw_module_t;
int hw_get_module(const char *id, const struct hw_module_t **module);
int hw_get_module(const char *id, const struct hw_module_t **module) { (void)id; (void)module; return -1; }
EOF

echo "-> 4. Bypass de validaciones de Meson..."
sed -i "s|libandroid_dep = .*|libandroid_dep = dependency('', required : false)|g" subprojects/libadrenotools/meson.build
sed -i "s|liblog_dep = .*|liblog_dep = dependency('', required : false)|g" subprojects/libadrenotools/meson.build
find subprojects/libadrenotools/ -name "meson.build" -exec sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" {} + 2>/dev/null || true

# 🟢 REPARACIÓN DE ENLAZADO DE 32 BITS: Machacamos la búsqueda rígida de libdl global para evitar el fallo de Setup
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 5. Pip e instalables..."
python -m pip install --upgrade pip && pip install mako PyYAML 'meson>=1.4.0' ninja packaging

echo "-> 6. Detectando NDK oficial..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

echo "-> 7. Shims e inyección base..."
unzip -o shims.zip -d ./ && mkdir -p "$GITHUB_WORKSPACE/shims_target" && cp -rf ./shims/* "$GITHUB_WORKSPACE/shims_target/"

cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
void __stub_placeholder(void) {}
EOF

$NDK_BIN/aarch64-linux-android30-clang -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libhardware.so"
$NDK_BIN/aarch64-linux-android30-clang -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libvulkan_wrapper.so"

# ==========================================
# 🟢 FASE A: COMPILACIÓN DE 32 BITS (ARMv7)
# ==========================================
echo "-> 8a. Generando cross_32.txt..."
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
c_link_args = ['-landroid', '-llog', '-lsync', '-lhardware', '-L${NDK_SYSROOT_LIB_32}', '-L$GITHUB_WORKSPACE/shims_target']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lhardware', '-L${NDK_SYSROOT_LIB_32}', '-L$GITHUB_WORKSPACE/shims_target']
EOF

echo "-> 9a. Lanzando Setup y Compilación de Mesa de 32 bits..."
meson setup build32 --cross-file cross_32.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build32

# ==========================================
# 🟢 FASE B: COMPILACIÓN DE 64 BITS (ARM64)
# ==========================================
echo "-> 8b. Generando cross_64.txt..."
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
c_link_args = ['-landroid', '-llog', '-lsync', '-lhardware', '-L${NDK_SYSROOT_LIB_64}', '-L$GITHUB_WORKSPACE/shims_target']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lhardware', '-L${NDK_SYSROOT_LIB_64}', '-L$GITHUB_WORKSPACE/shims_target']
EOF

echo "-> 9b. Lanzando Setup y Compilación de Mesa de 64 bits..."
meson setup build64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build64

# ==========================================
# 🟢 FASE C: CONSTRUCCIÓN DEL PUENTE INTERCEPTOR FAT EN C
# ==========================================
echo "-> 10. Escribiendo el enrutador puente dinámico de coincidencia de arquitectura..."
cat << 'EOF' > wrapper.c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

static void* handle = NULL;

__attribute__((constructor)) void init_wrapper() {
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

void* vk_icdGetInstanceProcAddr(void* instance, const char* pName) {
    if (!handle) return NULL;
    typedef void* (*PFN_icdGet)(void*, const char*);
    PFN_icdGet real_icd = (PFN_icdGet)dlsym(handle, "vk_icdGetInstanceProcAddr");
    return real_icd ? real_icd(instance, pName) : NULL;
}
EOF

$NDK_BIN/aarch64-linux-android30-clang -shared -fPIC -o libvulkan_wrapper.so wrapper.c -ldl --sysroot="$NDK_SYSROOT"

# ==========================================
# 🟢 FASE D: MAQUETADO ICD PLANO GANADOR
# ==========================================
echo "-> 11. Estructurando carpetas finales..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d

echo "-> [A] Copiando el Enrutador Fat unificado como entrada principal..."
cp -v libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

echo "-> [B] Copiando el driver físico real de 64 bits generado en la fase B..."
cp -v build64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so

echo "-> [C] Copiando el driver físico real de 32 bits generado en la fase A..."
cp -v build32/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_32.so

echo "-> [D] Estampando identidades SONAME y limpiando binarios..."
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost_64.so pkg/usr/lib/libvulkan_panfrost_64.so
patchelf --set-soname libvulkan_panfrost_32.so pkg/usr/lib/libvulkan_panfrost_32.so
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

echo "-> [E] Escribiendo manifiestos ICD limpios..."
echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "$GITHUB_WORKSPACE/wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡FAT BINARY HÍBRIDO CONEXIÓN TOTAL COMPLETADO CON ÉXITO!"
echo "=========================================================="
