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

shoot() { # nom style apparence [arguments supplémentaires…]
  local name="$1" style="$2" appearance="$3"
  shift 3
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -tribu.demo YES -tribu.style "$style" \
    -tribu.tab home -tribu.person "" -tribu.onboarding "" -tribu.module "" -tribu.cuisine "" -tribu.health NO "$@" >/dev/null
  sleep 4
  xcrun simctl io "$UDID" screenshot "$OUT/${style}-${name}-${appearance}.png" >/dev/null
  echo "  ${style}-${name}-${appearance}.png"
}

for style in frigo album couleurs; do
  shoot home "$style" light
  shoot home "$style" dark
  shoot family-leo "$style" light -tribu.tab family -tribu.person leo
  shoot courses "$style" light -tribu.tab cuisine -tribu.cuisine Courses
  shoot more "$style" light -tribu.tab more
done

style=couleurs
shoot menu "$style" light -tribu.tab cuisine -tribu.cuisine Menu
shoot recettes "$style" light -tribu.tab cuisine -tribu.cuisine Recettes
shoot agenda "$style" light -tribu.tab agenda
shoot rappels "$style" light -tribu.tab more -tribu.module reminders
shoot taches "$style" light -tribu.tab more -tribu.module tasks
shoot depenses "$style" light -tribu.tab more -tribu.module expenses
shoot activites "$style" light -tribu.tab more -tribu.module activities
shoot fil "$style" light -tribu.tab more -tribu.module feed
shoot agenda frigo light -tribu.tab agenda
shoot depenses album light -tribu.tab more -tribu.module expenses
shoot carnet-leo "$style" light -tribu.tab family -tribu.person leo -tribu.health YES
shoot carnet-leo album light -tribu.tab family -tribu.person leo -tribu.health YES
shoot welcome "$style" light -tribu.onboarding welcome
shoot tribe "$style" light -tribu.onboarding tribe
