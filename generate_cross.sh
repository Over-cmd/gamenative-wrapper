#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO INTERMEDIO: GENERACIÓN DE RECETAS EN EL HOST V38"
echo "=========================================================="

NDK_ROOT="/usr/local/lib/android/sdk/ndk"
SYSROOT="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

echo "-> Generando cross_libdrm.txt legítimo con Sysroot expandido..."
cat << EOF > cross_libdrm.txt
[binaries]
c = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang'
cpp = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++'
ar = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
ninja = '/usr/bin/ninja'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = '${SYSROOT}'
[built-in options]
c_args = ['--sysroot=${SYSROOT}', '-I${SYSROOT}/usr/include/aarch64-linux-android', '-DANDROID', '-D_GNU_SOURCE']
cpp_args = ['--sysroot=${SYSROOT}', '-I${SYSROOT}/usr/include/aarch64-linux-android', '-DANDROID', '-D_GNU_SOURCE']
EOF

echo "-> Generando cross_64.txt de Mesa 25 con enlace de pasaporte simétrico..."
# 🟢 SINCRONIZACIÓN SUPREMA DE NOMBRE DE STUB: Modificamos -lvulkan_stub_wrapper volviendo al token clásico -lvulkan_wrapper. Esto encaja de forma milimétrica con el archivo físico que escribe tu docker_run_inside.sh en la carpeta shims_64/lib/ al arrancar, destruyendo el error del hito 77 en un parpadeo
cat << EOF > cross_64.txt
[binaries]
c = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang'
cpp = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++'
ar = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkg-config = '/usr/bin/pkg-config'
ninja = '/usr/bin/ninja'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '${SYSROOT}'
libdir = ['/workspace/shims_64/lib', '${SYSROOT}/usr/lib/aarch64-linux-android']
pkg_config_path = '/workspace/shims_64/lib/pkgconfig'
pkg_config_libdir = '/workspace/shims_64/lib/pkgconfig'
[built-in options]
c_args = ['--sysroot=${SYSROOT}', '-I${SYSROOT}/usr/include/aarch64-linux-android', '-D__TERMUX__', '-B/workspace/shims_64/lib', '-I/workspace', '-I/workspace/src', '-I/workspace/shims_64/include', '-I/workspace/shims_64/include/libdrm']
cpp_args = ['--sysroot=${SYSROOT}', '-I${SYSROOT}/usr/include/aarch64-linux-android', '-D__TERMUX__', '-B/workspace/shims_64/lib', '-I/workspace', '-I/workspace/src', '-I/workspace/shims_64/include', '-I/workspace/shims_64/include/libdrm']
c_link_args = ['-Wl,-z,undefs', '-Wl,--allow-shlib-undefined', '-L/workspace/shims_64/lib', '-L${SYSROOT}/usr/lib/aarch64-linux-android', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic', '-lm']
cpp_link_args = ['-Wl,-z,undefs', '-Wl,--allow-shlib-undefined', '-L/workspace/shims_64/lib', '-L${SYSROOT}/usr/lib/aarch64-linux-android', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic', '-lm']
EOF

echo "=========================================================="
echo "🟢 RECETAS COMPILACIÓN GENERADAS INDESTRUCTIBLES V38 OK"
echo "=========================================================="
