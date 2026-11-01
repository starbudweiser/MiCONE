"""Génération d'icônes par IA : fournisseurs, conversation, trousseau macOS et détourage.

Fournisseurs :
- pollinations : gratuit sans clé (logo incrusté, 1 image / 45 s) ; clé facultative pour lever ces limites.
- huggingface : clé gratuite (crédits mensuels), FLUX. Comme Pollinations, la conversation est rejouée
  en un seul prompt avec la même graine.
- gemini : clé Google AI Studio. Chaque tour envoie la dernière image + la consigne (retouche).
- openai : clé OpenAI (payant). Fond transparent natif ; les tours suivants passent par /images/edits.
"""
from __future__ import annotations

import base64
import json
import os
import random
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid

import numpy as np
from PyQt6.QtCore import QBuffer, QByteArray, QIODevice, QThread, pyqtSignal
from PyQt6.QtGui import QImage

from textes import t

FOURNISSEURS = {
    "pollinations": {"cle": False, "facultative": True, "modele": "flux", "transparent": False,
                     "lien": "https://enter.pollinations.ai"},
    "huggingface": {"cle": True, "modele": "black-forest-labs/FLUX.1-schnell", "transparent": False,
                    "lien": "https://huggingface.co/settings/tokens"},
    "gemini": {"cle": True, "modele": "gemini-2.5-flash-image", "transparent": False,
               "lien": "https://aistudio.google.com/apikey"},
    "openai": {"cle": True, "modele": "gpt-image-1", "transparent": True,
               "lien": "https://platform.openai.com/api-keys"},
}

# Modèles proposés dans la liste (le champ reste modifiable pour un modèle plus récent).
MODELES = {
    "pollinations": ["flux", "turbo"],
    "huggingface": ["black-forest-labs/FLUX.1-schnell", "black-forest-labs/FLUX.1-dev",
                    "stabilityai/stable-diffusion-xl-base-1.0"],
    "gemini": ["gemini-2.5-flash-image", "gemini-3-pro-image-preview"],
    "openai": ["gpt-image-1", "gpt-image-1-mini"],
}


def detecter(cle: str) -> str | None:
    """Service probable d'une clé d'après son préfixe ; « anthropic » pour une clé Claude."""
    cle = cle.strip()
    for prefixe, service in (("sk-ant-", "anthropic"), ("AIza", "gemini"), ("hf_", "huggingface"),
                             ("sk_", "pollinations"), ("pk_", "pollinations"), ("sk-", "openai")):
        if cle.startswith(prefixe):
            return service
    return None


STYLES = {
    "3d": ("a polished glossy 3D object in the style of modern macOS app icons, soft studio lighting, "
           "subtle reflections", "white"),
    "plat": ("a flat minimalist vector illustration, bold simple shapes, limited vivid palette", "white"),
    "glyphe": ("a single solid white glyph symbol, minimal line-free silhouette", "black"),
    # Style des icônes des outils Skyrim (case « Style flat vectoriel »).
    "flat": ("a clean flat vector pictogram in the spirit of modern macOS Big Sur icon symbols: one bold, simple, "
             "instantly readable pictogram built from geometric shapes, two or three vivid saturated colors "
             "(such as orange, sky blue, green, yellow or red) combined with white, crisp sharp edges, "
             "a very subtle soft gradient on each shape and a soft drop shadow beneath, no outlines, "
             "no texture, no photorealism, no fine details, legible even at 16 pixels",
             "medium grey (#808080)"),
}

TIMEOUT = 180


class ErreurIA(Exception):
    pass


# ---------------------------------------------------------------- trousseau

