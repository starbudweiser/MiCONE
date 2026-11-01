"""Mise à jour automatique de MiCONE par les releases GitHub (starbudweiser/MiCONE).

Une requête au plus par jour. Quand une version plus récente existe : téléchargement de MiCONE-X.Y.Z.zip, contrôle
(identifiant, version annoncée, signature intacte, même exigence de signature que l'appli en cours), puis script
qui remplace le paquet et relance l'appli. Aucune requête hors de api.github.com et de son stockage de fichiers.
"""
from __future__ import annotations

import json
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from PyQt6.QtCore import QObject, QSettings, pyqtSignal

import version as version_source

DEPOT = "starbudweiser/MiCONE"
PREFIXE = "MiCONE-"
JOUR = 24 * 3600
HOTE_API = "api.github.com"


def parse_version(texte: str) -> tuple:
    """x, x.y ou x.y.z (préfixe v et suffixe -beta ignorés) → (x, y, z) ; () si illisible."""
    brut = str(texte or "").strip()
    if brut[:1] in "vV":
        brut = brut[1:]
    brut = brut.split("-")[0]
    parts = brut.split(".")
    if not 1 <= len(parts) <= 3 or not all(p.isdigit() for p in parts):
        return ()
    return tuple(int(p) for p in parts) + (0,) * (3 - len(parts))


def est_plus_recente(derniere: str, courante: str) -> bool:
    a, b = parse_version(derniere), parse_version(courante)
    return bool(a and b and a > b)


@dataclass(frozen=True)
class Release:
    tag: str
    version: str
    url: str
    nom: str


def analyser_release(donnees: bytes, prefixe: str = PREFIXE) -> Release | None:
    """Réponse de GET /repos/<dépôt>/releases/latest → Release ; rien pour un brouillon, une préversion ou sans archive."""
    try:
        j = json.loads(donnees)
    except ValueError:
        return None
    if not isinstance(j, dict) or j.get("draft") or j.get("prerelease"):
        return None
    tag = str(j.get("tag_name") or "")
    v = parse_version(tag)
    if not v:
        return None
    for asset in j.get("assets") or []:
        nom, url = str(asset.get("name") or ""), str(asset.get("url") or "")
        p = urlparse(url)
        if nom.startswith(prefixe) and nom.endswith(".zip") and p.scheme == "https" and p.hostname == HOTE_API:
            return Release(tag, ".".join(map(str, v)), url, nom)
    return None


def script_installation(pid: int, nouvelle: str, destination: str, relancer: bool) -> str:
    """Script lancé à part : attend la fin de l'appli, remplace le paquet (le remet si la copie échoue), relance si demandé."""
    q = shlex.quote
    ancienne = destination + ".old"
    relance = f"/usr/bin/open -g {q(destination)}\n" if relancer else ""
    return (
        "#!/bin/sh\n"
        f"while kill -0 {int(pid)} 2>/dev/null; do sleep 0.2; done\n"
        f"rm -rf {q(ancienne)}\n"
        f"mv {q(destination)} {q(ancienne)} || exit 1\n"
        f"if /usr/bin/ditto {q(nouvelle)} {q(destination)}; then\n"
        f"    rm -rf {q(ancienne)} {q(nouvelle)}\n"
        "else\n"
        f"    rm -rf {q(destination)}; mv {q(ancienne)} {q(destination)}\n"
        "fi\n"
        f"/usr/bin/xattr -cr {q(destination)} 2>/dev/null\n"
        f"{relance}"
    )


# --------------------------------------------------------------------------- appli en cours

def chemin_app() -> Path | None:
    """MiCONE.app en cours d'exécution, ou None en développement."""
    exe = Path(sys.executable).resolve()
    if exe.parent.name == "MacOS" and exe.parents[1].name == "Contents" and exe.parents[2].suffix == ".app":
        return exe.parents[2]
    return None


