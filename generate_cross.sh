#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO INTERMEDIO: GENERACIÓN DE RECETAS EN EL HOST V39"
echo "=========================================================="

# 🟢 REPARACIÓN DINÁMICA DE RUTA REAL NDK: Usamos find para localizar la coordenada física exacta de la versión de desarrollo del NDK r28 en el Host de las Actions. Esto inyectará el número de compilación legítimo (/28.2.13676358) dentro de los cross-files, pulverizando el error de "No such file or directory" de raíz
NDK_BASE_SEARCH="/usr/local/lib/android/sdk/ndk"
NDK_ROOT=$(find "$NDK_BASE_SEARCH" -maxdepth 1 -type d -name "28.*" | head -n 1 || echo "")

if [ -z "$NDK_ROOT" ] || [ ! -d "$NDK_ROOT" ]; then
    echo "-> [⚠️ ERROR CRÍTICO] No se localizó ninguna instalación real del NDK r28 en $NDK_BASE_SEARCH"
    exit 1
fi

SYSROOT="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
echo "-> [OK] Inyectando NDK de silicio detectado en: $NDK_ROOT"

echo "-> Generando cross_libdrm.txt legítimo..."
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
echo "🟢 RECETAS COMPILACIÓN GENERADAS INDESTRUCTIBLES V39 OK"
echo "=========================================================="
