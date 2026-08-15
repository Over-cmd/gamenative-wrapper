#!/bin/bash
set -e

# VARIABLES MOVIDAS DESDE EL YAML PARA EVITAR ERRORES SINTÁCTICOS
CUSTOM_TAG="gamenative-unisoc-builder:latest"
BUILD_DIR_64="b_64"
BUILD_DIR_32="b_32"
GITHUB_WORKSPACE=$(pwd)

echo "-> 1. Construyendo la imagen Docker Custom..."
docker build -t "$CUSTOM_TAG" .
# ... (el resto del código de tu script run_pipeline.sh idéntico a como lo tenías)
