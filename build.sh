#!/bin/bash
set -e

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

echo "-> 4. Bypass de validaciones rígidas de Meson..."
sed -i "s|libandroid_dep = .*|libandroid_dep = dependency('', required : false)|g" subprojects/libadrenotools/meson.build
sed -i "s|liblog_dep = .*|liblog_dep = dependency('', required : false)|g" subprojects/libadrenotools/meson.build
find subprojects/libadrenotools/ -name "meson.build" -exec sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" {} + 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 5. Pip e instalables..."
python -m pip install --upgrade pip && pip install mako PyYAML 'meson>=1.4.0' ninja packaging

echo "-> 6. Configurando entorno NDK r28 oficial de GitHub..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
NDK_SYSROOT_LIB="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/30"
export CLANG_CROSS="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang"
export LLVM_AR="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"

echo "-> 7. Shims e inyección de Librerías Estáticas ARM64 Legítimas..."
unzip -o shims.zip -d ./ && mkdir -p "$GITHUB_WORKSPACE/shims_target" && cp -rf ./shims/* "$GITHUB_WORKSPACE/shims_target/"

cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
void __stub_placeholder(void) {}
EOF

$CLANG_CROSS -c stub_logs.c -o stub_logs.o
$LLVM_AR rcs "$GITHUB_WORKSPACE/shims_target/libvulkan_wrapper.a" stub_logs.o
$CLANG_CROSS -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libhardware.so"
$CLANG_CROSS -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libcutils.so"
$CLANG_CROSS -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libnativewindow.so"
$CLANG_CROSS -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libsync.so"
$CLANG_CROSS -shared -fPIC stub_logs.c -o "$GITHUB_WORKSPACE/shims_target/libvulkan_wrapper.so"

echo "-> 8. Generando cross.txt unificado nativo de 64-Bits..."
cat << EOF > cross.txt
[constants]
ndk_bin = '${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin'
ndk_sysroot = '${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot'
[binaries]
c = [ndk_bin / 'clang', '-target', 'aarch64-linux-android30', '-D__TERMUX__']
cpp = [ndk_bin / 'clang++', '-target', 'aarch64-linux-android30', '-fno-exceptions', '--start-no-unused-arguments', '--end-no-unused-arguments', '-D__TERMUX__']
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
libdir = '${NDK_SYSROOT_LIB}'
pkg_config_path = '$GITHUB_WORKSPACE/shims_target'
pkg_config_libdir = '$GITHUB_WORKSPACE/shims_target'
[built-in options]
c_args = ['--sysroot=' + ndk_sysroot, '-I$GITHUB_WORKSPACE/shims_target/include', '-Wl,-llog', '-Wl,-lsync']
cpp_args = ['--sysroot=' + ndk_sysroot, '-I$GITHUB_WORKSPACE/shims_target/include', '-Wl,-llog', '-Wl,-lsync']
c_link_args = ['-landroid', '-llog', '-lsync', '-lhardware', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB}', '-L$GITHUB_WORKSPACE/shims_target']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lhardware', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB}', '-L$GITHUB_WORKSPACE/shims_target']
EOF

echo "-> 9. Lanzando inicialización de Meson Setup..."
meson setup build --cross-file cross.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper

echo "-> 10. Compilando el motor gráfico con Ninja..."
meson compile -C build

# ==========================================
# 🟢 11. ENRUTADOR PUENTE CON INYECCIÓN DE ENTORNO EN CALIENTE (HARDCODED)
# ==========================================
echo "-> 11. Fabricando el código fuente del enrutador con variables de entorno forzadas..."
cat << 'EOF' > wrapper.c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

static void* handle = NULL;

__attribute__((constructor)) void init_wrapper() {
    // Forzar la inyección de variables de entorno de Mesa directamente en la memoria del hilo de ejecución
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

$CLANG_CROSS -shared -fPIC -o libvulkan_wrapper.so wrapper.c -ldl --sysroot="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

echo "-> 12. Estructurando empaque compatible ICD para Bannerlator..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d pkg/usr/share/vulkan/settings.d

cp -v libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
cp -v build/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so
cp -v build/src/vulkan/wrapper/libvulkan_wrapper.so pkg/usr/lib/libvulkan_panfrost_32.so

patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost_64.so pkg/usr/lib/libvulkan_panfrost_64.so
llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "$GITHUB_WORKSPACE/wrapper.tzst" usr version.txt
echo "=========================================================="
echo "🟢 ECOSYSTEMA COMPLETO CONFIGURADO CON ÉXITO PARA BANNERLATOR"
echo "=========================================================="
