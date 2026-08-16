# ==========================================
# STAGE 1: Entorno de compilación base
# ==========================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_NDK_VERSION=r26b
ENV ANDROID_NDK_HOME=/opt/android-ndk

# Instalar dependencias esenciales de compilación para Mesa
RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    python3-pip \
    python3-setuptools \
    ninja-build \
    bison \
    flex \
    m4 \
    pkg-config \
    unzip \
    wget \
    git \
    glslang-tools \
    && rm -rf /var/lib/apt/lists/*

# Instalar Meson actualizado vía pip
RUN pip3 install meson

# Descargar e instalar Android NDK
RUN wget -q https://google.com{ANDROID_NDK_VERSION}-linux.zip -O /tmp/ndk.zip \
    && unzip -q /tmp/ndk.zip -d /opt \
    && mv /opt/android-ndk-${ANDROID_NDK_VERSION} ${ANDROID_NDK_HOME} \
    && rm /tmp/ndk.zip

WORKDIR /workspace
COPY . .

# ==========================================
# STAGE 2: Compilación de 32 Bits (armv7a)
# ==========================================
FROM builder AS build-32
RUN meson setup build-32 \
    --cross-file android-32.toml \
    --buildtype=release \
    -Dplatforms=android \
    -Dgallium-drivers=zink,swrast \
    -Dvulkan-drivers=freedreno,panfrost,broadcom \
    && ninja -C build-32/

# ==========================================
# STAGE 3: Compilación de 64 Bits (arm64-v8a)
# ==========================================
FROM builder AS build-64
RUN meson setup build-64 \
    --cross-file android-64.toml \
    --buildtype=release \
    -Dplatforms=android \
    -Dgallium-drivers=zink,swrast \
    -Dvulkan-drivers=freedreno,panfrost,broadcom \
    && ninja -C build-64/

# ==========================================
# STAGE 4: Empaquetado final de artefactos
# ==========================================
FROM alpine:latest AS final
WORKDIR /dist

# Copiar librerías resultantes de ambas arquitecturas
COPY --from=build-32 /workspace/build-32/src/vulkan/wsi/libvulkan_wrapper.so ./lib/armeabi-v7a/
COPY --from=build-64 /workspace/build-64/src/vulkan/wsi/libvulkan_wrapper.so ./lib/arm64-v8a/

# Comando por defecto para exportar binarios
CMD ["tar", "-czf", "gamenative-wrappers.tar.gz", "lib/"]
