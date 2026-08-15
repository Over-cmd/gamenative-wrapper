#!/bin/bash
set -e 

### Asignar variables por defecto si no están definidas

CUSTOM_TAG="gamenative-unisoc-builder:latest"
BUILD_DIR_64="b_64"
BUILD_DIR_32="b_32" 

echo "-> 1. Construyendo la imagen Docker Custom..."
docker build -t "$CUSTOM_TAG" . 

echo "-> 2. Compilando arquitectura de 64 bits (aarch64)..."
docker run --rm -e ARCH=aarch64 -v "$GITHUB_WORKSPACE:/workspace" "
𝐶𝑈𝑆𝑇𝑂𝑀𝑇𝐴𝐺

"

"
BUILD_DIR_64" 

echo "-> 3. Compilando arquitectura de 32 bits (arm)..."
docker run --rm -e ARCH=arm -v "$GITHUB_WORKSPACE:/workspace" "
𝐶𝑈𝑆𝑇𝑂𝑀𝑇𝐴𝐺

"

"
BUILD_DIR_32" 

echo "-> 4. Compilando el puente Multiarch unificado..."
mkdir -p unified_out
NDK_PATH=(docker run --rm --entrypoint /bin/bash "CUSTOM_TAG" -c 'find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1')
docker run --rm -v "$GITHUB_WORKSPACE:/workspace" --entrypoint /bin/bash "
𝐶𝑈𝑆𝑇𝑂𝑀𝑇𝐴𝐺

"

−𝑐

"
{NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang -shared -fPIC -O3 /root/bridge.c -o /workspace/unified_out/libvulkan_wrapper.so -ldl" 

echo "-> 5. Estructurando y empaquetando wrapper.tzst..."
mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d 

if [ -f "$BUILD_DIR_64/libvulkan_wrapper.so" ]; then
cp "$BUILD_DIR_64/libvulkan_wrapper.so" pkg/usr/lib/libvulkan_wrapper_64.so
else
cp "$BUILD_DIR_64/src/vulkan/wrapper/libvulkan_wrapper.so" pkg/usr/lib/libvulkan_wrapper_64.so
fi 

if [ -f "$BUILD_DIR_32/libvulkan_wrapper.so" ]; then
cp "$BUILD_DIR_32/libvulkan_wrapper.so" pkg/usr/lib/libvulkan_wrapper_32.so
else
cp "$BUILD_DIR_32/src/vulkan/wrapper/libvulkan_wrapper.so" pkg/usr/lib/libvulkan_wrapper_32.so
fi 

cp unified_out/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
echo '{"ICD":{"api_version":"1.3.289","library_path":"libvulkan_wrapper.so"},"file_format_version":"1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json 

cd pkg && tar -I 'zstd -19 -T0' -cf ../wrapper.tzst usr/
echo "-> ¡Empaquetado completado con éxito!"
