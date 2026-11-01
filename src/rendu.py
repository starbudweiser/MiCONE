"""Moteur de MiCONE : pose une image sur le fond d'icône macOS (squircle 824 px dans 1024 px)
et produit un .ICNS complet avec iconutil.

Grille Apple : toile 1024 × 1024, forme de 824 × 824 centrée (marge de 100 px), coins continus
de rayon 185,4 px. Une icône qui remplit exactement cette forme n'est plus enfermée par macOS
dans la plaque claire réservée aux icônes « non conformes ».
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field

from PyQt6.QtCore import QPointF, QRectF, Qt
from textes import t
from PyQt6.QtGui import (QBrush, QColor, QImage, QImageReader, QLinearGradient, QPainter,
                         QPainterPath, QPen, QRadialGradient)

TOILE = 1024
CORPS = QRectF(100, 100, 824, 824)
RAYON = 185.4

# Modèles de fond : (haut, bas) du dégradé vertical.
FONDS = {
    "sombre": ("#3a3a3f", "#141417"),
    "graphite": ("#5d5d64", "#2c2c31"),
    "nuit": ("#23324a", "#0b111c"),
    "clair": ("#ffffff", "#e2e2e8"),
}

# Couleurs de dossier (base de la face avant).
DOSSIERS = {
    "bleu": "#56acf0",
    "graphite": "#8c8c94",
    "nuit": "#2f4f84",
    "clair": "#e6e6ec",
}
DOS = QRectF(64, 168, 896, 704)      # panneau arrière (sans l'onglet)
FACE = QRectF(64, 250, 896, 622)     # face avant

# Tailles d'un .iconset : (nom, côté en px).
ICONSET = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
           ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
           ("512x512", 512), ("512x512@2x", 1024)]

FORMATS_LUS = sorted({bytes(f).decode().lower() for f in QImageReader.supportedImageFormats()})


@dataclass
class Reglages:
    type: str = "appli"             # « appli » (squircle) ou « dossier »
    fond_dossier: str = "bleu"      # clé de DOSSIERS ou "perso"
    grave: bool = True              # dossier : motif gravé dans la couleur du dossier
    detourer: bool = False          # retire le fond (ou la plaque d'une icône) de l'image
    fond: str = "sombre"            # clé de FONDS ou "perso"
    couleur: str = "#2d6cdf"        # base du fond « perso »
    ajustement: str = "contenir"    # « contenir » ou « remplir »
    taille: int = 72                # % du côté de la forme occupé par le motif (mode contenir)
    decalage_y: int = 0             # décalage vertical du motif, en % du côté de la forme
    recadrer: bool = True           # retire les marges transparentes de l'image
    verre: bool = True              # reflet de bord et lumière haute
    ombre_motif: bool = True        # ombre douce sous le motif
    ombre_icone: bool = False       # ombre portée autour de la forme (dans la marge)
    aplat: bool = False             # fond d'une seule couleur, sans dégradé ni lumière haute

    def vers_dict(self) -> dict:
        return dict(self.__dict__)

    @classmethod
    def depuis_dict(cls, d: dict) -> "Reglages":
        r = cls()
        for k, v in (d or {}).items():
            if hasattr(r, k):
                defaut = getattr(r, k)
                try:
                    setattr(r, k, type(defaut)(v) if not isinstance(defaut, bool)
                            else v in (True, "true", "1", 1))
                except (TypeError, ValueError):
                    pass
        return r


class ErreurImage(Exception):
    pass


# ---------------------------------------------------------------- forme

def forme(rect: QRectF = CORPS, r: float = RAYON) -> QPainterPath:
    """Rectangle à coins continus (courbure progressive, comme les icônes Apple)."""
    x, y, w, h = rect.x(), rect.y(), rect.width(), rect.height()
    r = min(r, min(w, h) / 2 / 1.52866483)
    p = QPainterPath()

    def coin(cx, cy, sx, sy, ordre):
        # Points d'un coin dans le repère du coin haut-droit, puis reflétés (sx, sy).
        pts = [(-1.52866471, 0), (-1.08849323, 0), (-0.86840689, 0), (-0.63149399, 0.07491100),
               (-0.37282392, 0.16905899), (-0.16905899, 0.37282392), (-0.07491100, 0.63149399),
               (0, 0.86840689), (0, 1.08849323), (0, 1.52866471)]
        pts = [QPointF(cx + sx * a * r, cy + sy * b * r) for a, b in pts]
        if ordre:
            pts = pts[::-1]
        return pts

    coins = [coin(x + w, y, 1, 1, False),        # haut-droit
             coin(x + w, y + h, 1, -1, True),    # bas-droit
             coin(x, y + h, -1, -1, False),      # bas-gauche
             coin(x, y, -1, 1, True)]            # haut-gauche
    p.moveTo(coins[0][0])
    for i, c in enumerate(coins):
        if i:
            p.lineTo(c[0])
        for k in range(1, 10, 3):
            p.cubicTo(c[k], c[k + 1], c[k + 2])
    p.closeSubpath()
    return p


# ---------------------------------------------------------------- image source

def charger(chemin: str) -> QImage:
    lecteur = QImageReader(chemin)
    lecteur.setAutoTransform(True)
    if lecteur.format().data().decode().lower() == "svg":
        lecteur.setScaledSize(lecteur.size().scaled(2048, 2048, Qt.AspectRatioMode.KeepAspectRatio))
    img = lecteur.read()
    if img.isNull():
        raise ErreurImage(t("err_lecture", nom=os.path.basename(chemin), detail=lecteur.errorString()))
    return img.convertToFormat(QImage.Format.Format_ARGB32_Premultiplied)


def recadrer(img: QImage, seuil: int = 8) -> QImage:
    """Retire les marges entièrement transparentes."""
    if not img.hasAlphaChannel():
        return img
    a = img.convertToFormat(QImage.Format.Format_Alpha8)
    w, h, pas = a.width(), a.height(), a.bytesPerLine()
    donnees = bytes(a.constBits().asstring(a.sizeInBytes()))
    table = bytes(1 if v > seuil else 0 for v in range(256))
    haut, bas, gauche, droite = None, None, w, -1
    for yy in range(h):
        ligne = donnees[yy * pas: yy * pas + w].translate(table)
        g = ligne.find(1)
        if g < 0:
            continue
        if haut is None:
            haut = yy
        bas = yy
        gauche = min(gauche, g)
        droite = max(droite, ligne.rfind(1))
    if haut is None:
        return img
    return img.copy(gauche, haut, droite - gauche + 1, bas - haut + 1)


def _flou(img: QImage, rayon: float) -> QImage:
    """Flou doux par réduction puis agrandissement lissés (suffisant pour une ombre)."""
    f = max(2, int(rayon))
    petit = img.scaled(max(1, img.width() // f), max(1, img.height() // f),
                       Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.SmoothTransformation)
    petit = petit.scaled(max(1, petit.width() // 2), max(1, petit.height() // 2),
                         Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.SmoothTransformation)
    return petit.scaled(img.width(), img.height(), Qt.AspectRatioMode.IgnoreAspectRatio,
                        Qt.TransformationMode.SmoothTransformation)


def _teinte(img: QImage, couleur: QColor) -> QImage:
    out = QImage(img.size(), QImage.Format.Format_ARGB32_Premultiplied)
    out.fill(Qt.GlobalColor.transparent)
    p = QPainter(out)
    p.drawImage(0, 0, img)
    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceIn)
    p.fillRect(out.rect(), couleur)
    p.end()
    return out


def _calque(img: QImage, rect: QRectF) -> QImage:
    """Image posée sur une toile transparente 1024 × 1024."""
    c = QImage(TOILE, TOILE, QImage.Format.Format_ARGB32_Premultiplied)
    c.fill(Qt.GlobalColor.transparent)
    p = QPainter(c)
    p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)
    p.drawImage(rect, img)
    p.end()
    return c


def _couleurs_fond(r: Reglages) -> tuple[QColor, QColor]:
    if r.fond == "perso":
        base = QColor(r.couleur) if QColor.isValidColorName(r.couleur) else QColor("#2d6cdf")
        return base.lighter(122), base.darker(165)
    haut, bas = FONDS.get(r.fond, FONDS["sombre"])
    return QColor(haut), QColor(bas)


def _clair(r: Reglages) -> bool:
    haut, bas = _couleurs_fond(r)
    return (haut.lightnessF() + bas.lightnessF()) / 2 > 0.6


# ---------------------------------------------------------------- rendu

def _place(img: QImage, zone: QRectF, r: Reglages) -> QRectF:
    iw, ih = img.width(), img.height()
    if r.ajustement == "remplir":
        k = max(zone.width() / iw, zone.height() / ih)
    else:
        cote = min(zone.width(), zone.height()) * max(10, min(100, r.taille)) / 100
        k = min(cote / iw, cote / ih)
    w, h = iw * k, ih * k
    cx = zone.center().x()
    cy = zone.center().y() + zone.height() * r.decalage_y / 100
    return QRectF(cx - w / 2, cy - h / 2, w, h)


def forme_dossier() -> tuple[QPainterPath, QPainterPath]:
    """Panneau arrière avec onglet, et face avant, façon dossier du Finder."""
    dos = QPainterPath()
    dos.addRoundedRect(DOS, 56, 56)
    onglet = QPainterPath()
    onglet.addRoundedRect(QRectF(DOS.left(), DOS.top() - 44, 380, 140), 40, 40)
    pente = QPainterPath()
    pente.moveTo(DOS.left() + 330, DOS.top() - 44)
    pente.cubicTo(DOS.left() + 380, DOS.top() - 44, DOS.left() + 390, DOS.top(),
                  DOS.left() + 450, DOS.top())
    pente.lineTo(DOS.left() + 330, DOS.top() + 60)
    pente.closeSubpath()
    face = QPainterPath()
    face.addRoundedRect(FACE, 52, 52)
    return dos.united(onglet).united(pente).simplified(), face


def _rendre_dossier(source: QImage | None, r: Reglages) -> QImage:
    out = QImage(TOILE, TOILE, QImage.Format.Format_ARGB32_Premultiplied)
    out.fill(Qt.GlobalColor.transparent)
    dos, face = forme_dossier()
    if r.fond_dossier == "perso" and QColor.isValidColorName(r.couleur):
        base = QColor(r.couleur)
    else:
        base = QColor(DOSSIERS.get(r.fond_dossier, DOSSIERS["bleu"]))
    clair = base.lightnessF() > 0.75
    p = QPainter(out)
    p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)

    if r.ombre_icone:
        masque = QImage(TOILE, TOILE, QImage.Format.Format_ARGB32_Premultiplied)
        masque.fill(Qt.GlobalColor.transparent)
        q = QPainter(masque)
        q.setRenderHint(QPainter.RenderHint.Antialiasing)
        q.fillPath(dos.united(face).translated(0, 12), QColor(0, 0, 0, 110))
        q.end()
        p.drawImage(0, 0, _flou(masque, 14))

    p.fillPath(dos, base.darker(122))
    if r.aplat:
        p.fillPath(face, base)
    else:
        deg = QLinearGradient(FACE.topLeft(), FACE.bottomLeft())
        deg.setColorAt(0, base.lighter(110))
        deg.setColorAt(1, base.darker(108))
        p.fillPath(face, QBrush(deg))

    p.save()
    p.setClipPath(face)
    if source is not None and not source.isNull():
        img = recadrer(source) if r.recadrer else source
        calque = _calque(img, _place(img, FACE, r))
        if r.grave:
            # Gravure : liseré clair dessous, motif plus sombre que la face.
            p.drawImage(QPointF(0, 4), _teinte(calque, QColor(255, 255, 255, 70 if not clair else 150)))
            p.drawImage(0, 0, _teinte(calque, base.darker(150 if not clair else 135)))
        else:
            if r.ombre_motif and r.ajustement != "remplir":
                p.drawImage(QPointF(0, 12), _flou(_teinte(calque, QColor(0, 0, 0, 110)), 16))
            p.drawImage(0, 0, calque)
    if r.verre:
        p.setPen(QPen(QColor(255, 255, 255, 110 if not clair else 200), 5))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawPath(face)
    p.restore()
    p.setPen(QPen(QColor(0, 0, 0, 45), 1.5))
    p.setBrush(Qt.BrushStyle.NoBrush)
    p.drawPath(face)
    p.end()
    return out


def appliquer_dossier(icone: QImage, dossier: str) -> None:
    """Pose l'icône sur un dossier (ou un fichier) du Finder."""
    with tempfile.TemporaryDirectory(prefix="micone_") as tmp:
        png = os.path.join(tmp, "icone.png")
        if not icone.save(png, "PNG"):
            raise OSError(t("err_png", nom="icone.png"))
        js = ("function run(a){ObjC.import('AppKit');"
              "var i=$.NSImage.alloc.initWithContentsOfFile(a[0]);"
              "return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(i,a[1],0);}")
        res = subprocess.run(["osascript", "-l", "JavaScript", "-e", js, png, dossier],
                             capture_output=True, text=True)
        if res.returncode != 0 or res.stdout.strip() != "true":
            raise OSError(t("err_appliquer", detail=res.stderr.strip() or res.stdout.strip()))


