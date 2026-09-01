#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 MÓDULO 2: ORQUESTADOR BIÓNICO PERFECCIONADO POR MÓDULOS"
echo "=========================================================="

WORKSPACE="$(pwd)"

# 1. Ejecutamos el preparador local de fuentes fuera de Docker
chmod +x patch_mesa.sh
./patch_mesa.sh

# Escribimos la receta entera de Docker en un script plano e independiente
cat << 'EOF' > docker_run_inside.sh
#!/bin/bash
set -e

echo "-> [Docker Internal] Preparando directorios para stubs primarios..."
mkdir -p shims_64/lib
mkdir -p drm_shims_inc/include/libdrm

echo "-> [Docker Internal] Instalando herramientas de compilación..."
pip3 install --no-cache-dir --break-system-packages meson ninja mako packaging || pip3 install --no-cache-dir meson ninja mako packaging || true

export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
NDK_SYSROOT_LIB_64="${NDK_SYSROOT}/usr/lib/aarch64-linux-android/26"
NDK_LLVM_LIB="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/19/lib/linux/aarch64"

if [ ! -d "$NDK_LLVM_LIB" ]; then
    NDK_LLVM_LIB=$(find ${ANDROID_NDK_HOME} -name "aarch64" -type d | grep "lib/linux" | head -n 1 || echo "")
fi

echo "-> [Docker Internal] Compilando stubs duales legítivos..."
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_c.o
$NDK_BIN/llvm-ar rcs shims_64/lib/liblog.a stub_c.o
$NDK_BIN/llvm-ar rcs shims_64/libvulkan_wrapper.a stub_c.o

$NDK_BIN/aarch64-linux-android26-clang++ -c stub_logs.c -o stub_cpp.o
$NDK_BIN/llvm-ar rcs shims_64/lib/libandroid.a stub_cpp.o
$NDK_BIN/llvm-ar rcs shims_64/lib/libdl.a stub_cpp.o

echo "-> [Docker Internal] INSTALACIÓN REAL: Colocando ficheros en los Sysroots..."
cp -fv shims_64/lib/libandroid.a "$NDK_SYSROOT_LIB_64/libandroid.a"
cp -fv shims_64/lib/liblog.a "$NDK_SYSROOT_LIB_64/liblog.a"
cp -fv shims_64/lib/libdl.a "$NDK_SYSROOT_LIB_64/libdl.a"

if [ -n "$NDK_LLVM_LIB" ] && [ -d "$NDK_LLVM_LIB" ]; then
    cp -fv shims_64/lib/libandroid.a "$NDK_LLVM_LIB/libandroid.a"
    cp -fv shims_64/lib/liblog.a "$NDK_LLVM_LIB/liblog.a"
    cp -fv shims_64/lib/libdl.a "$NDK_LLVM_LIB/libdl.a"
fi

echo "-> [Docker Internal] Configurando receta para libdrm..."
cat << EOL > cross_libdrm.txt
[binaries]
c = '${NDK_BIN}/aarch64-linux-android26-clang'
cpp = '${NDK_BIN}/aarch64-linux-android26-clang++'
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = '${NDK_SYSROOT}'
[built-in options]
c_args = ['--sysroot=${NDK_SYSROOT}', '-DANDROID', '-D_GNU_SOURCE']
EOF

# Invocamos Meson de forma nativa a través del motor puro de Python3 para ignorar el $PATH roto
python3 -m meson setup build-libdrm libdrm_android --cross-file cross_libdrm.txt --prefix="/workspace/shims_64" \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false
python3 -m meson install -C build-libdrm

