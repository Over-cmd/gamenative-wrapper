#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO INTERMEDIO: GENERACIÓN DE RECETAS EN EL HOST V36"
echo "=========================================================="

# Constantes absolutas de inodos del NDK r28 en los runners de GitHub
NDK_ROOT="/usr/local/lib/android/sdk/ndk/28.2.13676358"
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

echo "-> Generando cross_64.txt biónico libre de candados con cabeceras de arquitectura unificadas..."
# 🟢 BLINDAJE ATÓMICO DE COMPILACIÓN CRUZADA: Inyectamos los paths de inclusión de la arquitectura cruzada aarch64-linux-android y las librerías del API 26 directas en los argumentos. Esto permite que Clang valide las librerías matemáticas base, forzando a Meson a activar pkg-config de forma incondicional sobre /workspace/shims_64/ para absorber libdrm en el acto
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
libdir = ['/workspace/shims_64/lib', '${SYSROOT}/usr/lib/aarch64-linux-android/26']
pkg_config_path = '/workspace/shims_64/lib/pkgconfig'
pkg_config_libdir = '/workspace/shims_64/lib/pkgconfig'
[built-in options]
c_args = ['--sysroot=${SYSROOT}', '-I${SYSROOT}/usr/include/aarch64-linux-android', '-D__TERMUX__', '-B/workspace/shims_64/lib', '-I/workspace', '-I/workspace/src', '-I/workspace/shims_64/include', '-I/workspace/shims_64/include/libdrm']
cpp_args = ['--sysroot=${SYSROOT}', '-I${SYSROOT}/usr/include/aarch64-linux-android', '-D__TERMUX__', '-B/workspace/shims_64/lib', '-I/workspace', '-I/workspace/src', '-I/workspace/shims_64/include', '-I/workspace/shims_64/include/libdrm']
c_link_args = ['-Wl,-z,undefs', '-Wl,--allow-shlib-undefined', '-L/workspace/shims_64/lib', '-L${SYSROOT}/usr/lib/aarch64-linux-android/26', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_stub_wrapper', '-latomic', '-lm']
cpp_link_args = ['-Wl,-z,undefs', '-Wl,--allow-shlib-undefined', '-L/workspace/shims_64/lib', '-L${SYSROOT}/usr/lib/aarch64-linux-android/26', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_stub_wrapper', '-latomic', '-lm']
EOF

echo "=========================================================="
echo "🟢 RECETAS COMPILACIÓN GENERADAS INDESTRUCTIBLES V36 OK"
echo "=========================================================="