def infos_bundle(app: Path | None = None) -> dict:
    app = app or chemin_app()
    if app is None:
        return {}
    try:
        with (app / "Contents" / "Info.plist").open("rb") as f:
            return plistlib.load(f)
    except (OSError, plistlib.InvalidFileException):
        return {}


def version_courante() -> tuple[str, str]:
    """(version, build) lus dans l'Info.plist de l'appli compilée, sinon dans version.py."""
    info = infos_bundle()
    return (str(info.get("CFBundleShortVersionString") or version_source.__version__),
            str(info.get("CFBundleVersion") or version_source.__build__))


def _lancer(*args: str) -> tuple[int, str]:
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.SubprocessError):
        return -1, ""
    return r.returncode, r.stdout + r.stderr


def exigence(app: Path | str) -> str | None:
    """Exigence de signature désignée de l'appli (identifiant + certificat)."""
    code, sortie = _lancer("/usr/bin/codesign", "-d", "-r-", str(app))
    return next((l for l in sortie.splitlines() if l.startswith("designated =>")), None) if code == 0 else None


def preparer(archive: Path, version_attendue: str, id_attendu: str, exigence_attendue: str | None) -> Path | None:
    """Décompresse l'archive puis contrôle identifiant, version, signature et exigence. Renvoie MiCONE.app ou None."""
    dossier = Path(tempfile.mkdtemp(prefix="micone-maj-"))
    code, _ = _lancer("/usr/bin/ditto", "-x", "-k", str(archive), str(dossier))
    app = dossier / "MiCONE.app"
    if code == 0 and app.is_dir():
        info = infos_bundle(app)
        v = parse_version(str(info.get("CFBundleShortVersionString") or ""))
        if (info.get("CFBundleIdentifier") == id_attendu and v and v == parse_version(version_attendue)
                and exigence_attendue and exigence(app) == exigence_attendue
                and _lancer("/usr/bin/codesign", "--verify", "--strict", "--deep", str(app))[0] == 0):
            return app
    shutil.rmtree(dossier, ignore_errors=True)
    return None


# --------------------------------------------------------------------------- réseau

def jeton_github() -> str | None:
    """Jeton `gh` de l'utilisateur, seulement si le dépôt n'est pas lisible sans (dépôt privé)."""
    for gh in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh"):
        if Path(gh).is_file():
            code, sortie = _lancer(gh, "auth", "token")
            if code == 0 and sortie.strip():
                return sortie.strip()
    return None


class _SansJetonHorsGitHub(urllib.request.HTTPRedirectHandler):
    """N'envoie pas le jeton GitHub au stockage de fichiers vers lequel GitHub redirige."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        nouvelle = super().redirect_request(req, fp, code, msg, headers, newurl)
        if nouvelle is not None and urlparse(newurl).hostname != HOTE_API:
            nouvelle.headers.pop("Authorization", None)
            nouvelle.unredirected_hdrs.pop("Authorization", None)
        return nouvelle


def _ouvrir(url: str, accept: str, jeton: str | None, delai: float = 20.0):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "MiCONE-updater"})
    if jeton:
        req.add_header("Authorization", f"Bearer {jeton}")
    return urllib.request.build_opener(_SansJetonHorsGitHub).open(req, timeout=delai)


def derniere_release(depot: str = DEPOT) -> tuple[str, Release | None, str | None]:
    """('release', Release, jeton) | ('aucune', None, jeton) | ('echec', None, None). Sans jeton d'abord ; `gh` en repli sur 404."""
    url = f"https://{HOTE_API}/repos/{depot}/releases/latest"
    accept = "application/vnd.github+json"
    jeton = None
    for essai in (0, 1):
        try:
            with _ouvrir(url, accept, jeton) as r:
                rel = analyser_release(r.read())
                return ("release", rel, jeton) if rel else ("aucune", None, jeton)
        except urllib.error.HTTPError as e:
            if e.code == 404 and essai == 0 and (jeton := jeton_github()):
                continue
            return ("aucune", None, jeton) if e.code == 404 else ("echec", None, None)
        except (OSError, ValueError):
            return ("echec", None, None)
    return ("echec", None, None)


