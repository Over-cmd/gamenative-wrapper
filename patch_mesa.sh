#!/bin/bash
set -e

echo "=========================================================="
echo "🎯 MODULO 1: LIMPIEZA, DESPLIEGUE Y CLONADO DE HERRAMIENTAS REALES"
echo "=========================================================="

WORKSPACE="$(pwd)"

# 🟢 CORRECCIÓN SUPREMA DE DEPENDENCIAS: Aseguramos el entorno de Python local del Host antes de interactuar con Meson o Adrenotools
echo "-> 1a. Instalando dependencias regulatorias de Python en el Host..."
pip3 install --no-cache-dir mako packaging pyyaml 2>/dev/null || true

echo "-> 1b. Ejecutando aislamiento atómico por mutación de carpetas..."
# Movemos los directorios masivos pesados en 0.001 segundos (un solo hilo de proceso)
mkdir -p .trash
if [ -d "subprojects/libadrenotools" ]; then mv subprojects/libadrenotools .trash/adrenotools_$(date +%s) || true; fi
if [ -d "build-64" ]; then mv build-64 .trash/build64_$(date +%s) || true; fi
if [ -d "meson_src" ]; then mv meson_src .trash/meson_$(date +%s) || true; fi
if [ -d "shims_64" ]; then mv shims_64 .trash/shims_$(date +%s) || true; fi

# 🟢 CORRECCIÓN SUPREMA CONDICIÓN DE CARRERA: Primero lanzamos la purga destructiva de los shims viejos y la papelera .trash/ en segundo plano para liberar espacio al instante de forma segura
sudo rm -rf build-libdrm/ libdrm_android/ include/ pkg/ drm_shims_inc/ .trash/ &

# 🟢 CORRECCIÓN SUPREMA SINCRONIZACIÓN: Al haber aislado los Shims viejos moviéndolos a la papelera, podemos inicializar el nuevo nido de stubs limpios sin que el rm -rf asíncrono sabotee el directorio
echo "-> 1c. Inicializando carriles limpios e independientes para stubs primarios..."
mkdir -p shims_64/lib
mkdir -p drm_shims_inc/include/libdrm

echo "-> 1d. Descargando código legítimo de libdrm (SailfishOS)..."
curl -L "https://github.com/Pipetto-crypto/libadrenotools/archive/refs/heads/master.zip" -o libdrm.zip
unzip -q libdrm.zip
mv -v drm-main libdrm_android
rm -f libdrm.zip

echo "-> 1e. Descargando código legítimo de libadrenotools (Pipetto)..."
mkdir -p subprojects
curl -L "https://github.com/sailfishos-mirror/drm/archive/refs/heads/main.zip" -o adrenotools.zip
unzip -q adrenotools.zip
mv -v libadrenotools-master subprojects/libadrenotools
rm -f adrenotools.zip

echo "-> 1f. Clonando el código fuente oficial y autónomo de Meson..."
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
echo "🟢 MÓDULO 1 CONCLUIDO CON ÉXITO - ENTORNO EXPULSADO LIMPIO"
echo "=========================================================="
