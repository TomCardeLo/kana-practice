#!/usr/bin/env bash
# E2E completo de la app iOS: paridad Swift↔JS, enganche y XCUITest en iPhone y iPad (con sincronización
# contra un Deepy local: el iPhone sube y luego el iPad baja, por eso el orden importa).
# Evidencia (resultados + capturas): ios/build/e2e/iPhone.xcresult e ios/build/e2e/iPad.xcresult.
# Ábrelos con `open ios/build/e2e/iPhone.xcresult`. Termina con error si algo falla.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/paridad.sh
scripts/comprobar_enganche.sh

DISPOSITIVOS=(
  "iPhone F3091C9D-5A29-4CF7-B6BF-129480732FFD"
  "iPad 5FC510C8-3179-4114-989D-551D974A6EDF"
)
mkdir -p build/e2e
fallos=0

# Deepy local (Postgres embebido) para las pruebas de sincronización: el iPhone sube y el iPad baja.
node scripts/servidor_deepy.mjs >build/e2e/servidor.log 2>&1 &
servidor=$!
trap 'kill "$servidor" 2>/dev/null; wait "$servidor" 2>/dev/null' EXIT
for _ in $(seq 1 120); do grep -q "^LISTO" build/e2e/servidor.log && break; kill -0 "$servidor" 2>/dev/null || break; sleep 1; done
grep -q "^LISTO" build/e2e/servidor.log || { echo "✗ No arrancó el Deepy local (ver build/e2e/servidor.log)"; exit 1; }
echo "✓ Deepy local: $(grep '^LISTO' build/e2e/servidor.log)"

for entrada in "${DISPOSITIVOS[@]}"; do
  read -r nombre udid <<<"$entrada"
  resultado="build/e2e/$nombre.xcresult"
  rm -rf "$resultado"
  echo "▶ XCUITest en $nombre ($udid)"
  # Se prueban los dos dispositivos aunque falle el primero, para tener ambos xcresult.
  if xcodebuild test -project Kana.xcodeproj -scheme Kana -destination "id=$udid" \
      -derivedDataPath build/test -resultBundlePath "$resultado" -parallel-testing-enabled NO \
      -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
      -collect-test-diagnostics never \
      >"build/e2e/$nombre.log" 2>&1; then
    estado="OK"
  else
    estado="FALLA (ver build/e2e/$nombre.log)"
    fallos=1
  fi
  if [[ -d "$resultado" ]]; then
    xcrun xcresulttool get test-results summary --path "$resultado" --compact | python3 -c '
import json, sys
r = json.load(sys.stdin)
print("  %d pasan, %d fallan, %d omitidas" % (r["passedTests"], r["failedTests"], r["skippedTests"]))
for f in r.get("testFailures", []):
    print("  ✗ %s: %s" % (f["testName"], f["failureText"]))
if r["totalTestCount"] == 0:
    sys.exit("  No se ejecutó ninguna prueba")
' || fallos=1
  else
    echo "  No se generó $resultado"
    fallos=1
  fi
  echo "  $nombre: $estado"
done

exit "$fallos"
