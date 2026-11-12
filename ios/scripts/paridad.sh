#!/usr/bin/env bash
# Regenera el fixture desde los módulos JS y compara la lógica Swift contra él (modo de fallo 47).
set -euo pipefail
cd "$(dirname "$0")/../.."
npm run --silent paridad 2>/dev/null
mkdir -p ios/build
swiftc -O ios/Sources/Logica/*.swift ios/Paridad/main.swift -o ios/build/paridad
ios/build/paridad ios/Paridad/paridad.json
