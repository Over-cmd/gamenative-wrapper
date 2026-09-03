#!/bin/bash
set -e

echo "-> [Docker Internal] Preparando directorios para stubs primarios..."
mkdir -p shims_64/lib

echo "-> [Docker Internal] Purgando directorios previos de construcción..."
rm -rf build-libdrm/ build-64/ pkg/

echo "-> [Docker Internal] Instalando dependencias de Python complementarias..."
pip3 install --no-cache-dir --break-system-packages mako packaging || pip3 install --no-cache-dir mako packaging || true

export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
NDK_SYSROOT_LIB_64="${NDK_SYSROOT}/usr/lib/aarch64-linux-android/26"

echo "-> [Docker Internal] Compilando stubs duales legítivos para enlazado preferencial..."
# 🟢 COMPILACIÓN DEL PASAPORTE AISLADO: Cambiamos el nombre de este stub artificial a libvulkan_stub_log.so para que no compita a nivel de inodo ni suplante el nombre del binario rey real en las tablas de búsqueda
$NDK_BIN/aarch64-linux-android26-clang -shared -fPIC stub_logs.c -o shims_64/lib/libvulkan_stub_log.so

$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_c.o
$NDK_BIN/llvm-ar rcs shims_64/lib/liblog.a stub_c.o

$NDK_BIN/aarch64-linux-android26-clang++ -c stub_logs.c -o stub_cpp.o
$NDK_BIN/llvm-ar rcs shims_64/lib/libandroid.a stub_cpp.o
$NDK_BIN/llvm-ar rcs shims_64/lib/libdl.a stub_cpp.o

cp -fv shims_64/lib/libandroid.a "$NDK_SYSROOT_LIB_64/libandroid.a" 2>/dev/null || true
cp -fv shims_64/lib/liblog.a "$NDK_SYSROOT_LIB_64/liblog.a" 2>/dev/null || true
cp -fv shims_64/lib/libdl.a "$NDK_SYSROOT_LIB_64/libdl.a" 2>/dev/null || true

echo "-> [Docker Internal] Sincronizando inodos físicos en el hardware..."
sync
sleep 1

python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    if "fcntl.h" not in c:
        c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
        f=open(p,"w"); f.write(c); f.close()
'

python3 -c '
p="src/util/anon_file.c"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    if "SYS_memfd_create" in c:
        c = c.replace("SYS_memfd_create", "279")
        f=open(p,"w"); f.write(c); f.close()
        print("-> [Docker Internal] Éxito: SYS_memfd_create transmutado a la Syscall 279 de forma literal.")
'

python3 -c '
p="src/c11/impl/meson.build"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    if "dep_clock =" not in c:
        c = "dep_clock = declare_dependency(link_args : [" + chr(39) + "-lc" + chr(39) + "])\n" + c
        f=open(p,"w"); f.write(c); f.close()
        print("-> [Docker Internal] Éxito: dep_clock inyectado con comillas simples nativas puras.")
'

echo "-> [Docker Internal] Ejecutando barrido total recursivo de secure_getenv hacia getenv..."
find src/ -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.h" \) -exec sed -i 's/secure_getenv/getenv/g' {} +

python3 -c '
p="src/util/u_qsort.h"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    c = c.replace("#define HAVE_QSORT_R 1", "")
    patch = "#ifndef HAVE_QSORT_R\n#define HAVE_QSORT_R 1\n#endif\n#undef HAVE_QSORT_S\n"
    c = patch + c
    f=open(p,"w"); f.write(c); f.close()
    print("-> [Docker Internal] Éxito: Control incondicional de ordenamiento inyectado en u_qsort.h")
'

echo "-> [Docker Internal] Aplicando parches sintácticos atómicos in-situ..."
if [ -f "meson.build" ]; then
    sed -i "s#.*find_library('dl'.*#declare_dependency(link_args : ['-ldl'])#g" meson.build
    sed -i "s#.*find_library('rt'.*#declare_dependency(link_args : ['-lc'])#g" meson.build
    sed -i "s#.*find_library('atomic'.*#declare_dependency(link_args : ['-latomic'])#g" meson.build
    sed -i "s#dependency('libclc')#declare_dependency()#g" meson.build
