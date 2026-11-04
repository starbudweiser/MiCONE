"""Lien dynamique avec iCONIQ (bibliothèque d'icônes) : chaque icône créée est déposée dans la boîte de réception d'iCONIQ.

iCONIQ surveille ce dossier : il range l'icône dans sa collection « MiCONE », ou met à jour sur place celle déjà suivie
pour la même origine (même fichier exporté). Si iCONIQ n'est pas lancé, il est démarré en arrière-plan, sans prendre le focus.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid

BUNDLE_ID = "fr.stephan.iconiq"
RACINE = os.path.expanduser("~/Library/Application Support/iCONIQ")
BOITE = os.path.join(RACINE, "Inbox")
APPLIS = [os.path.expanduser("~/Applications/Applications Personnelles/iCONIQ.app"), "/Applications/iCONIQ.app"]


def installee() -> bool:
    return os.path.isdir(RACINE) or any(os.path.isdir(a) for a in APPLIS)


def envoyer(nom: str, fichier: str, origine: str, genre: str = "app") -> bool:
    """Dépose `fichier` (.icns ou .png) dans la boîte d'iCONIQ. `origine` identifie le lien (chemin de l'export)."""
    if not installee() or not os.path.isfile(fichier):
        return False
    try:
        os.makedirs(BOITE, exist_ok=True)
        ident = uuid.uuid4().hex
        copie = f"{ident}{os.path.splitext(fichier)[1].lower()}"
        shutil.copyfile(fichier, os.path.join(BOITE, copie))
        # le descripteur est écrit en dernier et d'un coup : iCONIQ ne lit jamais un fichier incomplet
        tmp = os.path.join(BOITE, f".{ident}.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"name": nom, "file": copie, "origin": origine, "kind": genre, "source": "MiCONE"}, f)
        os.replace(tmp, os.path.join(BOITE, f"{ident}.json"))
    except OSError:
        return False
    subprocess.Popen(["/usr/bin/open", "-g", "-b", BUNDLE_ID], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True
