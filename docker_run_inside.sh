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
$NDK_BIN/llvm-ar rcs shims_64/lib/libvulkan_wrapper.a stub_c.o

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

# 🟢 REPARACIÓN CRÍTICA DISK_CACHE: Redirigimos la llamada secure_getenv hacia la función estándar getenv() de la biblioteca bionic para la API 26 mediante una macro en la cabecera. Esto elude la ausencia de la función sin romper la integridad del mapa de memoria de Mesa 25
python3 -c '
p="src/util/disk_cache_os.c"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    if "secure_getenv" in c and "getenv" not in c.split("\n")[0]:
        patch = "#ifdef __ANDROID__\n#define secure_getenv getenv\n#endif\n"
        c = patch + c
        f=open(p,"w"); f.write(c); f.close()
        print("-> [Docker Internal] Éxito: secure_getenv mapeado hacia getenv en disk_cache_os.c")
'

echo "-> [Docker Internal] Aplicando parches sintácticos atómicos in-situ..."
if [ -f "meson.build" ]; then
    sed -i "s/.*find_library('dl'.*/declare_dependency(link_args : ['-ldl'])/g" meson.build
    sed -i "s/.*find_library('rt'.*/declare_dependency(link_args : ['-lc'])/g" meson.build
    sed -i "s/.*find_library('atomic'.*/declare_dependency(link_args : ['-latomic'])/g" meson.build
    sed -i "s/dependency('libclc')/declare_dependency()/g" meson.build
fi

if [ -d "subprojects/libadrenotools" ]; then
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/.*find_library('android'.*/declare_dependency(link_args : ['-landroid'])/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/.*find_library("android".*/declare_dependency(link_args : ["-landroid"])/g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/.*find_library('log'.*/declare_dependency(link_args : ['-llog'])/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/.*find_library("log".*/declare_dependency(link_args : ["-llog"])/g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/.*find_library('dl'.*/declare_dependency(link_args : ['-ldl'])/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/.*find_library("dl".*/declare_dependency(link_args : ["-ldl"])/g' {} +
fi

# Inicializamos formalmente las variables de linkernsbypass apuntando a los objetos de enlace real estructurados
BYPASS_RECIPE="subprojects/libadrenotools/lib/linkernsbypass/meson.build"
if [ -f "$BYPASS_RECIPE" ]; then
    echo "-> [Docker Internal] Estabilizando tokens globales sobre linkernsbypass..."
    echo -e "libandroid_dep = declare_dependency(link_args : ['-landroid'])\nliblog_dep = declare_dependency(link_args : ['-llog'])\nlibdl_dep = declare_dependency(link_args : ['-ldl'])\n$(cat $BYPASS_RECIPE)" > "$BYPASS_RECIPE"
fi

# Compilación de libdrm en su prefijo aislado
python3 meson_src/meson.py setup build-libdrm libdrm_android --cross-file /workspace/cross_libdrm.txt --prefix="/workspace/shims_64" \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false
python3 meson_src/meson.py install -C build-libdrm

# Compilación del Core de Mesa 25 con las banderas de enlazado de sistema re-acopladas de forma impecable
python3 meson_src/meson.py setup build-64 --cross-file /workspace/cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper
python3 meson_src/meson.py compile -C build-64
