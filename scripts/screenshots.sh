#!/usr/bin/env bash
# Lance l'app dans le simulateur iPhone et prend des captures d'écran de chaque ambiance.
# Usage : scripts/screenshots.sh <chemin/Tribu.app> [dossier de sortie]
set -euo pipefail
APP="$1"
OUT="${2:-screenshots}"
BUNDLE="tribu"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1]))
    for d in devices:
        if re.search(r"iPhone \d+ Pro Max", d["name"]):
            key = (version, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"])
print(best[1] if best else "")
')
if [ -z "$UDID" ]; then echo "Aucun simulateur iPhone Pro Max disponible"; exit 1; fi
echo "Simulateur : $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

shoot() { # style tab appearance [personne]
  local style="$1" tab="$2" appearance="$3" person="${4:-}"
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [ -n "$person" ]; then
    xcrun simctl launch "$UDID" "$BUNDLE" -tribu.style "$style" -tribu.tab "$tab" -tribu.person "$person" >/dev/null
  else
    xcrun simctl launch "$UDID" "$BUNDLE" -tribu.style "$style" -tribu.tab "$tab" -tribu.person "" >/dev/null
  fi
  sleep 4
  local name="${style}-${tab}${person:+-$person}-${appearance}.png"
  xcrun simctl io "$UDID" screenshot "$OUT/$name" >/dev/null
  echo "  $name"
}

for style in frigo album couleurs; do
  shoot "$style" home light
  shoot "$style" family light leo
  shoot "$style" more light
  shoot "$style" home dark
done