def lire_cle(fournisseur: str) -> str:
    r = subprocess.run(["security", "find-generic-password", "-s", "MiCONE", "-a", fournisseur, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def ecrire_cle(fournisseur: str, cle: str) -> None:
    if cle:
        subprocess.run(["security", "add-generic-password", "-U", "-s", "MiCONE", "-a", fournisseur,
                        "-l", f"MiCONE — {fournisseur}", "-w", cle], capture_output=True, check=True)
    else:
        subprocess.run(["security", "delete-generic-password", "-s", "MiCONE", "-a", fournisseur],
                       capture_output=True)


# ---------------------------------------------------------------- prompt

def _fond_txt(style: str, transparent: bool) -> str:
    _, fond = STYLES.get(style, STYLES["3d"])
    return ("on a fully transparent background" if transparent
            else f"isolated on a plain, uniform, pure {fond} background (flat solid color, no gradient)")


def consigne(demandes: list[str], style: str, transparent: bool) -> str:
    """Prompt complet (en anglais) : la demande de l'utilisateur d'abord et prioritaire, le style ensuite."""
    desc, _ = STYLES.get(style, STYLES["3d"])
    texte = f"Create an icon symbol. MAIN REQUEST (highest priority): {demandes[0]}."
    if demandes[1:]:
        texte += (" Then apply these changes, in this order; each one overrides anything before it: "
                  + "; ".join(demandes[1:]) + ".")
    texte += (f" Style guidelines, to follow only where the request above does not say otherwise: {desc}."
              f" Composition: one single centered subject {_fond_txt(style, transparent)}, generous empty margin"
              " around it, no text, no letters, no frame, no border, no background shape, no tile, no badge,"
              " no rounded square, no circle behind it.")
    return texte


def consigne_retouche(demande: str, historique: list[str], style: str, transparent: bool) -> str:
    """Retouche de l'image jointe : la nouvelle demande doit se voir nettement."""
    contexte = f" Earlier requests in this conversation, for context: {'; '.join(historique)}." if historique else ""
    return (f"Modify the attached icon according to this NEW REQUEST: {demande}. "
            "This new request has priority over the current image and over any earlier style: the change must be "
            "clearly visible; redraw the subject entirely if that is what it takes. Do not return an image that "
            f"looks the same as before.{contexte} Keep one single centered subject {_fond_txt(style, transparent)}, "
            "no text, no frame, no tile, no rounded square.")


# ---------------------------------------------------------------- réseau

def _png(img: QImage) -> bytes:
    ba = QByteArray()
    buf = QBuffer(ba)
    buf.open(QIODevice.OpenModeFlag.WriteOnly)
    img.save(buf, "PNG")
    return bytes(ba)


def _image(donnees: bytes) -> QImage:
    img = QImage.fromData(donnees)
    if img.isNull():
        raise ErreurIA(t("ia_err_image"))
    return img.convertToFormat(QImage.Format.Format_ARGB32_Premultiplied)


def _requete(url: str, donnees: bytes | None = None, entetes: dict | None = None) -> bytes:
    req = urllib.request.Request(url, data=donnees, headers={"User-Agent": "MiCONE/1.0", **(entetes or {})})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        corps = e.read().decode("utf-8", "replace")
        try:
            msg = json.loads(corps).get("error", {})
            msg = msg.get("message", "") if isinstance(msg, dict) else str(msg)
        except (ValueError, AttributeError):
            msg = corps[:200]
        if e.code in (401, 403):
            raise ErreurIA(t("ia_err_cle", code=e.code, msg=msg))
        if e.code == 402 and "pollinations" in url:
            raise ErreurIA(t("ia_err_gratuit"))
        if e.code == 429:
            raise ErreurIA(t("ia_err_429", msg=msg))
        raise ErreurIA(t("ia_err_http", code=e.code, msg=msg))
    except (urllib.error.URLError, TimeoutError) as e:
        raise ErreurIA(t("ia_err_reseau", raison=getattr(e, "reason", e)))


def _pollinations(prompt: str, graine: int, modele: str, cle: str = "") -> QImage:
    params = {"width": 1024, "height": 1024, "nologo": "true", "seed": graine}
    if modele:
        params["model"] = modele
    base = "https://gen.pollinations.ai/image/" if cle else "https://image.pollinations.ai/prompt/"
    url = base + urllib.parse.quote(prompt, safe="") + "?" + urllib.parse.urlencode(params)
    return _image(_requete(url, entetes={"Authorization": f"Bearer {cle}"} if cle else None))


def _huggingface(prompt: str, graine: int, modele: str, cle: str) -> QImage:
    corps = {"inputs": prompt, "parameters": {"width": 1024, "height": 1024, "seed": graine}}
    url = f"https://router.huggingface.co/hf-inference/models/{modele}"
    return _image(_requete(url, json.dumps(corps).encode(),
                           {"Authorization": f"Bearer {cle}", "Content-Type": "application/json",
                            "Accept": "image/png"}))


def _gemini(prompt: str, precedente: QImage | None, cle: str, modele: str) -> QImage:
    parts = [{"text": prompt}]
    if precedente is not None:
        parts.append({"inline_data": {"mime_type": "image/png",
                                      "data": base64.b64encode(_png(precedente)).decode()}})
    corps = {"contents": [{"role": "user", "parts": parts}],
             "generationConfig": {"responseModalities": ["TEXT", "IMAGE"],
                                  "imageConfig": {"aspectRatio": "1:1"}}}
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{modele}:generateContent"
    rep = json.loads(_requete(url, json.dumps(corps).encode(),
                              {"Content-Type": "application/json", "x-goog-api-key": cle}))
    texte = ""
    for cand in rep.get("candidates", []):
        for p in cand.get("content", {}).get("parts", []):
            d = p.get("inlineData") or p.get("inline_data")
            if d and d.get("data"):
                return _image(base64.b64decode(d["data"]))
            texte += p.get("text", "")
    raison = rep.get("promptFeedback", {}).get("blockReason") or texte.strip()[:200]
    raise ErreurIA(t("ia_err_aucune", service="Gemini", raison=raison))


def _multipart(champs: dict, fichiers: dict) -> tuple[bytes, str]:
    limite = uuid.uuid4().hex
    out = b""
    for k, v in champs.items():
        out += (f"--{limite}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n").encode()
    for k, (nom, donnees, type_) in fichiers.items():
        out += (f"--{limite}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{nom}\"\r\n"
                f"Content-Type: {type_}\r\n\r\n").encode() + donnees + b"\r\n"
    return out + f"--{limite}--\r\n".encode(), f"multipart/form-data; boundary={limite}"


def _openai(prompt: str, precedente: QImage | None, cle: str, modele: str) -> QImage:
    auth = {"Authorization": f"Bearer {cle}"}
    if precedente is None:
        corps = {"model": modele, "prompt": prompt, "size": "1024x1024", "n": 1}
        if modele.startswith("gpt-image"):
            corps["background"] = "transparent"
        rep = _requete("https://api.openai.com/v1/images/generations", json.dumps(corps).encode(),
                       {**auth, "Content-Type": "application/json"})
    else:
        champs = {"model": modele, "prompt": prompt, "size": "1024x1024", "n": "1"}
        if modele.startswith("gpt-image"):
            champs["background"] = "transparent"
        donnees, type_ = _multipart(champs, {"image": ("icone.png", _png(precedente), "image/png")})
        rep = _requete("https://api.openai.com/v1/images/edits", donnees, {**auth, "Content-Type": type_})
    data = json.loads(rep).get("data") or [{}]
    if data[0].get("b64_json"):
        return _image(base64.b64decode(data[0]["b64_json"]))
    if data[0].get("url"):
        return _image(_requete(data[0]["url"]))
    raise ErreurIA(t("ia_err_aucune", service="OpenAI", raison=""))


# ---------------------------------------------------------------- traduction

def _traduire_google(texte: str) -> tuple[str, str]:
    url = ("https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q="
           + urllib.parse.quote(texte))
    rep = json.loads(_requete(url))
    return "".join(seg[0] for seg in rep[0] if seg and seg[0]), rep[2] or "?"


def _traduire_llm(texte: str, fournisseur: str, cle: str) -> str:
    consigne_t = ("Translate the following image request into natural English. Keep proper nouns. "
                  "Reply with the translation only.\n\n" + texte)
    if fournisseur == "gemini":
        corps = {"contents": [{"role": "user", "parts": [{"text": consigne_t}]}]}
        url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        rep = json.loads(_requete(url, json.dumps(corps).encode(),
                                  {"Content-Type": "application/json", "x-goog-api-key": cle}))
        return rep["candidates"][0]["content"]["parts"][0]["text"].strip()
    corps = {"model": "gpt-4.1-mini", "messages": [{"role": "user", "content": consigne_t}]}
    rep = json.loads(_requete("https://api.openai.com/v1/chat/completions", json.dumps(corps).encode(),
                              {"Authorization": f"Bearer {cle}", "Content-Type": "application/json"}))
    return rep["choices"][0]["message"]["content"].strip()


def traduire(texte: str, fournisseur: str = "", cle: str = "") -> str:
    """Traduit la demande en anglais (les modèles d'image le comprennent mieux).

    Google Traduction (gratuit, langue détectée) d'abord ; à défaut, Gemini ou OpenAI si une clé
    est disponible ; en dernier recours, le texte d'origine.
    """
    try:
        anglais, langue = _traduire_google(texte)
        return texte if langue == "en" else (anglais or texte)
    except Exception:
        pass
    if cle and fournisseur in ("gemini", "openai"):
        try:
            return _traduire_llm(texte, fournisseur, cle) or texte
        except Exception:
            pass
    return texte


# ---------------------------------------------------------------- détourage

def detourer(img: QImage, tolerance: float = 40.0) -> QImage:
    """Rend transparent le fond relié aux bords, à la manière d'une baguette magique.

    Le remplissage avance d'un pixel à son voisin tant que la couleur change peu : il suit les fonds
    en dégradé et s'arrête net au contour du sujet. Bords adoucis, teinte du fond retirée des bords.
    """
    img = img.convertToFormat(QImage.Format.Format_RGBA8888)
    w, h = img.width(), img.height()
    a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
    a = a.reshape(h, img.bytesPerLine())[:, :w * 4].reshape(h, w, 4).astype(np.float32)
    rgb = a[..., :3]
    vide = a[..., 3] < 200
    if vide.any() and not vide.all():
        # Icône déjà posée sur une plaque (coins transparents) : la plaque est le fond, et la
        # graine est la bande opaque qui longe la transparence (reflets de bord compris).
        bande = vide.copy()
        for _ in range(max(3, min(w, h) // 40)):
            d = bande.copy()
            d[1:] |= bande[:-1]
            d[:-1] |= bande[1:]
            d[:, 1:] |= bande[:, :-1]
            d[:, :-1] |= bande[:, 1:]
            bande = d
        graine = bande & ~vide
        fond = np.median(rgb[graine], axis=0)
        zone = graine | vide
    else:
        bord = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
        fond = np.median(bord, axis=0)
        zone = None
    pas = tolerance / 5                                   # écart toléré entre deux voisins
    ok_v = np.sqrt(((rgb[1:] - rgb[:-1]) ** 2).sum(axis=2)) < pas
    ok_h = np.sqrt(((rgb[:, 1:] - rgb[:, :-1]) ** 2).sum(axis=2)) < pas
    loin = np.sqrt(((rgb - fond) ** 2).sum(axis=2)) < tolerance * 5   # garde-fou global
    if zone is None:
        zone = np.zeros((h, w), bool)
        for sl in (np.s_[0, :], np.s_[-1, :], np.s_[:, 0], np.s_[:, -1]):
            zone[sl] = loin[sl]
    else:
        loin |= zone
    for _ in range(6000):
        g = zone.copy()
        g[1:] |= zone[:-1] & ok_v
        g[:-1] |= zone[1:] & ok_v
        g[:, 1:] |= zone[:, :-1] & ok_h
        g[:, :-1] |= zone[:, 1:] & ok_h
        g &= loin
        if np.array_equal(g, zone):
            break
        zone = g
    # Bords adoucis : flou 3 × 3 répété sur le masque.
    alpha = (~zone).astype(np.float32)
    for _ in range(2):
        p = np.pad(alpha, 1, mode="edge")
        alpha = sum(p[dy:dy + h, dx:dx + w] for dy in range(3) for dx in range(3)) / 9
    al = np.maximum(alpha, 1e-3)[..., None]
    rgb2 = np.where(al < 1, np.clip((rgb - fond * (1 - al)) / al, 0, 255), rgb)
    out = np.dstack([rgb2, alpha * a[..., 3]]).astype(np.uint8)
    res = QImage(out.tobytes(), w, h, w * 4, QImage.Format.Format_RGBA8888).copy()
    return res.convertToFormat(QImage.Format.Format_ARGB32_Premultiplied)


def _outil_detourage() -> str | None:
    for dossier in (getattr(sys, "_MEIPASS", ""),
                    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "outils")):
        chemin = os.path.join(dossier, "detourage")
        if dossier and os.access(chemin, os.X_OK):
            return chemin
    return None


def detourer_auto(img: QImage) -> QImage:
    """Détourage automatique : plaque d'icône retirée par la baguette ; sinon le sujet est isolé
    par Vision (macOS, sur la machine) ; à défaut de sujet reconnu, retour à la baguette."""
    a = img.convertToFormat(QImage.Format.Format_ARGB32)
    w, h = a.width() - 1, a.height() - 1
    if all(a.pixelColor(x, y).alpha() < 200 for x, y in ((0, 0), (w, 0), (0, h), (w, h))):
        return detourer(img)
    outil = _outil_detourage()
    if outil:
        with tempfile.TemporaryDirectory(prefix="micone_") as tmp:
            entree, sortie = os.path.join(tmp, "e.png"), os.path.join(tmp, "s.png")
            if img.save(entree, "PNG"):
                res = subprocess.run([outil, entree, sortie], capture_output=True, timeout=120)
                if res.returncode == 0:
                    sujet = QImage(sortie)
                    if not sujet.isNull():
                        return sujet.convertToFormat(QImage.Format.Format_ARGB32_Premultiplied)
    return detourer(img)


# ---------------------------------------------------------------- conversation

class Conversation:
    def __init__(self):
        self.demandes: list[str] = []
        self.images: list[QImage] = []
        self.graine = random.randint(1, 10 ** 6)
        self.dernier_prompt = ""

    def generer(self, demande: str, fournisseur: str, style: str, cle: str, modele: str,
                traduire_en: bool = True, signaler=None, retoucher: bool = True) -> QImage:
        info = FOURNISSEURS[fournisseur]
        if info["cle"] and not cle:
            raise ErreurIA(t("ia_err_cle_requise"))
        if traduire_en:
            anglais = traduire(demande, fournisseur, cle)
            if signaler and anglais.strip() != demande.strip():
                signaler(anglais)
            demande = anglais
        modele = modele or info["modele"]
        if not retoucher:                       # nouvelle image : on oublie le fil précédent
            self.demandes, self.images = [], []
            self.graine = random.randint(1, 10 ** 6)
        precedente = self.images[-1] if self.images else None
        demandes = self.demandes + [demande]
        if fournisseur in ("pollinations", "huggingface"):
            # Pas de retouche d'image : la conversation est rejouée en un seul prompt.
            p = consigne(demandes, style, False)
            img = (_pollinations(p, self.graine, modele, cle) if fournisseur == "pollinations"
                   else _huggingface(p, self.graine, modele, cle))
        elif precedente is None:
            p = consigne(demandes, style, info["transparent"])
            img = _gemini(p, None, cle, modele) if fournisseur == "gemini" else _openai(p, None, cle, modele)
        else:
            p = consigne_retouche(demande, self.demandes, style, info["transparent"])
            img = (_gemini(p, precedente, cle, modele) if fournisseur == "gemini"
                   else _openai(p, precedente, cle, modele))
        self.dernier_prompt = p
        self.demandes.append(demande)
        self.images.append(img)
        return img


class Tache(QThread):
    fini = pyqtSignal(QImage, str)
    erreur = pyqtSignal(str)
    traduit = pyqtSignal(str)

    def __init__(self, conversation: Conversation, demande: str, fournisseur: str, style: str,
                 cle: str, modele: str, traduire_en: bool = True, retoucher: bool = True, parent=None):
        super().__init__(parent)
        self.args = (demande, fournisseur, style, cle, modele, traduire_en, self.traduit.emit, retoucher)
        self.conversation = conversation

    def run(self):
        try:
            img = self.conversation.generer(*self.args)
            self.fini.emit(img, self.conversation.dernier_prompt)
        except ErreurIA as e:
            self.erreur.emit(str(e))
        except Exception as e:  # réseau ou réponse inattendue : message lisible plutôt qu'un plantage
            self.erreur.emit(t("ia_err_inattendue", e=e))
