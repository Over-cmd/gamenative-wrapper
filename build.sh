#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR HÍBRIDO FAT BASADO EN TOML OFICIAL"
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
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 5. Pip e instalables..."
python -m pip install --upgrade pip && pip install mako PyYAML 'meson>=1.4.0' ninja packaging

echo "-> 6. Detectando NDK oficial..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"

# ==========================================
# 🟢 FASE A: COMPILACIÓN DE 32 BITS (Fiel al plano oficial)
# ==========================================
echo "-> 7a. Generando cross_32.txt..."
cat << EOF > cross_32.txt
[constants]
ndk_path = '${ANDROID_NDK_HOME}'
toolchain = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/bin'
api = '24'

[binaries]
c       = toolchain + '/armv7a-linux-androideabi' + api + '-clang'
cpp     = toolchain + '/armv7a-linux-androideabi' + api + '-clang++'
ar      = toolchain + '/llvm-ar'
strip   = toolchain + '/llvm-strip'
pkgconfig = 'false'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7a'
endian = 'little'
EOF

echo "-> 8a. Lanzando Setup y Compilación de Mesa de 32 bits..."
meson setup build-32 --cross-file cross_32.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-32

# ==========================================
# 🟢 FASE B: COMPILACIÓN DE 64 BITS (ARM64)
# ==========================================
echo "-> 7b. Generando cross_64.txt..."
cat << EOF > cross_64.txt
[constants]
ndk_path = '${ANDROID_NDK_HOME}'
toolchain = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/bin'
api = '24'

[binaries]
c       = toolchain + '/aarch64-linux-android' + api + '-clang'
cpp     = toolchain + '/aarch64-linux-android' + api + '-clang++'
ar      = toolchain + '/llvm-ar'
strip   = toolchain + '/llvm-strip'
pkgconfig = 'false'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

echo "-> 8b. Lanzando Setup y Compilación de Mesa de 64 bits..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-64

# ==========================================
# 🟢 FASE C: CONSTRUCCIÓN DEL PUENTE INTERCEPTOR FAT EN C
# ==========================================
echo "-> 9. Escribiendo el enrutador puente dinámico del Dockerfile..."
cat << 'EOF' > wrapper.c
#define _GNU_SOURCE
#include <stdio;h>
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

# Compilamos el enrutador puente con el Clang del NDK para asegurar firmas biónicas compatibles
$NDK_BIN/aarch64-linux-android24-clang -shared -fPIC -o libvulkan_wrapper.so wrapper.c -ldl --sysroot="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# ==========================================
# 🟢 FASE D: MAQUETADO ICD PLANO DEFINITIVO
# ==========================================
echo "-> 10. Estructurando carpetas finales..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d

echo "-> [A] Copiando el Enrutador Fat unificado como entrada principal..."
cp -v libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

echo "-> [B] Copiando el driver físico real de 64 bits generado en la fase B..."
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so

echo "-> [C] Copiando el driver físico real de 32 bits generado en la fase A..."
cp -v build-32/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_32.so

echo "-> [D] Estampando identidades SONAME y aplicando strip..."
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
echo "🟢 ¡FAT BINARY MONOLÍTICO SEGUIDO AL PLANO OFICIAL COMPLETADO!"
echo "=========================================================="
