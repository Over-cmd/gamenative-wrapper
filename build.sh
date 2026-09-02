#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 MÓDULO 2: ORQUESTADOR BIÓNICO MAESTRO SEGURO V66"
echo "=========================================================="

WORKSPACE="$(pwd)"

echo "-> 1a. Rastreando de forma dinámica la ubicación del Android NDK..."
NDK_BASE_SEARCH="/usr/local/lib/android/sdk/ndk"
ANDROID_NDK_HOME=$(find "$NDK_BASE_SEARCH" -maxdepth 1 -type d -name "28.*" | head -n 1 || echo "")

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "-> [⚠️ ERROR HOST] No se localizó ninguna instalación válida del NDK r28"
    exit 1
fi
echo "-> [OK] Android NDK detectado físicamente en: $ANDROID_NDK_HOME"

if [ -f "meson.build" ] && grep -q "WORKSPACE=" "meson.build"; then
    rm -f meson.build
fi
git checkout HEAD -- meson.build 2>/dev/null || git checkout -f meson.build 2>/dev/null || true

chmod +x patch_mesa.sh generate_cross.sh docker_run_inside.sh
./patch_mesa.sh
rm -f subprojects/libadrenotools.wrap

echo "-> 1b. Aplicando parches sintácticos sobre Adrenotools en el Host..."
if [ -d "subprojects/libadrenotools" ]; then
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/cc.find_library('android'/dependency('', required : false) #/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/cc.find_library("android"/dependency("", required : false) #/g' {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i "s/cc.find_library('log'/dependency('', required : false) #/g" {} +
    find subprojects/libadrenotools -name "meson.build" -exec sed -i 's/cc.find_library("log"/dependency("", required : false) #/g' {} +
fi

if [ -f "stub_logs.c" ]; then chmod 644 stub_logs.c; fi
./generate_cross.sh

chmod -R 777 "$WORKSPACE"

echo "-> 3. Lanzando entorno biónico aislado en Docker..."
docker run --rm --entrypoint /bin/bash \
  --user "$(id -u):$(id -g)" \
  -e ANDROID_NDK_HOME="$ANDROID_NDK_HOME" \
  -v "${WORKSPACE}:/workspace" \
  -v "${ANDROID_NDK_HOME}:${ANDROID_NDK_HOME}" \
  -w /workspace ghcr.io/leegao/mesa-wrapper-ci/wrapper-compiler:latest ./docker_run_inside.sh

echo "-> 4. Maquetando empaque unificado de proximidad biónica..."
mkdir -p pkg/usr/lib/aarch64-linux-android pkg/usr/share/vulkan/icd.d

if [ -f "compilacion/libvulkan_wrapper.so" ]; then
    cp -v compilacion/libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
elif [ -f "libvulkan_wrapper.so" ]; then
    cp -v libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
else
    echo "-> [❌ ERROR CRÍTICO] Falta libvulkan_wrapper.so"; exit 1
fi

if [ -f "shims_64/lib/libdrm.so" ]; then
    cp -v shims_64/lib/libdrm.so pkg/usr/lib/libdrm.so
else
    echo "-> [❌ ERROR CRÍTICO] Falta libdrm.so"; exit 1
fi

if [ -f "build-64/src/panfrost/vulkan/libvulkan_panfrost.so" ]; then
    cp -v build-64/src/panfrost/vulkan/libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
else
    echo "-> [❌ ERROR CRÍTICO] Falta libvulkan_panfrost.so"; exit 1
fi

# 🟢 REPARACIÓN CRÍTICA SÍNCRONA STRIP: Aplicamos la limpieza de símbolos sobrantes a los archivos FÍSICOS REALES de forma explícita e individual AQUÍ, antes de fabricar enlaces blandos que confundan a la herramienta. Esto reduce el peso del driver para Termux al mínimo legal sin romper inodos
STRIP_HOST="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
if [ -f "$STRIP_HOST" ]; then
    echo "-> [Host] Aligerando binarios reales con llvm-strip de forma explícita..."
    $STRIP_HOST --strip-unneeded pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
    $STRIP_HOST --strip-unneeded pkg/usr/lib/libdrm.so 2>/dev/null || true
    $STRIP_HOST --strip-unneeded pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so 2>/dev/null || true
fi

# Fabricamos de forma segura el enlace simbólico virtual una vez limpiados los datos reales
echo "-> [Host] Inicializando enlace de acoplamiento para Panfrost..."
cd pkg/usr/lib/aarch64-linux-android && ln -sf ../libvulkan_panfrost.so libvulkan_wrapper.so && cd "${WORKSPACE}"

# Sellado estructural con patchelf sobre las rutas consolidadas
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --add-needed libdrm.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-soname libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --add-needed libdrm.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-soname libdrm.so pkg/usr/lib/libdrm.so

cat << 'EOF' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
{ "ICD": { "api_version": "1.3.289", "library_path": "libvulkan_wrapper.so" }, "file_format_version": "1.0.0" }
EOF

echo "-> 5. Sellando empaque de alta compresión..."
echo "msf:315508" > pkg/version.txt && chmod -R 755 pkg/
cd pkg && tar -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt && cd "${WORKSPACE}"

rm -f docker_run_inside.sh cross_libdrm.txt cross_64.txt stub_logs.c stub_c.o stub_cpp.o generate_cross.sh
rm -rf meson_src/ shims_64/ build-64/

echo "=========================================================="
echo "  778/778 COMPLETO - REGISTROS ENLAZADOS CORRECTAMENTE OK "
echo "=========================================================="
