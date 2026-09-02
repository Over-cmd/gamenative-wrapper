#!/bin/bash
set -e

echo "-> [Docker Internal] Preparando directorios para stubs primarios..."
mkdir -p shims_64/lib

echo "-> [Docker Internal] Purgando directorios previos de construcción..."
rm -rf build-libdrm/ build-64/

echo "-> [Docker Internal] Instalando dependencias de Python complementarias..."
pip3 install --no-cache-dir --break-system-packages mako packaging || pip3 install --no-cache-dir mako packaging || true

export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
NDK_SYSROOT_LIB_64="${NDK_SYSROOT}/usr/lib/aarch64-linux-android/26"

echo "-> [Docker Internal] Compilando stubs duales legítivos para enlazado preferencial..."
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_c.o
$NDK_BIN/llvm-ar rcs shims_64/lib/liblog.a stub_c.o
$NDK_BIN/shims_64/libvulkan_wrapper.a stub_c.o 2>/dev/null || $NDK_BIN/llvm-ar rcs shims_64/libvulkan_wrapper.a stub_c.o

$NDK_BIN/aarch64-linux-android26-clang++ -c stub_logs.c -o stub_cpp.o
$NDK_BIN/llvm-ar rcs shims_64/lib/libandroid.a stub_cpp.o
$NDK_BIN/llvm-ar rcs shims_64/lib/libdl.a stub_cpp.o

cp -fv shims_64/lib/libandroid.a "$NDK_SYSROOT_LIB_64/libandroid.a" 2>/dev/null || true
cp -fv shims_64/lib/liblog.a "$NDK_SYSROOT_LIB_64/liblog.a" 2>/dev/null || true
cp -fv shims_64/lib/libdl.a "$NDK_SYSROOT_LIB_64/libdl.a" 2>/dev/null || true

python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    if "fcntl.h" not in c:
        c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
        f=open(p,"w"); f.write(c); f.close()
'

# 🟢 REPARACIÓN CRÍTICA EN CALIENTE INTERNAL: Aplicamos las elisiones de find_library directamente aquí dentro de la jaula virtual de Docker. No hay retraso de disco ni bloqueo de permisos que pueda esquivar este comando síncrono antes del setup
echo "-> [Docker Internal] Aplicando parches sintácticos atómicos in-situ..."
if [ -f "meson.build" ]; then
    sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build
    sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build
    sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build
    sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build
fi

if [ -d "subprojects/libadrenotools" ]; then
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/cc.find_library('android'/dependency('', required : false) #/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/cc.find_library("android"/dependency("", required : false) #/g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/cc.find_library('log'/dependency('', required : false) #/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/cc.find_library("log"/dependency("", required : false) #/g' {} +
fi

# Compilación de libdrm en su prefijo aislado
python3 meson_src/meson.py setup build-libdrm libdrm_android --cross-file /workspace/cross_libdrm.txt --prefix="/workspace/shims_64" \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false
python3 meson_src/meson.py install -C build-libdrm

# Compilación del Core de Mesa 25 leyendo las fuentes locales ya purificadas
python3 meson_src/meson.py setup build-64 --cross-file /workspace/cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper
python3 meson_src/meson.py compile -C build-64