def telecharger(release: Release, jeton: str | None) -> Path | None:
    cible = Path(tempfile.mkdtemp(prefix="micone-dl-")) / release.nom
    try:
        with _ouvrir(release.url, "application/octet-stream", jeton, delai=60) as r, cible.open("wb") as f:
            shutil.copyfileobj(r, f)
        return cible
    except (OSError, ValueError):
        shutil.rmtree(cible.parent, ignore_errors=True)
        return None


# --------------------------------------------------------------------------- objet Qt

class MiseAJour(QObject):
    """Recherche et installation hors du fil principal ; les résultats reviennent par `etat`.

    etat(clé, release, manuel) : a_jour | disponible | installation | differee | echec_reseau | echec_verif | echec_install
    """
    etat = pyqtSignal(str, object, bool)

    def __init__(self, reglages: QSettings):
        super().__init__()
        self.reglages = reglages
        self._occupe = False
        self._jeton: str | None = None

    @property
    def auto(self) -> bool:
        return self.reglages.value("maj/auto", True) in (True, "true")

    @auto.setter
    def auto(self, valeur: bool) -> None:
        self.reglages.setValue("maj/auto", bool(valeur))

    def verifier(self, manuel: bool = False) -> None:
        if self._occupe:
            return
        if not manuel:
            if chemin_app() is None:
                return
            derniere = float(self.reglages.value("maj/verifie", 0) or 0)
            if time.time() - derniere < JOUR:
                return
        self._occupe = True
        threading.Thread(target=self._verifier, args=(manuel,), daemon=True).start()

    def _verifier(self, manuel: bool) -> None:
        try:
            statut, release, self._jeton = derniere_release()
            if statut == "echec":
                self.etat.emit("echec_reseau", None, manuel)
                return
            self.reglages.setValue("maj/verifie", time.time())
            if release and est_plus_recente(release.version, version_courante()[0]):
                self.etat.emit("disponible", release, manuel)
            else:
                self.etat.emit("a_jour", release, manuel)
        finally:
            self._occupe = False

    def installer(self, release: Release, relancer: bool, manuel: bool = False) -> None:
        if self._occupe:
            return
        self._occupe = True
        threading.Thread(target=self._installer, args=(release, relancer, manuel), daemon=True).start()

    def _installer(self, release: Release, relancer: bool, manuel: bool) -> None:
        try:
            app = chemin_app()
            if app is None or not app.parent.is_dir() or not _ecriture_possible(app.parent):
                self.etat.emit("echec_install", release, manuel)
                return
            archive = telecharger(release, self._jeton)
            if archive is None:
                self.etat.emit("echec_reseau", release, manuel)
                return
            preparee = preparer(archive, release.version, str(infos_bundle().get("CFBundleIdentifier") or ""), exigence(app))
            shutil.rmtree(archive.parent, ignore_errors=True)
            if preparee is None:
                self.etat.emit("echec_verif", release, manuel)
                return
            if not _lancer_installateur(app, preparee, relancer):
                self.etat.emit("echec_install", release, manuel)
                return
            self.etat.emit("installation" if relancer else "differee", release, manuel)
        finally:
            self._occupe = False


def _ecriture_possible(dossier: Path) -> bool:
    import os
    return os.access(dossier, os.W_OK)


def _lancer_installateur(app: Path, nouvelle: Path, relancer: bool) -> bool:
    import os
    script = Path(tempfile.mkdtemp(prefix="micone-install-")) / "installer.sh"
    script.write_text(script_installation(os.getpid(), str(nouvelle), str(app), relancer), encoding="utf-8")
    try:
        subprocess.Popen(["/bin/sh", str(script)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        return False
    return True
