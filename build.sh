#!/bin/bash
set -e 

### Leer arquitectura seleccionada o asignar 'all' por defecto

ARCH="${ARCH:-all}" 

### Ubicación del repositorio y archivos de configuración cruzada

REPO_DIR="/root/gamenative-wrapper"
CONFIG_BASE="/root/build-config" 

NDK_DIR=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)
STRIP_BIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" 

compile_target() {
local target_arch=$1
local build_dir="{REPO_DIR}/build_{target_arch}"
local cross_file="{CONFIG_BASE}/cross_{target_arch}.txt" 

echo "============================================="
echo " Iniciando compilación de Mesa Wrapper: ${target_arch}"
echo "=============================================" 

cd "${REPO_DIR}" 

### Inicializar Meson si la carpeta no existe

if [ ! -d "${build_dir}" ]; then
meson setup "
𝑏𝑢𝑖𝑙𝑑𝑑𝑖𝑟

"

−−𝑐𝑟𝑜𝑠𝑠

−𝑓𝑖𝑙𝑒

"
{cross_file}" 
-Dcpp_rtti=false 
-Dgbm=disabled 
-Dopengl=false 
-Dllvm=disabled 
-Dshared-llvm=disabled 
-Dplatforms=x11 
-Dgallium-drivers= 
-Dxmlconfig=disabled 
-Dvulkan-drivers=wrapper
fi 

### Compilar componente específico de Vulkan Wrapper de Mesa

ninja -C "${build_dir}" src/vulkan/wrapper/libvulkan_wrapper.so 

### Crear copia sin strips para depuraciones eventuales

cp "
𝑏𝑢𝑖𝑙𝑑𝑑𝑖𝑟

/𝑠𝑟𝑐

/𝑣𝑢𝑙𝑘𝑎𝑛

/𝑤𝑟𝑎𝑝𝑝𝑒𝑟

/𝑙𝑖𝑏𝑣𝑢𝑙𝑘𝑎𝑛𝑤𝑟𝑎𝑝𝑝𝑒𝑟

.

𝑠𝑜

"

"
{build_dir}/libvulkan_wrapper.so.unstripped" 

### Strip final para reducir drásticamente el tamaño del .so

$STRIP_BIN --strip-unneeded -o "
𝑏𝑢𝑖𝑙𝑑𝑑𝑖𝑟

/𝑙𝑖𝑏𝑣𝑢𝑙𝑘𝑎𝑛𝑤𝑟𝑎𝑝𝑝𝑒𝑟

.

𝑠𝑜

"

"
{build_dir}/libvulkan_wrapper.so.unstripped" 

echo " Compilación exitosa para ${target_arch}."
echo " Binario listo en: ${build_dir}/libvulkan_wrapper.so"
} 

### Lógica de enrutamiento por arquitectura

if [ "${ARCH}" = "all" ]; then
compile_target "aarch64"
compile_target "arm"
elif [ "
𝐴𝑅𝐶𝐻

"

=

"

𝑎𝑎𝑟𝑐ℎ64

"

]

|

|

[

"
{ARCH}" = "arm" ]; then
compile_target "${ARCH}"
else
echo "Error: Arquitectura '${ARCH}' inválida. Usa 'aarch64', 'arm' o 'all'."
exit 1
fi
