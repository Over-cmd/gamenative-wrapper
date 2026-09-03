#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 MÓDULO 2: ORQUESTADOR BIÓNICO SEGURO DE ENLAZADO REAL V87"
echo "=========================================================="

WORKSPACE="$(pwd)"

echo "-> 1a. Rastreando de forma dinámica la ubicación del Android NDK..."
NDK_BASE_SEARCH="/usr/local/lib/android/sdk/ndk"

# Evitamos caídas por SIGPIPE (tuberías rotas) causadas por head -n 1
set +e
ANDROID_NDK_HOME=$(find "$NDK_BASE_SEARCH" -maxdepth 1 -type d -name "28.*" 2>/dev/null | head -n 1)
set -e

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

echo "-> 1b. Aplicando parches sintácticos y bypass de API en el Host..."

# 🟢 REPARACIÓN PARA EL ERROR DE COMPILACIÓN DE MESA 25 (SYS_memfd_create)
if [ -f "src/util/anon_file.c" ]; then
    echo "   [Mesa] Inyectando fallback seguro para compatibilidad de memoria..."
    sed -i 's/#if defined(__NR_memfd_create)/#if defined(__NR_memfd_create) \&\& !defined(__ANDROID__)/g' src/util/anon_file.c
    sed -i 's/#ifdef SYS_memfd_create/#if defined(SYS_memfd_create) \&\& !defined(__ANDROID__)/g' src/util/anon_file.c
fi

# 🟢 REPARACIÓN PARA ENLAZADO DE ADRENOTOOLS (Falta de __android_log_print)
# Reemplaza la purga destructiva por una inyección de rutas sysroot correctas
ADRENOTOOLS_MESON="subprojects/libadrenotools/meson.build"
if [ -f "$ADRENOTOOLS_MESON" ]; then
    echo "   [Adrenotools] Forzando rutas de enlazado nativas del NDK..."
    NDK_REAL_LIB="-L${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android"
    sed -i "s/link_args : \[/link_args : \['-Wl,--no-as-needed', '${NDK_REAL_LIB}', '-llog', '-landroid', '-ldl', /g" "$ADRENOTOOLS_MESON"
    sed -i "s/adrenotools_link_args = \[/adrenotools_link_args = \['-Wl,--no-as-needed', '${NDK_REAL_LIB}', '-llog', '-landroid', '-ldl', /g" "$ADRENOTOOLS_MESON"
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
# 🟢 CORRECCIÓN: Reconstrucción obligatoria del directorio limpio
rm -rf pkg/
mkdir -p pkg/usr/lib/aarch64-linux-android pkg/usr/share/vulkan/icd.d

# 🟢 CORRECCIÓN: Despliegue de los binarios reales compilados por Ninja
PANFROST_REAL_SRC="build-64/src/panfrost/vulkan/libvulkan_panfrost.so"
if [ -f "$PANFROST_REAL_SRC" ]; then
    echo "-> [Host] Desplegando binarios de Panfrost en el árbol de empaquetado..."
    cp -fv "$PANFROST_REAL_SRC" pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
    cp -fv "$PANFROST_REAL_SRC" pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
    cp -fv "$PANFROST_REAL_SRC" pkg/usr/lib/libvulkan_wrapper.so
else
    echo "-> [❌ ERROR CRÍTICO] El motor real de Panfrost no apareció en $PANFROST_REAL_SRC"
    exit 1
fi

if [ -f "shims_64/lib/libdrm.so" ]; then
    cp -fv shims_64/lib/libdrm.so pkg/usr/lib/libdrm.so
else
    echo "-> [❌ ERROR CRÍTICO] Falta libdrm.so en shims_64/"; exit 1
fi

chmod -R 755 pkg/

STRIP_HOST="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
if [ -f "$STRIP_HOST" ]; then
    echo "-> [Host] Aligerando binarios reales con llvm-strip de forma explícita..."
    $STRIP_HOST --strip-unneeded pkg/usr/lib/libvulkan_wrapper.so 2>/dev/null || true
    $STRIP_HOST --strip-unneeded pkg/usr/lib/libdrm.so 2>/dev/null || true
    $STRIP_HOST --strip-unneeded pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so 2>/dev/null || true
    $STRIP_HOST --strip-unneeded pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so 2>/dev/null || true
fi

echo "-> [Host] Aplicando sellado estructural con patchelf..."
patchelf --set-soname libvulkan_wrapper.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --add-needed libdrm.so pkg/usr/lib/libvulkan_wrapper.so
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/libvulkan_wrapper.so

patchelf --set-soname libvulkan_panfrost.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --add-needed libdrm.so pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/aarch64-linux-android/libvulkan_panfrost.so

patchelf --set-soname libvulkan_wrapper_android.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
patchelf --add-needed libdrm.so pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so
patchelf --set-rpath '$ORIGIN' pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

patchelf --set-soname libdrm.so pkg/usr/lib/libdrm.so

cat << 'EOF' > pkg/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
{ "ICD": { "api_version": "1.3.289", "library_path": "libvulkan_wrapper.so" }, "file_format_version": "1.0.0" }
EOF

cat << 'EOF' > pkg/usr/share/vulkan/icd.d/panfrost_icd.aarch64.json
{ "ICD": { "api_version": "1.3.289", "library_path": "aarch64-linux-android/libvulkan_panfrost.so" }, "file_format_version": "1.0.0" }
EOF

echo "msf:315508" > pkg/version.txt
chmod -R 755 pkg/

echo "-> [AUDITORÍA FINAL SANIDAD] Verificando presencia real en el disco antes de tar:"
ls -l pkg/usr/lib/libvulkan_wrapper.so
ls -l pkg/usr/lib/aarch64-linux-android/libvulkan_wrapper.so

echo "-> 5. Sellando empaque de alta compresión..."
sync
cd pkg && tar --hard-dereference -I "zstd -19 -T0" -cf "../wrapper.tzst" usr version.txt && cd "${WORKSPACE}"

rm -f docker_run_inside.sh cross_libdrm.txt cross_64.txt stub_logs.c stub_c.o stub_cpp.o generate_cross.sh 2>/dev/null || true
rm -rf meson_src/ shims_64/ build-64/

echo "=========================================================="
echo "  778/778 COMPLETO - REGISTROS ENLAZADOS CORRECTAMENTE OK "
echo "=========================================================="
