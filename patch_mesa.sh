#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO 1: LIMPIEZA, DESPLIEGUE Y CLONADO DE HERRAMIENTAS REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"

# 1a. Instalando dependencias de Python regulatorias en el Host
echo "-> 1a. Instalando dependencias de Python en el Host..."
pip3 install --no-cache-dir mako packaging pyyaml 2>/dev/null || true

# Ejecutamos el vaciado pesado de escombros de forma SÍNCRONA en primer plano para evitar condiciones de carrera
echo "-> 1b. Ejecutando purga destructiva de residuos previos de forma síncrona..."
sudo rm -rf shims_64/ build-libdrm/ libdrm_android/ pkg/ drm_shims_inc/ build-64/

mkdir -p .trash
if [ -d "subprojects/libadrenotools" ]; then mv subprojects/libadrenotools .trash/adrenotools_$(date +%s) || true; fi
if [ -d "meson_src" ]; then mv meson_src .trash/meson_$(date +%s) || true; fi

sudo rm -rf .trash/ &
PID_CLEAN=$!

echo "-> 1c. Inicializando nidos de compilación limpios e inmunes..."
mkdir -p shims_64/lib

echo "-> 1d. Descargando código legítimo de libdrm (SailfishOS)..."
rm -rf libdrm_android
git clone --depth 1 https://github.com/sailfishos-mirror/drm.git libdrm_android

# 🟢 CORRECCIÓN SUPREMA 1e: Reemplazamos el curl incompleto por un clonado recursivo legítimo de Git para descargar físicamente el submódulo linkernsbypass y sus meson.build anidados
echo "-> 1e. Descargando código real de libadrenotools con submódulos recursivos..."
mkdir -p subprojects
rm -rf subprojects/libadrenotools
git clone --depth 1 --recursive https://github.com/Over-cmd/libadrenotools.git subprojects/libadrenotools

# Usamos '|' como delimitador seguro en sed para que las comillas y la almohadilla del comentario convivan de forma legal sin errores de Bash
sed -i "s|cc.find_library('android'|dependency('', required : false) #|g" subprojects/libadrenotools/meson.build
sed -i 's|cc.find_library("android"|dependency("", required : false) #|g' subprojects/libadrenotools/meson.build
sed -i "s|cc.find_library('log'|dependency('', required : false) #|g" subprojects/libadrenotools/meson.build
sed -i 's|cc.find_library("log"|dependency("", required : false) #|g' subprojects/libadrenotools/meson.build

echo "-> 1f. Clonando la versión de desarrollo compatible de Meson 1.11.1..."
rm -rf meson_src
git clone --depth 1 --branch 1.11.1 https://github.com/mesonbuild/meson.git meson_src

# 🟢 REPARACIÓN INDUSTRIAL STUBS V50: Purificamos write_to_logfile de este archivo artificial para eliminar la última duplicidad en ld.lld de raíz
cat << 'EOF' > stub_logs.c
#include <stdarg.h>
#include <stddef.h>

// Firmas de enlazado de liblog.a para Adrenotools
int __android_log_print(int prio, const char *tag, const char *fmt, ...) {
    (void)prio; (void)tag; (void)fmt;
    return 0;
}

// Firmas de enlazado de libandroid.a y libdl.a para linkernsbypass
void* android_dlopen_ext(const char* filename, int flags, const void* extinfo) {
    (void)filename; (void)flags; (void)extinfo;
    return 0;
}

int dl_iterate_phdr(int (*callback)(void*, size_t, void*), void* data) {
    (void)callback; (void)data;
    return 0;
}

void* dlopen(const char* filename, int flags) { (void)filename; (void)flags; return 0; }
void* dlsym(void* handle, const char* symbol) { (void)handle; (void)symbol; return 0; }
int dlclose(void* handle) { (void)handle; return 0; }
EOF

wait $PID_CLEAN 2>/dev/null || true

echo "=========================================================="
echo "🟢 MÓDULO 1 CONCLUIDO CON ÉXITO - REPOSITORIOS ALINEADOS OK"
echo "=========================================================="
