#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 INICIANDO ENLAZADOR DOCKER-INTEGRAL MESA 25 (ARM64)"
echo "=========================================================="

echo "-> 1. Ordenando al Contenedor de Docker compilar el Interceptor oficial..."
# Esta llamada oficial genera tu libvulkan_wrapper.so con el parche de mallopt inyectado
docker run --rm -v "$(pwd):/workspace" ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest compilacion

echo "-> 2. 🟢 JUGADA MAESTRA: Forzamos al Docker a compilar el driver físico de Panfrost..."
# Aprovechamos el entorno interno del Docker (con libdrm de Termux y -U__ANDROID__ listo) para compilar Mesa 25 nativo
docker run --rm -v "$(pwd):/workspace" --entrypoint /usr/bin/ninja ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest -C compilacion src/panfrost/vulkan/libvulkan_panfrost.so

echo "-> 3. Estructurando maquetado ICD plano reglamentario para Bannerlator..."
rm -rf pkg && mkdir -p pkg/usr/lib pkg/usr/share/vulkan/icd.d

echo "-> [A] Colocando el Wrapper interceptor de Docker como entrada principal..."
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so

echo "-> [B] Colocando el motor de Panfrost de 64 bits nacido legítimamente dentro de Docker..."
cp -v compilacion/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/libvulkan_panfrost_64.so

# Ranura de contingencia reutilizando el Wrapper dinámico
cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_panfrost_32.so

echo "-> [C] Sellando identidades de SONAME internas mediante patchelf..."
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost_64.so pkg/usr/lib/libvulkan_panfrost_64.so
patchelf --set-soname libvulkan_panfrost_32.so pkg/usr/lib/libvulkan_panfrost_32.so

# Buscamos el strip del NDK del host de las Actions para remover tablas de debug muertas
NDK_STRIP=$(find /usr/local/lib/android/sdk/ndk/ -name "llvm-strip" | head -n 1)
if [ -n "$NDK_STRIP" ]; then
  $NDK_STRIP --strip-unneeded pkg/usr/lib/*.so 2>/dev/null || true
fi

echo "-> [D] Escribiendo manifiestos ICD limpios sin carpetas settings duplicadas..."
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
echo '{"ICD": {"api_version": "1.3.289", "library_path": "libvulkan_wrapper.so"}, "file_format_version": "1.0.0"}' > pkg/usr/share/vulkan/icd.d/wrapper_icd.arm.json

echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt

echo "=========================================================="
echo "🟢 ¡FAT PACK DOCKER-PURE COMPLETADO EN VERDE ABSOLUTO!"
echo "=========================================================="
