#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO 1: LIMPIEZA, DESPLIEGUE Y CLONADO DE HERRAMIENTAS REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"

echo "-> 1a. Ejecutando purga atómica de directorios previos..."
mkdir -p .trash
if [ -d "subprojects/libadrenotools" ]; then mv subprojects/libadrenotools .trash/adrenotools_$(date +%s) || true; fi
if [ -d "build-64" ]; then mv build-64 .trash/build64_$(date +%s) || true; fi
if [ -d "meson_src" ]; then mv meson_src .trash/meson_$(date +%s) || true; fi

# Saneamos los residuos en segundo plano sin estrangular el ulimit del host
sudo rm -rf shims_64/ build-libdrm/ libdrm_android/ pkg/ .trash/ &

mkdir -p shims_64/lib

echo "-> 1b. Descargando código legítimo de libdrm (SailfishOS)..."
curl -L "https://github.com/sailfishos-mirror/drm/archive/refs/heads/main.zip" -o libdrm.zip
unzip -q libdrm.zip
mv -v drm-main libdrm_android
rm -f libdrm.zip

echo "-> 1c. Descargando código legítimo de libadrenotools (Pipetto)..."
mkdir -p subprojects
curl -L "https://github.com/Pipetto-crypto/libadrenotools/archive/refs/heads/master.zip" -o adrenotools.zip
unzip -q adrenotools.zip
rm -rf subprojects/libadrenotools
mv -v libadrenotools-master subprojects/libadrenotools
rm -f adrenotools.zip

echo "-> 1d. Descargando e instalando Meson de forma autónoma local..."
rm -rf meson_src
git clone --depth 1 https://github.com/mesonbuild/meson.git meson_src

# Fabricamos el archivo de stubs de logs mínimos para el compilador móvil
cat << 'EOF' > stub_logs.c
int get_wrapper_log_level(const char *option) { (void)option; return 0; }
void write_to_logfile(const char *fmt, const char *level, ...) { (void)fmt; (void)level; }
void *dlopen(const char *f, int flags) { (void)f; (void)flags; return 0; }
void *dlsym(void *h, const char *s) { (void)h; (void)s; return 0; }
int dlclose(void *h) { (void)h; return 0; }
EOF

echo "=========================================================="
echo "🟢 MÓDULO 1 CONCLUIDO CON ÉXITO - HERRAMIENTAS INSTALADAS"
echo "=========================================================="
