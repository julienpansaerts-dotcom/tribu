"""Révoque le certificat de développement créé pendant cet envoi TestFlight.

Sur un Mac de GitHub vierge, la signature automatique crée à chaque fois un certificat
« Apple Development » (nommé « Created via API »). Apple en limite le nombre : on supprime
uniquement ceux créés il y a moins de 3 heures par l'API, sans toucher aux autres
(par exemple ceux d'AltStore ou d'un Mac). Autorisé par le propriétaire du compte.
"""
import datetime
import json
import os
import sys
import time
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    now = int(time.time())
    with open(os.environ["KEY_PATH"]) as f:
        key = f.read()
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        return json.loads(body) if body else None


def main():
    data = call("GET", "/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200")
    now = datetime.datetime.now(datetime.timezone.utc)
    removed = 0
    for cert in data.get("data", []):
        attrs = cert["attributes"]
        label = f'{attrs.get("name") or ""} {attrs.get("displayName") or ""}'.strip()
        expires = datetime.datetime.fromisoformat(attrs["expirationDate"].replace("Z", "+00:00"))
        created = expires - datetime.timedelta(days=365)
        if "Created via API" in label and now - created < datetime.timedelta(hours=3):
            call("DELETE", f'/certificates/{cert["id"]}')
            removed += 1
            print(f"Révoqué : {label} ({cert['id']})")
    print(f"{removed} certificat(s) de développement temporaire(s) révoqué(s).")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # le nettoyage ne doit jamais faire échouer l'envoi
        print(f"Nettoyage impossible : {error}", file=sys.stderr)
