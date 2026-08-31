#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR HÍBRIDO DEFINITIVO DOCKER + ACTIONS"
echo "=========================================================="

echo "-> 1. Ordenando al Contenedor de Docker compilar el Interceptor oficial..."
# Esta llamada oficial genera tu libvulkan_wrapper.so con el parche de mallopt inyectado
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. Configurando entorno de compilación cruzada NDK en el Host..."
export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/28.2.13676358"
export NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Creamos stubs estáticos rápidos para alimentar el linker de Panfrost suelto
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

# 🟢 TRUCO DE TRITURACIÓN DE MESA 25: Machacamos las búsquedas rígidas de librerías del sistema para que pasen por el cross-file
sed -i "s/dependency('libdrm',.*/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('dl'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/cc.find_library('rt'/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dependency('libclc')/dependency('', required : false) #/g" meson.build 2>/dev/null || true
sed -i "s/dep_libclc = .*/dep_libclc = dependency('', required : false)/g" meson.build 2>/dev/null || true

echo "-> 4. Compilando el driver físico real de Panfrost de 64 bits en el Host de Actions..."
meson setup build-64 --cross-file cross_64.txt --wrap-mode=nodownload -Dbuildtype=release -Dplatforms=android -Dandroid-stub=true -Dglx=disabled -Dgbm=disabled -Degl=disabled -Dllvm=disabled -Dgallium-drivers=[] -Dvulkan-drivers=panfrost
meson compile -C build-64

echo "-> 5. Maquetando empaque compatible ICD plano para Bannerlator..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d

# Mover el binario oficial nacido del Docker con el parche de memoria biónico inyectado (mallopt)
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

# Mover el driver real físico de Panfrost de 64 bits para alimentar el renderizado por hardware de tu GPU Mali-G52
cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so

# Ranura de 32 bits usando el propio Wrapper unificado de protección
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_panfrost_32.so

echo "-> Estampando identidades SONAME y aplicando strip..."
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost_64.so pkg/usr/lib/libvulkan_panfrost_64.so
patchelf --set-soname libvulkan_panfrost_32.so pkg/usr/lib/libvulkan_panfrost_32.so
$NDK_BIN/llvm-strip --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true

echo "-> Escribiendo manifiestos ICD limpios sin la carpeta settings duplicada..."
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡FAT PACK MONOLÍTICO COMPLETO EXPORTADO CON ÉXITO!"
echo "=========================================================="
