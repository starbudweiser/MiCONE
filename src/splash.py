"""Écran de lancement animé (règle Socle « Splash animé », même construction que celui de sKYCRASH).

Fenêtre sans cadre et transparente de 500 × 190 px (carte de 476 × 166 et marge de 12 px), centrée.
Chronologie : t = 0 splash visible → t = 2 s fenêtre principale → t = 4 s sortie animée de 600 ms.
Réglage « Réduire les animations » de macOS : splash fixe, mêmes durées.

Le logo reprend le motif de l'icône (assets/motif.png), redessiné au QPainter pour animer ses pièces.
"""
from __future__ import annotations

import ctypes
import ctypes.util

from PyQt6.QtCore import QElapsedTimer, QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import (QColor, QCursor, QFont, QFontMetricsF, QGuiApplication, QPainter, QPainterPath, QPen,
                         QPolygonF, QTransform)
from PyQt6.QtWidgets import QWidget

import socle_qt
from textes import t as texte

LARGEUR = socle_qt.m("size-splash-width")    # 500 : carte de 476 et marge de 12
HAUTEUR = socle_qt.m("size-splash-height")   # 190 : carte de 166 et marge de 12
MARGE = 12
AFFICHE_MS = 4000       # durée à l'écran avant la sortie
FENETRE_MS = 2000       # ouverture de la fenêtre principale
SORTIE_MS = 600
ANIMATION_MS = 2100     # tout est en place : plus rien à redessiner jusqu'à la sortie

BLEU_NOM = QColor("#4090f0")     # bleu du logo pour la minuscule du nom et le filet
BLEU_MOTIF = QColor("#4696ff")   # couleurs de assets/motif.png
SOLEIL = QColor("#ffb830")
PAD = socle_qt.m("space-6")      # marge intérieure, identique à gauche et à droite
TITRE_PX = socle_qt.m("size-splash-title")
LOGO, ECART = 108, 26
ESPACEMENT_SOUS_TITRE = 4
NOM = "MiCONE"

# Le motif, dans le repère 800 × 800 de assets/motif.png
CADRE = QRectF(80, 160, 640, 480)     # axe du trait blanc
TRAIT_CADRE = 40
RAYON_CADRE = 50
ENCOMBREMENT = CADRE.adjusted(-TRAIT_CADRE / 2, -TRAIT_CADRE / 2, TRAIT_CADRE / 2, TRAIT_CADRE / 2)
GRANDE = QPolygonF([QPointF(130, 600), QPointF(330, 330), QPointF(530, 600)])
PETITE = QPolygonF([QPointF(400, 600), QPointF(540, 440), QPointF(670, 600)])
CENTRE_SOLEIL = QPointF(535, 295)
RAYON_SOLEIL = 65


def animations_reduites() -> bool:
    """Réglage d'accessibilité macOS « Réduire les animations » (équivalent de prefers-reduced-motion)."""
    try:
        objc = ctypes.cdll.LoadLibrary(ctypes.util.find_library("objc"))
        objc.objc_getClass.restype = ctypes.c_void_p
        objc.sel_registerName.restype = ctypes.c_void_p
        envoi = objc.objc_msgSend
        envoi.restype = ctypes.c_void_p
        envoi.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        ws = envoi(objc.objc_getClass(b"NSWorkspace"), objc.sel_registerName(b"sharedWorkspace"))
        envoi.restype = ctypes.c_bool
        return bool(envoi(ws, objc.sel_registerName(b"accessibilityDisplayShouldReduceMotion")))
    except Exception:  # sans accès au réglage, animations normales
        return False


def _bezier(x1: float, y1: float, x2: float, y2: float):
    """Équivalent de cubic-bezier() CSS : renvoie f(t) pour t dans [0, 1]."""
    def coord(t, a, b):
        return 3 * a * t * (1 - t) ** 2 + 3 * b * t * t * (1 - t) + t ** 3

    def f(x: float) -> float:
        if x <= 0:
            return 0.0
        if x >= 1:
            return 1.0
        lo, hi = 0.0, 1.0
        for _ in range(30):
            mid = (lo + hi) / 2
            if coord(mid, x1, x2) < x:
                lo = mid
            else:
                hi = mid
        return coord((lo + hi) / 2, y1, y2)
    return f


COURBE_DOUCE = _bezier(0.16, 1, 0.3, 1)
COURBE_LETTRE = _bezier(0.2, 1.2, 0.4, 1)
COURBE_FILET = _bezier(0.65, 0, 0.35, 1)
COURBE_SORTIE = _bezier(0.6, -0.15, 0.735, 0.045)   # léger rebond : la carte ne dépasse pas 104 %


def _phase(t: float, debut: float, duree: float) -> float:
    """Avancement de 0 à 1 d'une animation qui commence à `debut` ms et dure `duree` ms."""
    return min(1.0, max(0.0, (t - debut) / duree))


def _lerp(a: float, b: float, k: float) -> float:
    return a + (b - a) * k


