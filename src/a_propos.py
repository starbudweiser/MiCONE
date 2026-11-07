"""Fenêtre « À propos » de MiCONE (modèle Socle : colonne centrée de 300 px, marges de 28 px)."""
from __future__ import annotations

import os
import sys

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QGuiApplication, QPixmap
from PyQt6.QtWidgets import QDialog, QLabel, QVBoxLayout, QWidget

import maj
import socle_qt
from textes import t

LARGEUR_TEXTE = 300
MARGE = 28


def ressource(nom: str) -> str:
    """Fichier embarqué (PyInstaller) ou du dossier assets en développement."""
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, nom)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", nom)


class APropos(QDialog):
    _instance: "APropos | None" = None

    @classmethod
    def afficher(cls, fenetre: QWidget | None = None) -> None:
        """Ouvre la fenêtre, centrée sur la fenêtre de l'appli (où qu'elle soit), sinon sur l'écran."""
        if cls._instance is None:
            cls._instance = cls()
            cls._instance.setProperty("socle_centre_manuel", True)
        d = cls._instance
        if fenetre is not None:
            d._parent_centre = fenetre
        d.show()
        d._centrer_sur_parent()
        QTimer.singleShot(0, d._centrer_sur_parent)   # les marges du cadre ne sont connues qu'après l'affichage
        d.raise_()
        d.activateWindow()

    def _centrer_sur_parent(self) -> None:
        f = getattr(self, "_parent_centre", None)
        if f is None:
            return
        cadre = self.frameGeometry()
        cadre.moveCenter(f.frameGeometry().center())
        self.move(cadre.topLeft())

    def __init__(self):
        super().__init__()
        self.setWindowTitle(t("apropos_menu"))
        self.setWindowFlags(Qt.WindowType.Dialog | Qt.WindowType.CustomizeWindowHint
                            | Qt.WindowType.WindowTitleHint | Qt.WindowType.WindowCloseButtonHint)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(MARGE, MARGE, MARGE, MARGE)
        lay.setSpacing(0)
        lay.setAlignment(Qt.AlignmentFlag.AlignHCenter)

        icone = QLabel()
        dpr = QGuiApplication.primaryScreen().devicePixelRatio() if QGuiApplication.primaryScreen() else 2.0
        pix = QPixmap(ressource("icon.png")).scaled(int(84 * dpr), int(84 * dpr), Qt.AspectRatioMode.KeepAspectRatio,
                                                    Qt.TransformationMode.SmoothTransformation)
        pix.setDevicePixelRatio(dpr)
        icone.setPixmap(pix)
        icone.setFixedSize(84, 84)
        lay.addWidget(icone, 0, Qt.AlignmentFlag.AlignHCenter)
        lay.addSpacing(12)

        nom = self._texte("MiCONE")
        police = socle_qt.font("body")
        police.setPixelSize(17)
        police.setBold(True)
        nom.setFont(police)
        version, build = maj.version_courante()
        ligne_version = self._texte(t("apropos_version", version=version, build=build), "muted")
        description = self._texte(t("apropos_description"))
        auteurs = self._texte(t("apropos_auteurs"))
        police_auteurs = socle_qt.font("body")
        police_auteurs.setBold(True)
        auteurs.setFont(police_auteurs)
        licence = self._texte(t("apropos_licence"))
        garantie = self._texte(t("apropos_garantie"), "muted")
        lay.setSpacing(0)
        for widget, apres in ((nom, 6), (ligne_version, 18), (description, 12), (auteurs, 12), (licence, 12), (garantie, 0)):
            lay.addWidget(widget, 0, Qt.AlignmentFlag.AlignHCenter)
            if apres:
                lay.addSpacing(apres)

        self.setFixedWidth(LARGEUR_TEXTE + 2 * MARGE)
        lay.activate()
        self.setFixedHeight(lay.totalHeightForWidth(self.width()))

    @staticmethod
    def _texte(texte: str, role: str | None = None) -> QLabel:
        label = QLabel(texte)
        label.setWordWrap(True)
        label.setAlignment(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop)
        label.setFixedWidth(LARGEUR_TEXTE)
        label.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)
        if role:
            socle_qt.role(label, role)
        return label