def rendre(source: QImage | None, r: Reglages) -> QImage:
    """Icône 1024 × 1024 (fond + motif), prête pour l'.iconset."""
    if r.type == "dossier":
        return _rendre_dossier(source, r)
    out = QImage(TOILE, TOILE, QImage.Format.Format_ARGB32_Premultiplied)
    out.fill(Qt.GlobalColor.transparent)
    chemin = forme()
    p = QPainter(out)
    p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)

    # Ombre portée de la forme, dans la marge.
    if r.ombre_icone:
        masque = QImage(TOILE, TOILE, QImage.Format.Format_ARGB32_Premultiplied)
        masque.fill(Qt.GlobalColor.transparent)
        q = QPainter(masque)
        q.setRenderHint(QPainter.RenderHint.Antialiasing)
        q.fillPath(chemin.translated(0, 12), QColor(0, 0, 0, 110))
        q.end()
        p.drawImage(0, 0, _flou(masque, 14))

    # Fond : aplat ou dégradé vertical.
    haut, bas = _couleurs_fond(r)
    if r.aplat:
        if r.fond == "perso" and QColor.isValidColorName(r.couleur):
            uni = QColor(r.couleur)
        else:
            uni = QColor((haut.red() + bas.red()) // 2, (haut.green() + bas.green()) // 2,
                         (haut.blue() + bas.blue()) // 2)
        p.fillPath(chemin, uni)
    else:
        deg = QLinearGradient(CORPS.topLeft(), CORPS.bottomLeft())
        deg.setColorAt(0, haut)
        deg.setColorAt(1, bas)
        p.fillPath(chemin, QBrush(deg))

    p.save()
    p.setClipPath(chemin)
    clair = _clair(r)

    # Lumière haute (verre), absente en aplat.
    if r.verre and not r.aplat:
        lum = QRadialGradient(QPointF(TOILE / 2, CORPS.top() - 120), 760)
        lum.setColorAt(0, QColor(255, 255, 255, 34 if not clair else 60))
        lum.setColorAt(1, QColor(255, 255, 255, 0))
        p.fillRect(CORPS, QBrush(lum))

    # Motif.
    if source is not None and not source.isNull():
        img = recadrer(source) if r.recadrer else source
        calque = _calque(img, _place(img, CORPS, r))
        if r.ombre_motif and r.ajustement != "remplir":
            ombre = _flou(_teinte(calque, QColor(0, 0, 0, 90 if clair else 150)), 16)
            p.drawImage(QPointF(0, 14), ombre)
        p.drawImage(0, 0, calque)

    # Reflet de bord (verre) : filet clair plus marqué en haut et en bas.
    if r.verre:
        bord = QLinearGradient(CORPS.topLeft(), CORPS.bottomLeft())
        a = 1.0 if not clair else 0.55
        bord.setColorAt(0.0, QColor(255, 255, 255, int(120 * a)))
        bord.setColorAt(0.25, QColor(255, 255, 255, int(28 * a)))
        bord.setColorAt(0.75, QColor(255, 255, 255, int(14 * a)))
        bord.setColorAt(1.0, QColor(255, 255, 255, int(60 * a)))
        p.setPen(QPen(QBrush(bord), 5))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawPath(chemin)
    p.restore()

    # Filet extérieur très discret pour détacher la forme d'un fond de même valeur.
    p.setPen(QPen(QColor(0, 0, 0, 40 if clair else 70), 1.5))
    p.setBrush(Qt.BrushStyle.NoBrush)
    p.drawPath(chemin)
    p.end()
    return out


def reduire(img: QImage, cote: int) -> QImage:
    """Réduction par moitiés successives : plus net qu'un seul redimensionnement."""
    while img.width() // 2 >= cote:
        img = img.scaled(img.width() // 2, img.height() // 2, Qt.AspectRatioMode.IgnoreAspectRatio,
                         Qt.TransformationMode.SmoothTransformation)
    if img.width() != cote:
        img = img.scaled(cote, cote, Qt.AspectRatioMode.IgnoreAspectRatio,
                         Qt.TransformationMode.SmoothTransformation)
    return img


def exporter_icns(icone: QImage, destination: str, png: bool = False) -> str:
    """Écrit le .ICNS (et, si demandé, le .PNG 1024 px à côté). Renvoie le chemin du .ICNS."""
    if not destination.lower().endswith(".icns"):
        destination += ".icns"
    iconutil = shutil.which("iconutil") or "/usr/bin/iconutil"
    with tempfile.TemporaryDirectory(prefix="micone_") as tmp:
        dossier = os.path.join(tmp, "icone.iconset")
        os.makedirs(dossier)
        for nom, cote in ICONSET:
            if not reduire(icone, cote).save(os.path.join(dossier, f"icon_{nom}.png"), "PNG"):
                raise OSError(t("err_png", nom=f"icon_{nom}.png"))
        sortie = os.path.join(tmp, "icone.icns")
        res = subprocess.run([iconutil, "-c", "icns", dossier, "-o", sortie],
                             capture_output=True, text=True)
        if res.returncode != 0:
            raise OSError(t("err_iconutil", detail=res.stderr.strip() or res.stdout.strip()))
        shutil.copyfile(sortie, destination)
    if png:
        icone.save(os.path.splitext(destination)[0] + "_1024.png", "PNG")
    return destination
