#!/bin/bash
set -e

echo "-> 1. Submódulos de Pipetto..."
cd subprojects/libadrenotools && git submodule update --init --recursive && cd ../..

echo "-> 2. Parches de hardware Mali-G52..."
sed -i 's/fd = syscall(SYS_memfd_create.*/fd = memfd_create(debug_name, MFD_CLOEXEC \| MFD_ALLOW_SEALING);/g' src/util/anon_file.c 2>/dev/null || true
sed -i '1s|^|static int sync_wait(int fd, int timeout) { return 0; }\n|' src/panfrost/lib/kmod/panthor_kmod.c

echo "-> 2b. 🟢 REPARACIÓN DE LECTURA DE LOGS: Inyectando cabecera fcntl.h en el wrapper_log de Pipetto..."
sed -i '1s|^|#include <fcntl.h>\n|' src/vulkan/wrapper/wrapper_log.c

echo "-> 3. Prototipos Públicos en Panfrost (Evita -Werror)..."
cat << 'EOF' >> src/panfrost/vulkan/panvk_android.c
#include <stdarg.h>
__attribute__((visibility("default"))) int get_wrapper_log_level(const char *opt);
__attribute__((visibility("default"))) void write_to_logfile(const char *f, const char *l, ...);
__attribute__((visibility("default"))) int get_wrapper_log_level(const char *opt) { (void)opt; return 0; }
__attribute__((visibility("default"))) void write_to_logfile(const char *f, const char *l, ...) { (void)f; (void)l; }
EOF

echo "-> 4. Bypass de validaciones de Meson y libclc..."
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

echo "-> 7. Shims e inyección ARM64..."
unzip -o shims.zip -d ./ && mkdir -p "$GITHUB_WORKSPACE/shims_target" && cp -rf ./shims/* "$GITHUB_WORKSPACE/shims_target/"
echo "void __stub(void) {}" > simple_stub.c
$CLANG_CROSS -shared -fPIC simple_stub.c -o "$GITHUB_WORKSPACE/shims_target/libhardware.so"
$CLANG_CROSS -shared -fPIC simple_stub.c -o "$GITHUB_WORKSPACE/shims_target/libvulkan_wrapper.so"

echo "-> 8. Generando cross.txt unificado..."
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

echo "-> 9. Compilación en dos fases (Bypass circular)..."
meson setup build --cross-file cross.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper
ninja -C build src/vulkan/wrapper/libvulkan_wrapper.so
cp -fv build/src/vulkan/wrapper/libvulkan_wrapper.so "$GITHUB_WORKSPACE/shims_target/libvulkan_wrapper.so"
meson compile -C build

echo "-> 10. Estructura ICD final y renombrado con patchelf..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d pkg/usr/share/vulkan/settings.d
cp -v build/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

echo '{"ICD": {"api_version": "1.4.352", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"env":{"PAN_I_WANT_A_BROKEN_VULKAN_DRIVER":"1","MESA_VK_IGNORE_CONFORMANCE_WARNING":"1","PANVK_DEBUG":"sync,nir","MESA_VK_FORCE_BLIT":"1","MESA_LOADER_DRIVER_OVERRIDE":"panfrost","GALLIUM_DRIVER":"panfrost"}}' > pkg/usr/share/vulkan/settings.d/wrapper_settings.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "$GITHUB_WORKSPACE/wrapper.tzst" usr version.txt
echo "🟢 COMPILACIÓN EXITOSA CON SONAME EN ARM64"