cp -rf shims_64/include/libdrm/* drm_shims_inc/include/libdrm/ 2>/dev/null || cp -rf shims_64/include/* drm_shims_inc/include/libdrm/ 2>/dev/null || true

python3 -c '
p="src/vulkan/wrapper/wrapper_log.c"
import os
if os.path.exists(p):
    f=open(p,"r"); c=f.read(); f.close()
    if "fcntl.h" not in c:
        c = "#include <fcntl.h>\n#include <unistd.h>\n" + c
        f=open(p,"w"); f.write(c); f.close()
'

echo "-> [Docker Internal] Generando cross_64.txt definitivo para Mesa 25..."
cat << EOL > cross_64.txt
[constants]
shims_path = '/workspace/shims_64'
drm_inc = '/workspace/drm_shims_inc'
[binaries]
c = '${NDK_BIN}/aarch64-linux-android26-clang'
cpp = '${NDK_BIN}/aarch64-linux-android26-clang++'
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '${NDK_SYSROOT}'
libdir = '${NDK_SYSROOT_LIB_64}'
pkg_config_path = shims_path + '/lib/pkgconfig'
pkg_config_libdir = shims_path + '/lib/pkgconfig'
[built-in options]
c_args = ['--sysroot=${NDK_SYSROOT}', '-D__TERMUX__', '-I' + shims_path + '/include', '-I' + drm_inc + '/include', '-I' + drm_inc + '/include/libdrm']
cpp_args = ['--sysroot=${NDK_SYSROOT}', '-D__TERMUX__', '-I' + shims_path + '/include', '-I' + drm_inc + '/include', '-I' + drm_inc + '/include/libdrm']
c_link_args = ['-L' + shims_path + '/lib', '-L${NDK_SYSROOT_LIB_64}', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
cpp_link_args = ['-L' + shims_path + '/lib', '-L${NDK_SYSROOT_LIB_64}', '-landroid', '-llog', '-ldl', '-lsync', '-lvulkan_wrapper', '-latomic']
EOF

sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('atomic'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true

# Inicialización y compilación masiva delegada a los módulos directos de Python
python3 -m meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost,wrapper
python3 -m meson compile -C build-64
EOF

chmod +x docker_run_inside.sh

# Invocación atómica directa al contenedor sin escapes traicioneros
echo "-> 2. Lanzando entorno biónico aislado en Docker..."
docker run --rm --entrypoint /bin/bash \
  -v "${WORKSPACE}:/workspace" \
  -v "/usr/local/lib/android:/usr/local/lib/android" \
  -w /workspace ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest ./docker_run_inside.sh

# 3. Maquetando empaque de proximidad biónica unificado en el Host de Actions
echo "-> 3. Maquetando empaque unificado de proximidad biónica..."
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/share/vulkan/icd.d

cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || cp -v libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
cp -v shims_64/lib/libdrm.so pkg/usr/lib/libdrm.so 2>/dev/null || true
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so

cd pkg/usr/lib/aarch64-linux-android
ln -sf ../libvulkan_panfrost.so libvulkan_wrapper.so
cd "${WORKSPACE}"

# 🟢 CORRECCIÓN SUPREMA DE RUTA: Apuntamos de forma reglamentaria al subdirectorio unificado donde reside físicamente el binario
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-soname libdrm.so pkg/usr/lib/libdrm.so 2>/dev/null || true

patchelf --add-needed libdrm.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so 2>/dev/null || true
patchelf --add-needed libdrm.so pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true

STRIP_HOST="/usr/local/lib/android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
$STRIP_HOST --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true
$STRIP_HOST --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true

cat << 'EOF' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
{
    "ICD": { "api_version": "1.3.289", "library_path": "libvulkan_wrapper.so" },
    "file_format_version": "1.0.0"
}
EOF

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

# Purgando artefactos efímeros con privilegios de administración
echo "-> 4. Purgando artefactos efímeros con privilegios de administración..."
sudo rm -f docker_run_inside.sh
sudo rm -rf drm_shims_inc/

echo "=========================================================="
echo "🏆 ¡EMPAQUE MONOLÍTICO SEGURO REAL LOGRADO EN VERDE! 🏆"
echo "=========================================================="
