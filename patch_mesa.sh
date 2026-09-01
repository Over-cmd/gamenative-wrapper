#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO 1: LIMPIEZA Y DESPLIEGUE DE FUENTES REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"

echo "-> 1. Ejecutando CleanSpec sobre el espacio de trabajo..."
rm -rf shims_64/ build-libdrm/ build-64/ libdrm_android/ include/ pkg/
mkdir -p shims_64/lib

echo "-> 2. Descargando código legítimo de libdrm (SailfishOS)..."
curl -L "https://github.com/sailfishos-mirror/drm/archive/refs/heads/main.zip" -o libdrm.zip
unzip -q libdrm.zip
mv -v drm-main libdrm_android
rm -f libdrm.zip

echo "-> 3. Descargando código legítimo de libadrenotools (Pipetto)..."
mkdir -p subprojects
curl -L "https://github.com/Pipetto-crypto/libadrenotools/archive/refs/heads/master.zip" -o adrenotools.zip
unzip -q adrenotools.zip
rm -rf subprojects/libadrenotools
mv -v libadrenotools-master subprojects/libadrenotools
rm -f adrenotools.zip

# Fabricamos el archivo de stubs de logs mínimos para el compilador móvil
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
void *dlopen(const char *f, int flags) { (void)f; (void)flags; return 0; }
void *dlsym(void *h, const char *s) { (void)h; (void)s; return 0; }
int dlclose(void *h) { (void)h; return 0; }
EOF

echo "=========================================================="
echo "🟢 MÓDULO 1 LISTO - FUENTES DESPLEGADOS"
echo "=========================================================="
