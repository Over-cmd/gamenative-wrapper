#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR HÍBRIDO FAT CON INTERCEPTOR DE WRAP"
echo "=========================================================="

echo "-> 1. Ordenando al Contenedor de Docker compilar el Interceptor oficial..."
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK en el Host..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
EOF
mkdir -p "$(pwd)/shims_64"
$NDK_BIN/aarch64-linux-android26-clang -c stub_logs.c -o stub_logs_64.o
$NDK_BIN/llvm-ar rcs "$(pwd)/shims_64/libvulkan_wrapper.a" stub_logs_64.o

NDK_SYSROOT_LIB_64="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/26"

echo "-> 3. Generando cross_64.txt con inyección nativa de cabeceras DRM locales..."
cat << EOF > cross_64.txt
[constants]
ndk_path = '${ANDROID_NDK_HOME}'
toolchain = ndk_path + '/toolchains/llvm/prebuilt/linux-x86_64/bin'
api = '26'
[binaries]
c       = toolchain + '/aarch64-linux-android' + api + '-clang'
cpp     = toolchain + '/aarch64-linux-android' + api + '-clang++'
ar      = toolchain + '/llvm-ar'
strip   = toolchain + '/llvm-strip'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '${NDK_SYSROOT}'
libdir = '${NDK_SYSROOT_LIB_64}'
[built-in options]
c_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I' + '$(pwd)/subprojects/libdrm', '-I' + '$(pwd)/subprojects/libdrm/include/drm']
cpp_args = ['--sysroot=' + '${NDK_SYSROOT}', '-D__TERMUX__', '-I' + '$(pwd)/subprojects/libdrm', '-I' + '$(pwd)/subprojects/libdrm/include/drm']
c_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
cpp_link_args = ['-landroid', '-llog', '-lsync', '-lvulkan_wrapper', '-L${NDK_SYSROOT_LIB_64}', '-L$(pwd)/shims_64']
EOF

# 🟢 JUGADA MAESTRA DE ANULACIÓN: Forzamos un .wrap falso local para que Meson asuma que libdrm ya está resuelta internamente
mkdir -p subprojects
cat << 'EOF' > subprojects/libdrm.wrap
[wrap-file]
directory = libdrm
[provide]
libdrm = dep_libdrm
EOF

# Purga de validaciones secundarias que rompen el setup cruzado
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 4. Compilando el driver físico real de Panfrost de 64 bits..."
# Usamos --wrap-mode=nodownload para forzar a Meson a tragarse nuestro override de subproyecto sin buscar en internet
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-64

echo "-> 5. Maquetando empaque compatible ICD plano multi-directorio..."
rm -rf pkg
mkdir -p pkg/usr/lib/aarch64-linux-android
mkdir -p pkg/usr/lib/arm-linux-androideabi
mkdir -p pkg/usr/share/vulkan/icd.d

echo "-> [A] Guardando Interceptor base en la raíz de librerías..."
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

echo "-> [B] Guardando Panfrost de 64 bits en su subcarpeta dedicada bajo el nombre puro..."
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

echo "-> [C] Guardando clon de contingencia de 32 bits..."
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/arm-linux-androideabi/libvulkan_wrapper.so

echo "-> [D] Grabando el identificador interno SONAME libvulkan_wrapper.so en toda la pila..."
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/arm-linux-androideabi/libvulkan_wrapper.so

$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/aarch64-linux-android/*.so 2>/dev/null || true
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/arm-linux-androideabi/*.so 2>/dev/null || true

echo "-> [E] Escribiendo manifiestos ICD limpios..."
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡FAT PACK MONOLÍTICO SEPARADO COMPLETADO EN VERDE TOTAL!"
echo "=========================================================="
