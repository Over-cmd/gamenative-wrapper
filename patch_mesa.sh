#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO 1: LIMPIEZA, DESPLIEGUE Y CLONADO DE HERRAMIENTAS REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"

# 1a. Instalando dependencias regulatorias de Python en el Host
echo "-> 1a. Instalando dependencias de Python en el Host..."
pip3 install --no-cache-dir mako packaging pyyaml 2>/dev/null || true

# 🟢 CORRECCIÓN SUPREMA DE CONCURRENCIA: Ejecutamos el vaciado pesado de escombros de forma SÍNCRONA en primer plano para evitar que un rm -rf retrasado barra el nuevo mkdir
echo "-> 1b. Ejecutando purga destructiva de residuos previos de forma síncrona..."
sudo rm -rf shims_64/ build-libdrm/ libdrm_android/ include/ pkg/ drm_shims_inc/ build-64/

# Movemos los residuos masivos de Git y Adrenotools a la papelera en un milisegundo
mkdir -p .trash
if [ -d "subprojects/libadrenotools" ]; then mv subprojects/libadrenotools .trash/adrenotools_$(date +%s) || true; fi
if [ -d "meson_src" ]; then mv meson_src .trash/meson_$(date +%s) || true; fi

# La papelera .trash/ se tritura en segundo plano de forma segura, pero el script esperará su fin si es necesario
sudo rm -rf .trash/ &
PID_CLEAN=$!

# 🟢 CORRECCIÓN SUPREMA DE INFRAESTRUCTURA: Inicializamos los carriles limpios SOLO cuando el disco está completamente pacificado y libre de hilos rm -rf mutantes
echo "-> 1c. Inicializando nidos de compilación limpios e inmunes..."
mkdir -p shims_64/lib

echo "-> 1d. Descargando código legítimo de libdrm (SailfishOS)..."
curl -L "https://github.com/sailfishos-mirror/drm/archive/refs/heads/main.zip" -o libdrm.zip
unzip -q libdrm.zip
mv -v drm-main libdrm_android
rm -f libdrm.zip

echo "-> 1e. Descargando código legítimo de libadrenotools (Pipetto)..."
mkdir -p subprojects
curl -L "https://github.com/Pipetto-crypto/libadrenotools/archive/refs/heads/master.zip" -o adrenotools.zip
unzip -q adrenotools.zip
mv -v libadrenotools-master subprojects/libadrenotools
rm -f adrenotools.zip

echo "-> 1f. Clonando el código fuente oficial y autónomo de Meson..."
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

# Nos aseguramos de que el proceso background de la papelera .trash/ haya terminado antes de cederle el control al Módulo 2
wait $PID_CLEAN 2>/dev/null || true

echo "=========================================================="
echo "🟢 MÓDULO 1 CONCLUIDO CON ÉXITO - REPOSITORIOS ALINEADOS OK"
echo "=========================================================="
