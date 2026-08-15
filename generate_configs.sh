#!/bin/bash
set -e
mkdir -p bin_hijack 

### Generar cross de 64 bits

cat << 'EOF' > bin_hijack/cross_aarch64.txt
[binaries]
c = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang'
cpp = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang++'
ar = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkg-config = 'pkg-config'
[constants]
td = '/data/data/com.termux/files/usr'
[properties]
pkg_config_libdir = td + '/lib/pkgconfig:' + td + '/share/pkgconfig'
[built-in options]
c_args = ['-D__TERMUX__','-D__USE_GNU','-U__ANDROID__','-I'+td+'/include','-include','fcntl.h','-include','unistd.h']
cpp_args = ['-D__TERMUX__','-D__USE_GNU','-U__ANDROID__','-I'+td+'/include','-include','fcntl.h','-include','unistd.h']
c_link_args = ['-L'+td+'/lib','-landroid-shmem']
cpp_link_args = ['-L'+td+'/lib','-landroid-shmem']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF 

### Generar cross de 32 bits

cat << 'EOF' > bin_hijack/cross_arm.txt
[binaries]
c = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi30-clang'
cpp = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi30-clang++'
ar = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '@NDK_PATH@/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkg-config = 'pkg-config'
[constants]
td = '/data/data/com.termux/files/usr'
[properties]
pkg_config_libdir = td + '/lib/arm-linux-androideabi/pkgconfig:' + td + '/share/pkgconfig'
[built-in options]
c_args = ['-D__TERMUX__','-D__USE_GNU','-U__ANDROID__','-I'+td+'/include','-include','fcntl.h','-include','unistd.h','-march=armv7-a','-mfpu=neon']
cpp_args = ['-D__TERMUX__','-D__USE_GNU','-U__ANDROID__','-I'+td+'/include','-include','fcntl.h','-include','unistd.h','-march=armv7-a','-mfpu=neon']
c_link_args = ['-L'+td+'/lib/arm-linux-androideabi','-landroid-shmem']
cpp_link_args = ['-L'+td+'/lib/arm-linux-androideabi','-landroid-shmem']
[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7-a'
endian = 'little'
EOF 

### Script que corre internamente en Docker para compilar

cat << 'EOF' > bin_hijack/build.sh
#!/bin/bash
set -e
A="${ARCH:-aarch64}"
B="{1:-b_{A}}"
R=$(find /home/builder/lib -maxdepth 2 -name "android-ndk*" 2>/dev/null | head -n 1)
sed -i "s|@NDK_PATH@|${R}|g" /root/build-config/cross_aarch64.txt
sed -i "s|@NDK_PATH@|${R}|g" /root/build-config/cross_arm.txt
if [ ! -d "${B}" ]; then
meson setup "{B}" --cross-file /root/build-config/cross_{A}.txt -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= -Dxmlconfig=disabled -Dandroid-stub=true -Dvulkan-drivers=wrapper
fi
ninja -C "${B}" src/vulkan/wrapper/libvulkan_wrapper.so
cp "
𝐵

/𝑠𝑟𝑐

/𝑣𝑢𝑙𝑘𝑎𝑛

/𝑤𝑟𝑎𝑝𝑝𝑒𝑟

/𝑙𝑖𝑏𝑣𝑢𝑙𝑘𝑎𝑛𝑤𝑟𝑎𝑝𝑝𝑒𝑟

.

𝑠𝑜

"

"
{B}/libvulkan_wrapper.so.unstripped"
"${R}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded -o "
𝐵

/𝑙𝑖𝑏𝑣𝑢𝑙𝑘𝑎𝑛𝑤𝑟𝑎𝑝𝑝𝑒𝑟

.

𝑠𝑜

"

"
{B}/libvulkan_wrapper.so.unstripped"
EOF
chmod +x bin_hijack/build.sh 

### Puente Conmutador en C para Bannerlator

cat << 'EOF' > bin_hijack/bridge.c
#include <dlfcn.h>
#include <stddef.h>
static void* h = NULL;
static void **attribute**((constructor)) init() {
h = dlopen((sizeof(void*) == 4) ? "/data/data/com.termux/files/usr/lib/libvulkan_wrapper_32.so" : "/data/data/com.termux/files/usr/lib/libvulkan_wrapper_64.so", RTLD_NOW | RTLD_GLOBAL);
}
**attribute**((visibility("default"))) void* vk_icdGetInstanceProcAddr(void* inst, const char* name) {
if (!h) return NULL;
void* (*f)(void*, const char*) = dlsym(h, "vk_icdGetInstanceProcAddr");
return f ? f(inst, name) : NULL;
}
EOF
