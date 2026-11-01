"""Fenêtre « Créer avec une IA » : conversation avec un service de génération d'images."""
from __future__ import annotations

import os
import re
import time

from PyQt6.QtCore import QSettings, Qt, QTimer, QUrl, pyqtSignal
from PyQt6.QtGui import QDesktopServices, QImage, QKeySequence, QPixmap, QShortcut
from PyQt6.QtWidgets import (QCheckBox, QComboBox, QDialog, QFrame, QHBoxLayout, QLabel, QLineEdit, QPlainTextEdit,
                             QProgressBar, QPushButton, QScrollArea, QVBoxLayout, QWidget)

import ia
import rendu
import socle_qt
from textes import t

DOSSIER = os.path.expanduser("~/Pictures/MiCONE")
VIGNETTE = 220


class DialogueIA(QDialog):
    image_choisie = pyqtSignal(str)   # chemin du .PNG enregistré

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle(t("ia_titre"))
        self.resize(720, 720)
        self.qs = QSettings("MiCONE", "MiCONE")
        self.conv = ia.Conversation()
        self.tache: ia.Tache | None = None
        self._construire()
        self._changer_fournisseur()

    # ------------------------------------------------------------ interface

    def _construire(self):
        sp = socle_qt.m
        lay = QVBoxLayout(self)
        lay.setContentsMargins(sp("space-4"), sp("space-4"), sp("space-4"), sp("space-4"))
        lay.setSpacing(sp("space-3"))

        haut = QHBoxLayout()
        haut.setSpacing(sp("space-2"))
        haut.addWidget(socle_qt.role(QLabel(t("ia_service")), "muted"))
        self.c_fourn = QComboBox()
        for cle in ia.FOURNISSEURS:
            self.c_fourn.addItem(t(f"ia_f_{cle}"), cle)
        self.c_fourn.setCurrentIndex(max(0, self.c_fourn.findData(self.qs.value("ia/fournisseur", "pollinations"))))
        self.c_fourn.currentIndexChanged.connect(self._changer_fournisseur)
        haut.addWidget(self.c_fourn, 1)
        haut.addSpacing(sp("space-2"))
        haut.addWidget(socle_qt.role(QLabel(t("ia_style")), "muted"))
        self.c_style = QComboBox()
        for cle in ("3d", "plat", "glyphe"):
            self.c_style.addItem(t(f"ia_s_{cle}"), cle)
        self.c_style.setCurrentIndex(max(0, self.c_style.findData(self.qs.value("ia/style", "3d"))))
        self.c_style.currentIndexChanged.connect(lambda: self.qs.setValue("ia/style", self.c_style.currentData()))
        haut.addWidget(self.c_style, 1)
        self.k_flat = QCheckBox(t("ia_flat"))
        self.k_flat.setChecked(self.qs.value("ia/flat", False) in (True, "true"))
        self.k_flat.toggled.connect(self._changer_flat)
        haut.addSpacing(sp("space-2"))
        haut.addWidget(self.k_flat, 0, Qt.AlignmentFlag.AlignVCenter)
        self.b_reglages = socle_qt.variant(QPushButton(t("ia_reglages")), "tertiary")
        self.b_reglages.setCheckable(True)
        self.b_reglages.toggled.connect(lambda v: self.p_reglages.setVisible(v))
        haut.addSpacing(sp("space-2"))
        haut.addWidget(self.b_reglages)
        lay.addLayout(haut)

        # Réglages du service : modèle et clé.
        self.p_reglages = QFrame()
        self.p_reglages.setProperty("panel", "raised")
        lr = QVBoxLayout(self.p_reglages)
        lr.setContentsMargins(sp("space-3"), sp("space-3"), sp("space-3"), sp("space-3"))
        lr.setSpacing(sp("space-2"))
        l_mod = QHBoxLayout()
        l_mod.addWidget(socle_qt.role(QLabel(t("ia_modele")), "muted"))
        self.e_modele = QComboBox()
        self.e_modele.setEditable(True)
        self.e_modele.currentTextChanged.connect(lambda _: self._memoriser_modele())
        l_mod.addWidget(self.e_modele, 1)
        lr.addLayout(l_mod)
        self.w_cle = QWidget()
        l_cle = QHBoxLayout(self.w_cle)
        l_cle.setContentsMargins(0, 0, 0, 0)
        l_cle.addWidget(socle_qt.role(QLabel(t("ia_cle")), "muted"))
        self.e_cle = QLineEdit()
        self.e_cle.setEchoMode(QLineEdit.EchoMode.Password)
        self.e_cle.textEdited.connect(self._cle_saisie)
        l_cle.addWidget(self.e_cle, 1)
        b_enr = socle_qt.variant(QPushButton(t("ia_cle_enregistrer")), "secondary")
        b_enr.clicked.connect(self._enregistrer_cle)
        l_cle.addWidget(b_enr)
        self.b_obtenir = socle_qt.variant(QPushButton(t("ia_cle_obtenir")), "tertiary")
        self.b_obtenir.clicked.connect(
            lambda: QDesktopServices.openUrl(QUrl(ia.FOURNISSEURS[self._fourn()].get("lien", ""))))
        l_cle.addWidget(self.b_obtenir)
        lr.addWidget(self.w_cle)
        self.l_aide = socle_qt.role(QLabel(""), "subtle")
        self.l_aide.setWordWrap(True)
        lr.addWidget(self.l_aide)
        self.p_reglages.hide()
        self.c_style.setEnabled(not self.k_flat.isChecked())
        lay.addWidget(self.p_reglages)

        # Conversation.
        self.zone = QScrollArea()
        self.zone.setWidgetResizable(True)
        self.zone.setFrameShape(QFrame.Shape.NoFrame)
        fil = QWidget()
        fil.setObjectName("Fil")
        fil.setStyleSheet(f"QWidget#Fil {{ background: {socle_qt.c('bg-sunken')}; }}")
        self.fil = QVBoxLayout(fil)
        self.fil.setContentsMargins(sp("space-3"), sp("space-3"), sp("space-3"), sp("space-3"))
        self.fil.setSpacing(sp("space-3"))
        self.l_vide = socle_qt.role(QLabel(t("ia_vide")), "muted")
        self.l_vide.setWordWrap(True)
        self.l_vide.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.fil.addWidget(self.l_vide)
        self.fil.addStretch(1)
        self.zone.setWidget(fil)
        cadre = QFrame()
        cadre.setProperty("panel", "sunken")
        lc = QVBoxLayout(cadre)
        lc.setContentsMargins(1, 1, 1, 1)
        lc.addWidget(self.zone)
        lay.addWidget(cadre, 1)

        # Saisie.
        self.e_prompt = QPlainTextEdit()
        self.e_prompt.setPlaceholderText(t("ia_placeholder"))
        self.e_prompt.setFixedHeight(72)
        lay.addWidget(self.e_prompt)
        QShortcut(QKeySequence("Ctrl+Return"), self.e_prompt, activated=self.envoyer)

        bas = QHBoxLayout()
        self.k_detourer = QCheckBox(t("ia_detourer"))
        self.k_detourer.setChecked(self.qs.value("ia/detourer", True) in (True, "true"))
        self.k_detourer.toggled.connect(lambda v: self.qs.setValue("ia/detourer", v))
        bas.setSpacing(socle_qt.m("space-4"))
        bas.addWidget(self.k_detourer, 0, Qt.AlignmentFlag.AlignVCenter)
        self.k_traduire = QCheckBox(t("ia_traduire"))
        self.k_traduire.setChecked(self.qs.value("ia/traduire", True) in (True, "true"))
        self.k_traduire.toggled.connect(lambda v: self.qs.setValue("ia/traduire", v))
        bas.addWidget(self.k_traduire, 0, Qt.AlignmentFlag.AlignVCenter)
        self.k_retoucher = QCheckBox(t("ia_retoucher"))
        self.k_retoucher.setChecked(True)
        self.k_retoucher.setEnabled(False)
        bas.addWidget(self.k_retoucher, 0, Qt.AlignmentFlag.AlignVCenter)
        bas.addStretch(1)
        lay.addLayout(bas)
        bas = QHBoxLayout()
        bas.addStretch(1)
        self.b_nouvelle = socle_qt.variant(QPushButton(t("ia_nouvelle")), "tertiary")
        self.b_nouvelle.clicked.connect(self.nouvelle)
        bas.addWidget(self.b_nouvelle)
        self.b_envoyer = socle_qt.variant(QPushButton(t("ia_envoyer")), "primary")
        self.b_envoyer.setMinimumWidth(120)
        self.b_envoyer.clicked.connect(self.envoyer)
        bas.addWidget(self.b_envoyer)
        lay.addLayout(bas)

        st = QHBoxLayout()
        self.l_statut = socle_qt.role(QLabel(""), "muted")
        self.l_statut.setWordWrap(True)
        st.addWidget(self.l_statut, 1)
        self.barre = QProgressBar()
        self.barre.setRange(0, 0)
        self.barre.setFixedWidth(120)
        self.barre.setTextVisible(False)
        self.barre.hide()
        st.addWidget(self.barre)
        lay.addLayout(st)

    # ------------------------------------------------------------ service

    def _fourn(self) -> str:
        return self.c_fourn.currentData()

    def _changer_fournisseur(self, *_):
        f = self._fourn()
        info = ia.FOURNISSEURS[f]
        self.qs.setValue("ia/fournisseur", f)
        self.e_modele.blockSignals(True)
        self.e_modele.clear()
        self.e_modele.addItems(ia.MODELES.get(f, []))
        self.e_modele.setCurrentText(self.qs.value(f"ia/modele/{f}", info["modele"]) or info["modele"])
        self.e_modele.blockSignals(False)
        self.w_cle.setVisible(True)
        self.e_cle.setText(ia.lire_cle(f))
        self.l_aide.setText(t("ia_cle_aide") if info["cle"] else t("ia_cle_facultative") + " " + t("ia_cle_aide"))
        self.k_detourer.setVisible(not info["transparent"])
        if info["cle"] and not self.e_cle.text():
            self.b_reglages.setChecked(True)

    def _changer_flat(self, oui: bool):
        self.qs.setValue("ia/flat", oui)
        self.c_style.setEnabled(not oui)

    def _memoriser_modele(self):
        self.qs.setValue(f"ia/modele/{self._fourn()}", self.e_modele.currentText().strip())

    def _cle_saisie(self, texte: str):
        """Bascule sur le service auquel appartient la clé collée."""
        service = ia.detecter(texte)
        if service == "anthropic":
            self._statut(t("ia_cle_claude"), "warning")
        elif service and service != self._fourn():
            self.c_fourn.setCurrentIndex(self.c_fourn.findData(service))
            self.e_cle.setText(texte)
            self._statut(t("ia_cle_detectee", service=self.c_fourn.currentText()), "info")

    def _enregistrer_cle(self):
        if ia.detecter(self.e_cle.text()) == "anthropic":
            self._statut(t("ia_cle_claude"), "warning")
            return
        try:
            ia.ecrire_cle(self._fourn(), self.e_cle.text().strip())
            self._statut(t("ia_cle_ok"), "success")
        except Exception as e:
            self._statut(t("ia_err_trousseau", e=e), "danger")

    # ------------------------------------------------------------ conversation

    def nouvelle(self):
        if self.tache and self.tache.isRunning():
            return
        self.conv = ia.Conversation()
        while self.fil.count() > 2:
            w = self.fil.takeAt(1).widget()
            if w:
                w.deleteLater()
        self.l_vide.show()
        self.k_retoucher.setChecked(True)
        self.k_retoucher.setEnabled(False)
        self._statut("", "none")

    def envoyer(self):
        demande = self.e_prompt.toPlainText().strip()
        if not demande or (self.tache and self.tache.isRunning()):
            return
        self._memoriser_modele()
        self.l_vide.hide()
        bulle = socle_qt.role(QLabel(f"<b>{t('ia_vous')} :</b> {demande.replace('<', '&lt;')}"), "muted")
        bulle.setWordWrap(True)
        bulle.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self._ajouter(bulle)
        self.e_prompt.clear()
        self._occupe(True)
        f = self._fourn()
        style = "flat" if self.k_flat.isChecked() else self.c_style.currentData()
        self.tache = ia.Tache(self.conv, demande, f, style,
                              self.e_cle.text().strip(),
                              self.e_modele.currentText().strip(), self.k_traduire.isChecked(),
                              self.k_retoucher.isChecked(), self)
        self.tache.fini.connect(self._resultat)
        self.tache.erreur.connect(self._erreur)
        self.tache.traduit.connect(self._traduit)
        self.tache.start()

    def _traduit(self, anglais: str):
        l = socle_qt.role(QLabel(f"→ {t('ia_traduit')} : {anglais.replace('<', '&lt;')}"), "subtle")
        l.setWordWrap(True)
        l.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self._ajouter(l)

    def _resultat(self, img: QImage, prompt: str = ""):
        self._occupe(False)
        self._statut("", "none")
        info = ia.FOURNISSEURS[self.tache.args[1]]
        if self.k_detourer.isChecked() and not info["transparent"]:
            img = ia.detourer(img)
        carte = QFrame()
        carte.setProperty("panel", "true")
        lc = QHBoxLayout(carte)
        lc.setContentsMargins(socle_qt.m("space-3"), socle_qt.m("space-3"), socle_qt.m("space-3"), socle_qt.m("space-3"))
        vue = QLabel()
        dpr = self.devicePixelRatioF()
        apercu = rendu.rendre(img, rendu.Reglages())   # aperçu directement sur le fond d'icône
        pm = QPixmap.fromImage(rendu.reduire(apercu, int(VIGNETTE * dpr)))
        pm.setDevicePixelRatio(dpr)
        vue.setPixmap(pm)
        vue.setFixedSize(VIGNETTE, VIGNETTE)
        lc.addWidget(vue)
        brute = QLabel()
        pm2 = QPixmap.fromImage(rendu.reduire(img, int(96 * dpr)))
        pm2.setDevicePixelRatio(dpr)
        brute.setPixmap(pm2)
        brute.setFixedSize(96, 96)
        brute.setStyleSheet(f"background: {socle_qt.c('bg-inset')}; border: 1px solid {socle_qt.c('border')};")
        col = QVBoxLayout()
        col.addWidget(brute)
        col.addStretch(1)
        b = socle_qt.variant(QPushButton(t("ia_utiliser")), "secondary")
        b.clicked.connect(lambda _=False, i=img: self._utiliser(i))
        col.addWidget(b)
        lc.addLayout(col)
        lc.addStretch(1)
        self._ajouter(carte)
        if prompt:
            texte = socle_qt.role(QLabel(prompt), "subtle")
            texte.setWordWrap(True)
            texte.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            texte.hide()
            voir = socle_qt.variant(QPushButton(t("ia_voir_prompt")), "tertiary")
            voir.setCheckable(True)
            voir.toggled.connect(texte.setVisible)
            self._ajouter(voir)
            self._ajouter(texte)
        self.k_retoucher.setEnabled(True)
        self.k_retoucher.setChecked(True)

    def _erreur(self, msg: str):
        self._occupe(False)
        self._statut(msg, "danger")

    def _utiliser(self, img: QImage):
        os.makedirs(DOSSIER, exist_ok=True)
        base = re.sub(r"[^a-z0-9]+", "-", (self.conv.demandes[0] if self.conv.demandes else "icone").lower())
        chemin = os.path.join(DOSSIER, f"{base.strip('-')[:40] or 'icone'}-{time.strftime('%Y%m%d-%H%M%S')}.png")
        if not img.save(chemin, "PNG"):
            self._statut(t("ia_err_enregistrer", chemin=chemin), "danger")
            return
        self.image_choisie.emit(chemin)

    # ------------------------------------------------------------ utilitaires

    def _ajouter(self, w: QWidget):
        self.fil.insertWidget(self.fil.count() - 1, w)
        QTimer.singleShot(50, lambda: self.zone.verticalScrollBar().setValue(self.zone.verticalScrollBar().maximum()))

    def _occupe(self, oui: bool):
        self.b_envoyer.setEnabled(not oui)
        self.b_nouvelle.setEnabled(not oui)
        self.barre.setVisible(oui)
        if oui:
            self._statut(t("ia_encours"), "none")

    def _statut(self, texte: str, statut: str):
        self.l_statut.setText(texte)
        socle_qt.status(self.l_statut, statut)