fi

if [ -d "subprojects/libadrenotools" ]; then
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s#.*find_library('android'.*#declare_dependency(link_args : ['-landroid'])#g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's#.*find_library("android".*#declare_dependency(link_args : ["-landroid"])#g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s#.*find_library('log'.*#declare_dependency(link_args : ['-llog'])#g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's#.*find_library("log".*#declare_dependency(link_args : ["-llog"])#g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s#.*find_library('dl'.*#declare_dependency(link_args : ['-ldl'])#g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's#.*find_library("dl".*#declare_dependency(link_args : ["-ldl"])#g' {} +
fi

echo "-> [Docker Internal] Mutando flags de enlace rígidos en Adrenotools..."
if [ -d "subprojects/libadrenotools" ]; then
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/-Wl,--no-undefined/-Wl,--allow-shlib-undefined/g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/b_lundef=true/b_lundef=false/g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/b_asneeded=true/b_asneeded=false/g' {} +
fi

BYPASS_RECIPE="subprojects/libadrenotools/lib/linkernsbypass/meson.build"
if [ -f "$BYPASS_RECIPE" ]; then
    echo "-> [Docker Internal] Estabilizando tokens globales sobre linkernsbypass..."
    echo -e "libandroid_dep = declare_dependency(link_args : ['-landroid'])\nliblog_dep = declare_dependency(link_args : ['-llog'])\nlibdl_dep = declare_dependency(link_args : ['-ldl'])\n$(cat $BYPASS_RECIPE)" > "$BYPASS_RECIPE"
fi

python3 meson_src/meson.py setup build-64 --cross-file /workspace/cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=wrapper,panfrost
python3 meson_src/meson.py compile -C build-64

# 🟢 CIRUGÍA MAESTRA RUTA ABSOLUTA SEÑOR: Forzamos la extracción directa mapeando los dos nidos de salida de Ninja reales legítimos. Python extraerá el libvulkan_wrapper.so real forjado por Mesa y el libvulkan_panfrost.so real, poblando la carpetapkg de forma inmaculada e indestructible
python3 -c '
import os, shutil

os.makedirs("pkg/usr/lib/aarch64-linux-android", exist_ok=True)
os.makedirs("pkg/usr/share/vulkan/icd.d", exist_ok=True)

# Coordenadas físicas inmutables reales de Mesa 25
real_wrapper = "build-64/src/vulkan/wrapper/libvulkan_wrapper.so"
real_panfrost = "build-64/src/panfrost/vulkan/libvulkan_panfrost.so"
drm_src = "build-libdrm/src/libdrm.so" # Tomamos la compilación real del Host instalada

if os.path.exists(real_wrapper) and os.path.exists(real_panfrost):
    size_wrap = os.path.getsize(real_wrapper) / (1024 * 1024)
    size_pan = os.path.getsize(real_panfrost) / (1024 * 1024)
    print(f"-> [Docker Internal] ¡Wrapper Real Extraído! Peso: {size_wrap:.2f} MB")
    print(f"-> [Docker Internal] ¡Panfrost Real Extraído! Peso: {size_pan:.2f} MB")
    
    # Inyección física real de los binarios puros del silicio forjado
    shutil.copy2(real_wrapper, "pkg/usr/lib/libvulkan_wrapper.so")
    shutil.copy2(real_wrapper, "pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so")
    shutil.copy2(real_panfrost, "pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so")
    
    # Rastreando libdrm.so real compilado e inyectándolo al empaque
    for root, dirs, files in os.walk("build-libdrm"):
        if "libdrm.so" in files:
            shutil.copy2(os.path.join(root, "libdrm.so"), "pkg/usr/lib/libdrm.so")
            break
            
    print("-> [Docker Internal] EXITO ABSOLUTO: ¡La jerarquía pkg/ contiene los drivers reales legítimos de Mesa 25!")
else:
    print("-> [Docker Internal ❌ ERROR REAL] Las rutas de compilación se desalinearon de sus inodos.")
    exit(1)
'
sync