class Splash(QWidget):
    """Splash de lancement : demarrer(ouvrir) appelle ouvrir() à 2 s pour afficher la fenêtre principale."""

    def __init__(self):
        # fenêtre ordinaire : Qt.Tool et Qt.SplashScreen donnent sous macOS un panneau qui se
        # masque dès que l'appli n'est plus active
        super().__init__(None, Qt.WindowType.Window | Qt.WindowType.FramelessWindowHint
                         | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.NoDropShadowWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setFixedSize(LARGEUR, HAUTEUR)
        self.fixe = animations_reduites()
        self.sous_titre = texte("splash_sous_titre")
        self._horloge = QElapsedTimer()
        self._sortie_a: float | None = None
        self._fenetre_ouverte = False
        self._assez_long = False
        self._ouvrir = None
        self._tic = QTimer(self)
        self._tic.setTimerType(Qt.TimerType.PreciseTimer)
        self._tic.setInterval(16)
        self._tic.timeout.connect(self.update)

        famille = QGuiApplication.font().family()
        self.f_titre = QFont(famille)
        self.f_titre.setPixelSize(TITRE_PX)
        self.f_titre.setWeight(QFont.Weight.ExtraBold)
        self.f_titre.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 0.5)
        self.f_sous_titre = QFont(famille)
        self.f_sous_titre.setPixelSize(15)
        self.f_sous_titre.setWeight(QFont.Weight.DemiBold)
        self.f_sous_titre_final = QFont(self.f_sous_titre)
        self.f_sous_titre_final.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, ESPACEMENT_SOUS_TITRE)

    def demarrer(self, ouvrir) -> None:
        self._ouvrir = ouvrir
        # écran du pointeur, comme la fenêtre principale ; centre exact de l'écran complet
        ecran = (QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()).geometry()
        pos = (ecran.x() + (ecran.width() - LARGEUR) // 2, ecran.y() + (ecran.height() - HAUTEUR) // 2)
        self.move(*pos)
        self.show()
        self.move(*pos)   # macOS remonte la fenêtre de 20 px à son premier affichage
        self._horloge.start()
        if not self.fixe:
            self._tic.start()
            QTimer.singleShot(ANIMATION_MS, self._tic.stop)
        # minuteries précises : les minuteries par défaut peuvent se déclencher 5 % trop tôt
        QTimer.singleShot(FENETRE_MS, Qt.TimerType.PreciseTimer, self._ouvrir_fenetre)
        QTimer.singleShot(AFFICHE_MS, Qt.TimerType.PreciseTimer, self._duree_atteinte)

    def ecoule(self) -> float:
        return float(self._horloge.elapsed()) if self._horloge.isValid() else 0.0

    def _ouvrir_fenetre(self) -> None:
        self._ouvrir()
        self._fenetre_ouverte = True   # pas de raise_() : il sort le splash de l'écran si l'appli n'est pas active
        self._sortir()

    def _duree_atteinte(self) -> None:
        self._assez_long = True
        self._sortir()

    def _sortir(self) -> None:
        if self._sortie_a is not None or not self._fenetre_ouverte or not self._assez_long:
            return
        self._sortie_a = self.ecoule()
        if self.fixe:
            self.hide()
        else:
            self._tic.start()
        QTimer.singleShot(SORTIE_MS + 50, Qt.TimerType.PreciseTimer, self.close)

    def paintEvent(self, _e) -> None:
        t = 3000.0 if self.fixe else self.ecoule()   # image fixe : tout est en place
        p = QPainter(self)
        p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.TextAntialiasing)
        carte = QRectF(MARGE, MARGE, LARGEUR - 2 * MARGE, HAUTEUR - 2 * MARGE)
        cx, cy = carte.center().x(), carte.center().y()

        opacite = _phase(t, 0, 300)
        if self._sortie_a is not None and not self.fixe:
            k = _phase(self.ecoule(), self._sortie_a, SORTIE_MS)
            s = _lerp(1, 0.05, COURBE_SORTIE(k))
            p.translate(cx, cy)
            p.scale(s, s)
            p.translate(-cx, -cy)
            opacite *= 1.0 if k < 0.7 else 1 - (k - 0.7) / 0.3
        p.setOpacity(max(0.0, opacite))

        # Carte plate (Socle) : ni ombre, ni dégradé, ni reflet
        p.setPen(QPen(QColor(socle_qt.c("border-strong", "dark")), 1))
        p.setBrush(QColor(socle_qt.c("surface-raised", "dark")))
        p.drawRoundedRect(carte.adjusted(0.5, 0.5, -0.5, -0.5), 16, 16)

        # Contenu centré entre deux marges identiques (space-6)
        fm = QFontMetricsF(self.f_titre)
        l_titre = sum(fm.horizontalAdvance(ch) + 0.5 for ch in NOM)
        l_sous_titre = (QFontMetricsF(self.f_sous_titre_final).horizontalAdvance(self.sous_titre)
                        - ESPACEMENT_SOUS_TITRE)
        disponible = carte.width() - 2 * PAD - LOGO - ECART
        ajuste = min(1.0, disponible / max(1.0, l_sous_titre))
        l_texte = max(l_titre, l_sous_titre * ajuste)
        gauche = carte.left() + PAD + (carte.width() - 2 * PAD - (LOGO + ECART + l_texte)) / 2
        self._logo(p, QPointF(gauche + LOGO / 2, cy), t)
        self._texte(p, QPointF(gauche + LOGO + ECART, cy), l_texte, ajuste, t)
        p.end()

    def _logo(self, p: QPainter, centre: QPointF, t: float) -> None:
        """Le cadre se trace, les montagnes montent l'une après l'autre, le soleil se lève."""
        p.save()
        p.translate(centre)
        p.scale(LOGO / ENCOMBREMENT.width(), LOGO / ENCOMBREMENT.width())
        p.translate(-ENCOMBREMENT.center())

        cadre = QPainterPath()
        cadre.addRoundedRect(CADRE, RAYON_CADRE, RAYON_CADRE)
        k = COURBE_FILET(_phase(t, 100, 800))
        if k > 0:
            longueur = cadre.length() / TRAIT_CADRE     # tirets exprimés en largeurs de trait
            stylo = QPen(QColor("#ffffff"), TRAIT_CADRE)
            stylo.setCapStyle(Qt.PenCapStyle.FlatCap)
            if k < 1:
                stylo.setDashPattern([longueur * k, longueur])
            p.setPen(stylo)
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawPath(cadre)

        interieur = QPainterPath()
        interieur.addRoundedRect(CADRE.adjusted(TRAIT_CADRE / 2, TRAIT_CADRE / 2, -TRAIT_CADRE / 2, -TRAIT_CADRE / 2),
                                 RAYON_CADRE - TRAIT_CADRE / 2, RAYON_CADRE - TRAIT_CADRE / 2)
        p.setPen(Qt.PenStyle.NoPen)
        p.setClipPath(interieur, Qt.ClipOperation.IntersectClip)

        # Le soleil passe derrière les montagnes
        k = COURBE_DOUCE(_phase(t, 850, 800))
        if k > 0:
            p.setBrush(SOLEIL)
            p.drawEllipse(CENTRE_SOLEIL + QPointF(0, _lerp(300, 0, k)), RAYON_SOLEIL, RAYON_SOLEIL)
        p.setBrush(BLEU_MOTIF)
        for forme, debut in ((PETITE, 620), (GRANDE, 480)):
            k = COURBE_DOUCE(_phase(t, debut, 650))
            if k > 0:
                p.save()
                p.translate(0, _lerp(340, 0, k))
                p.drawPolygon(forme)
                p.restore()
        p.restore()

    def _texte(self, p: QPainter, origine: QPointF, l_texte: float, ajuste: float, t: float) -> None:
        gauche = origine.x()
        taille = float(TITRE_PX)
        fm = QFontMetricsF(self.f_titre)
        h_sous_titre, ecart_filet = 15 * 1.25, 10 + 2 + 9
        haut = origine.y() - (taille + ecart_filet + h_sous_titre) / 2
        ligne = haut + fm.ascent() - (fm.ascent() + fm.descent() - taille) / 2

        # Nom : lettres qui basculent une à une (taille fixe size-splash-title)
        p.save()
        p.setFont(self.f_titre)
        x = gauche
        for i, ch in enumerate(NOM):
            l = fm.horizontalAdvance(ch) + 0.5
            k = _phase(t, 450 + i * 70, 700)
            if k > 0:
                e = COURBE_LETTRE(k)
                oy = haut + taille * 0.85
                tr = QTransform()
                tr.translate(x + l / 2, oy + _lerp(14, 0, e))
                tr.rotate(_lerp(-95, 0, e), Qt.Axis.XAxis)
                tr.translate(-(x + l / 2), -oy)
                p.save()
                p.setTransform(tr, True)
                p.setOpacity(p.opacity() * min(1.0, k * 1.6))
                p.setPen(BLEU_NOM if ch.islower() else QColor("#ffffff"))
                p.drawText(QPointF(x, ligne), ch)
                p.restore()
            x += l
        p.restore()

        # Filet bleu
        k = COURBE_FILET(_phase(t, 950, 700))
        if k > 0:
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(BLEU_NOM)
            p.drawRect(QRectF(gauche, haut + taille + 10, l_texte * k, 2))

        # Sous-titre : l'espacement se resserre ; réduit au besoin pour tenir dans la zone utile
        k = _phase(t, 1100, 900)
        if k > 0:
            e = COURBE_DOUCE(k)
            f = QFont(self.f_sous_titre)
            espacement = _lerp(12, ESPACEMENT_SOUS_TITRE, e)
            f.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, espacement)
            largeur = QFontMetricsF(f).horizontalAdvance(self.sous_titre) - espacement
            ajust = min(ajuste, l_texte / max(1.0, largeur))   # pas de rognage pendant l'entrée
            p.save()
            p.setFont(f)
            p.setPen(QColor("#d8d8d8"))
            p.setOpacity(p.opacity() * e)
            p.translate(gauche, haut + taille + ecart_filet)
            p.scale(ajust, ajust)
            p.drawText(QRectF(0, 0, largeur + 40, h_sous_titre),
                       Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter, self.sous_titre)
            p.restore()
