#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO INTERMEDIO: GENERACIÓN DE RECETAS EN EL HOST"
echo "=========================================================="

echo "-> Generando cross_libdrm.txt..."
cat << EOF > cross_libdrm.txt
[binaries]
c = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang'
cpp = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++'
ar = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
ninja = '/usr/bin/ninja'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot'
[built-in options]
c_args = ['--sysroot=/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot', '-DANDROID', '-D_GNU_SOURCE']
EOF

echo "-> Generando cross_64.txt de Mesa 25..."
cat << EOF > cross_64.txt
[constants]
shims_path = '/workspace/shims_64'
mesa_root = '/workspace'
[binaries]
c = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang'
cpp = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++'
ar = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkg-config = '/usr/bin/pkg-config'
ninja = '/usr/bin/ninja'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot'
libdir = '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26'
pkg_config_path = shims_path + '/lib/pkgconfig'
pkg_config_libdir = shims_path + '/lib/pkgconfig'
# 🟢 CORRECCIÓN SUPREMA DE INFRAESTRUCTURA: Inyectamos el path nativo /workspace/include a nivel de constantes de Clang para saciar la variable inc_include sin tocar un solo archivo de Git ni provocar bloqueos de root
[built-in options]
c_args = ['--sysroot=/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot', '-D__TERMUX__', '-I' + shims_path + '/include', '-I' + shims_path + '/include/libdrm', '-I' + mesa_root + '/include']
cpp_args = ['--sysroot=/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot', '-D__TERMUX__', '-I' + shims_path + '/include', '-I' + shims_path + '/include/libdrm', '-I' + mesa_root + '/include']
c_link_args = ['-L' + shims_path + '/lib', '-L/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
cpp_link_args = ['-L' + shims_path + '/lib', '-L/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
EOF

echo "=========================================================="
echo "🟢 RECETAS COMPILACIÓN GENERADAS INDESTRUCTIBLES"
echo "=========================================================="
