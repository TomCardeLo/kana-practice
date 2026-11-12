#!/usr/bin/env bash
# Compila Kana firmada con la cuenta gratuita de Apple (equipo RV2VS68Z9R) y la instala en los dispositivos
# emparejados con esta Mac. La firma vence a los 7 días; la renueva a diario deepy_web/ios/scripts/renovar_firmas.sh.
# Uso: ios/scripts/instalar.sh [UDID...]   (por defecto, el iPhone 17 Pro Max y el iPad 9.ª gen. de Tommy)
set -euo pipefail
cd "$(dirname "$0")/.."
UDIDS=("${@:-00008150-000404182247801C 00008030-000929210AE3C02E}")
read -r -a UDIDS <<<"${UDIDS[*]}"

xcodegen generate --quiet
# Destino genérico: no hace falta el dispositivo conectado para compilar (y evita copiar ~11 GB de
# símbolos del iPad a iOS DeviceSupport).
xcodebuild -project Kana.xcodeproj -scheme Kana -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/device -allowProvisioningUpdates build -quiet
APP=build/device/Build/Products/Release-iphoneos/Kana.app
for udid in "${UDIDS[@]}"; do
  if xcrun devicectl device install app --device "$udid" "$APP"; then
    xcrun devicectl device process launch --terminate-existing --device "$udid" com.tommycardelo.kana || true
  else
    echo "No se pudo instalar en $udid (¿bloqueado o fuera de la Wi-Fi?)" >&2
    fallo=1
  fi
done
exit "${fallo:-0}"
