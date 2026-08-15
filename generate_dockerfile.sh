#!/bin/bash
set -e
cat << 'EOF' > Dockerfile
FROM ghcr.io/termux/package-builder:latest
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ninja-build && pip3 install --break-system-packages --ignore-installed --no-cache-dir meson ninja mako pyyaml packaging
RUN T='https://packages-cf.termux.dev/apt/termux-main' && P='libdrm libandroid-shmem libxcb libx11 libxshmfence libxext libxrandr libxrender xorgproto libxau libxdmcp' && 
mkdir -p /tmp/s64 && cd /tmp/s64 && curl -s "$T/dists/stable/main/binary-aarch64/Packages" > Pk && for p in $P; do path=(awk -v p="Package: p" '$0==p{f=1} f && /^Filename:/{print 2; exit}' Pk) && [ -n "path" ] && curl -L -O "T/path"; done && mkdir -p /data/data/com.termux/files/usr && for f in *.deb; do [ -f "
𝑓

"

]

𝑑𝑝𝑘𝑔

−𝑑𝑒𝑏

−𝑥

"
f" /; done && 
mkdir -p /tmp/s32 && cd /tmp/s32 && curl -s "$T/dists/stable/main/binary-arm/Packages" > Pk && for p in $P; do path=(awk -v p="Package: p" '$0==p{f=1} f && /^Filename:/{print 2; exit}' Pk) && [ -n "path" ] && curl -L -O "T/path"; done && mkdir -p /tmp/ex && for f in *.deb; do [ -f "
𝑓

"

]

𝑑𝑝𝑘𝑔

−𝑑𝑒𝑏

−𝑥

"
f" /tmp/ex; done && mkdir -p /data/data/com.termux/files/usr/lib/arm-linux-androideabi && cp -r /tmp/ex/data/data/com.termux/files/usr/include/* /data/data/com.termux/files/usr/include/ 2>/dev/null || true && cp -r /tmp/ex/data/data/com.termux/files/usr/lib/* /data/data/com.termux/files/usr/lib/arm-linux-androideabi/ 2>/dev/null || true && 
rm -rf /tmp/s64 /tmp/s32 /tmp/ex
RUN mkdir -p /root/build-config
COPY bin_hijack/cross_aarch64.txt /root/build-config/cross_aarch64.txt
COPY bin_hijack/cross_arm.txt /root/build-config/cross_arm.txt
COPY bin_hijack/build.sh /root/build.sh
COPY bin_hijack/bridge.c /root/bridge.c
RUN chmod +x /root/build.sh
WORKDIR /workspace
ENTRYPOINT ["/root/build.sh"]
EOF
echo "-> Dockerfile generado correctamente."
