#!/usr/bin/env bash
# Comprueba la lógica de rachas, hitos, mensajes y combo (modos de fallo 61–69) y el revisor de trazos (113–123).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Sources/Logica/*.swift Comprobaciones/*.swift -o build/comprobar_enganche
build/comprobar_enganche
