#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO INTERMEDIO: GENERACIÓN DE RECETAS EN EL HOST V34"
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

echo "-> Generando cross_64.txt de Mesa 25 con elusión incondicional de indefinidos..."
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
libdir = ['/workspace/shims_64/lib', '/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android']
pkg_config_path = shims_path + '/lib/pkgconfig'
pkg_config_libdir = shims_path + '/lib/pkgconfig'
[built-in options]
c_args = ['--sysroot=/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot', '-D__TERMUX__', '-B' + shims_path + '/lib', '-I' + mesa_root, '-I' + mesa_root + '/src', '-I' + shims_path + '/include', '-I' + shims_path + '/include/libdrm']
cpp_args = ['--sysroot=/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot', '-D__TERMUX__', '-B' + shims_path + '/lib', '-I' + mesa_root, '-I' + mesa_root + '/src', '-I' + shims_path + '/include', '-I' + shims_path + '/include/libdrm']
c_link_args = ['-Wl,-z,undefs', '-Wl,--allow-shlib-undefined', '-L' + shims_path + '/lib', '-L/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
cpp_link_args = ['-Wl,-z,undefs', '-Wl,--allow-shlib-undefined', '-L' + shims_path + '/lib', '-L/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
EOF

echo "=========================================================="
echo "🟢 RECETAS COMPILACIÓN GENERADAS INDESTRUCTIBLES"
echo "=========================================================="
