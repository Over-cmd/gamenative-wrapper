#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO 1: LIMPIEZA, DESPLIEGUE Y CLONADO DE HERRAMIENTAS REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"

echo "-> 1a. Instalando dependencias de Python en el Host..."
pip3 install --no-cache-dir mako packaging pyyaml 2>/dev/null || true

echo "-> 1b. Ejecutando purga destructiva de residuos previos de forma síncrona..."
sudo rm -rf shims_64/ build-libdrm/ libdrm_android/ pkg/ drm_shims_inc/ build-64/ subprojects/libadrenotools/

mkdir -p .trash
if [ -d "meson_src" ]; then mv meson_src .trash/meson_$(date +%s) || true; fi

sudo rm -rf .trash/ &
PID_CLEAN=$!

echo "-> 1c. Inicializando nidos de compilación limpios e inmunes..."
mkdir -p shims_64/lib

echo "-> 1d. Descargando código legítimo de libdrm (SailfishOS) de forma nativa por Git..."
rm -rf libdrm_android
git clone --depth 1 https://github.com libdrm_android

echo "-> 1e. Descargando tu código real de libadrenotools con submódulos recursivos..."
mkdir -p subprojects
rm -rf subprojects/libadrenotools
git clone --depth 1 --recursive https://github.com subprojects/libadrenotools

echo "-> 1f. Aplicando parches quirúrgicos inmediatos sobre Adrenotools..."
if [ -f "subprojects/libadrenotools/meson.build" ]; then
    sed -i "s#cc.find_library('android'#dependency('', required : false) ##g" subprojects/libadrenotools/meson.build
    sed -i 's#cc.find_library("android"#dependency("", required : false) ##g' subprojects/libadrenotools/meson.build
    sed -i "s#cc.find_library('log'#dependency('', required : false) ##g" subprojects/libadrenotools/meson.build
    sed -i 's#cc.find_library("log"#dependency("", required : false) ##g' subprojects/libadrenotools/meson.build
fi

echo "-> 1g. Clonando la versión de desarrollo compatible de Meson 1.11.1..."
rm -rf meson_src
git clone --depth 1 --branch 1.11.1 https://github.com meson_src

cat << 'EOF' > stub_logs.c
#include <stdarg.h>
#include <stddef.h>

void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }

int __android_log_print(int prio, const char *tag, const char *fmt, ...) {
    (void)prio; (void)tag; (void)fmt;
    return 0;
}

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
