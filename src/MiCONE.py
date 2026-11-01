"""MiCONE — transforme n'importe quelle image en icône macOS (.ICNS) posée sur le fond
sombre des icônes macOS 27, pour éviter la plaque blanche que le système ajoute aux
PNG transparents ou non carrés.

Interface : python MiCONE.py
Ligne de commande : python MiCONE.py --cli image.png [autres…] [--sortie DOSSIER] [--fond sombre]
                    [--taille 72] [--png]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

from PyQt6.QtCore import QEvent, QSettings, Qt, QTimer
from PyQt6.QtGui import QAction, QColor, QGuiApplication, QImage, QPixmap
from PyQt6.QtWidgets import (QApplication, QColorDialog, QComboBox, QFileDialog, QFrame, QHBoxLayout,
                             QLabel, QMenuBar, QMessageBox, QPushButton, QSlider, QStackedWidget, QVBoxLayout,
                             QWidget)

import ia
import maj
import rendu
import socle_qt
from a_propos import APropos
from dialogue_ia import DialogueIA
from textes import LANGUE, t

APERCU = 400                     # côté de l'aperçu principal (points)
PETITES = (128, 64, 32, 16)      # tailles réelles affichées sous l'aperçu
EXTENSIONS = tuple("." + f for f in rendu.FORMATS_LUS)
ERREURS_MAJ = {"echec_reseau": "maj_err_reseau", "echec_verif": "maj_err_verif", "echec_install": "maj_err_install"}


def _pixmap(img: QImage, cote: int, dpr: float) -> QPixmap:
    pm = QPixmap.fromImage(rendu.reduire(img, int(cote * dpr)))
    pm.setDevicePixelRatio(dpr)
    return pm


class ZoneDepot(QFrame):
    """Zone vide de départ : invite à ouvrir ou déposer une image."""

    def __init__(self, ouvrir, ouvrir_ia):
        super().__init__()
        self.setObjectName("ZoneDepot")
        lay = QVBoxLayout(self)
        lay.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.setSpacing(socle_qt.m("space-3"))
        titre = socle_qt.role(QLabel(t("depot")), "heading")
        titre.setAlignment(Qt.AlignmentFlag.AlignCenter)
        titre.setWordWrap(True)
        formats = ", ".join(f".{f.upper()}" for f in rendu.FORMATS_LUS
                            if f in ("png", "jpg", "jpeg", "webp", "svg", "heic", "tiff", "gif", "bmp", "icns"))
        sous = socle_qt.role(QLabel(t("depot_formats", formats=formats)), "meta")
        sous.setAlignment(Qt.AlignmentFlag.AlignCenter)
        sous.setWordWrap(True)
        bouton = socle_qt.variant(QPushButton(t("ouvrir")), "secondary")
        bouton.clicked.connect(ouvrir)
        b_ia = socle_qt.variant(QPushButton(t("ia_ouvrir")), "tertiary")
        b_ia.clicked.connect(ouvrir_ia)
        lay.addWidget(titre)
        lay.addWidget(sous)
        lay.addWidget(bouton, 0, Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(b_ia, 0, Qt.AlignmentFlag.AlignCenter)
        self.survol(False)

    def survol(self, actif: bool):
        bord = socle_qt.c("accent") if actif else socle_qt.c("border-strong")
        fond = socle_qt.c("surface-hover") if actif else socle_qt.c("bg-sunken")
        self.setStyleSheet(f"QFrame#ZoneDepot {{ background: {fond}; border: 1px dashed {bord}; "
                           f"border-radius: {socle_qt.m('radius-lg')}px; }}"
                           "QFrame#ZoneDepot QLabel { background: transparent; border: none; }")


class Fenetre(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MiCONE")
        self.setAcceptDrops(True)
        self.reglages_qt = QSettings("MiCONE", "MiCONE")
        self.r = rendu.Reglages.depuis_dict(self.reglages_qt.value("reglages", {}) or {})
        self.png_aussi = self.reglages_qt.value("png_aussi", False) in (True, "true")
        self.source: QImage | None = None
        self._detouree: QImage | None = None
        self.chemin_source: str | None = None
        self.icone: QImage | None = None
        self.dernier_export: str | None = None
        self.dialogue_ia: DialogueIA | None = None
        self._minuteur = QTimer(self, singleShot=True, interval=60)
        self._minuteur.timeout.connect(self._rendre)
        self._construire()
        self._vers_controles()
        socle_qt.fit_height(self)
        self.resize(940, 680)
        self.maj = maj.MiseAJour(self.reglages_qt)
        self.maj.etat.connect(self._etat_maj)
        self._menus()

    # ------------------------------------------------------------ menu, À propos, mises à jour

    def _menus(self):
        """Barre de menus globale de macOS : « À propos », mises à jour et leur réglage, dans le menu de l'appli."""
        self.barre = QMenuBar()   # sans parent : barre de menus de l'application
        menu = self.barre.addMenu("MiCONE")

        def action(texte, role, rappel, coche=None):
            a = QAction(texte, self)
            a.setMenuRole(role)
            if coche is not None:
                a.setCheckable(True)
                a.setChecked(coche)
                a.toggled.connect(rappel)
            else:
                a.triggered.connect(rappel)
            menu.addAction(a)
            return a

        action(t("apropos_menu"), QAction.MenuRole.AboutRole, lambda *_: APropos.afficher())
        action(t("maj_menu"), QAction.MenuRole.ApplicationSpecificRole, lambda *_: self.maj.verifier(manuel=True))
        action(t("maj_auto"), QAction.MenuRole.ApplicationSpecificRole, lambda v: setattr(self.maj, "auto", v),
               coche=self.maj.auto)

    def _etat_maj(self, cle: str, release, manuel: bool):
        version = release.version if release else ""
        if cle == "a_jour":
            if manuel:
                self._statut(t("maj_a_jour", version=maj.version_courante()[0]), "success")
        elif cle == "disponible":
            if self.maj.auto:
                self._statut(t("maj_telechargement", version=version), "none")
                # Un travail en cours n'est pas interrompu : la version s'installe alors à la fermeture.
                self.maj.installer(release, relancer=self.source is None, manuel=manuel)
            elif self._demander_installation(version):
                self._statut(t("maj_telechargement", version=version), "none")
                self.maj.installer(release, relancer=True, manuel=True)
        elif cle == "installation":
            self._statut(t("maj_installation", version=version), "success")
            QTimer.singleShot(400, QApplication.quit)
        elif cle == "differee":
            self._statut(t("maj_differee", version=version), "success")
        elif cle in ERREURS_MAJ:
            if manuel or release is not None:   # silencieux seulement pour une recherche automatique hors ligne
                self._statut(t(ERREURS_MAJ[cle]), "danger")

    def _demander_installation(self, version: str) -> bool:
        boite = QMessageBox(self)
        boite.setWindowTitle(t("maj_titre"))
        boite.setText(t("maj_question", version=version))
        installer = boite.addButton(t("maj_installer"), QMessageBox.ButtonRole.AcceptRole)
        boite.addButton(t("maj_plus_tard"), QMessageBox.ButtonRole.RejectRole)
        boite.exec()
        return boite.clickedButton() is installer

    # ------------------------------------------------------------ interface

    def _construire(self):
        sp = socle_qt.m
        racine = QVBoxLayout(self)
        racine.setContentsMargins(sp("space-3"), sp("space-3"), sp("space-3"), sp("space-3"))
        racine.setSpacing(sp("space-3"))

        entete = QFrame(objectName="HeaderBar")
        entete.setFixedHeight(sp("size-bar"))
        le = QHBoxLayout(entete)
        le.setContentsMargins(sp("space-3"), 0, sp("space-3"), 0)
        le.addWidget(socle_qt.role(QLabel("MiCONE"), "title"))
        le.addWidget(socle_qt.role(QLabel(t("sous_titre")), "subtle"))
        le.addStretch(1)
        racine.addWidget(entete)

        corps = QHBoxLayout()
        corps.setSpacing(sp("space-3"))
        racine.addLayout(corps, 1)

        # Barre latérale : réglages.
        cote = QFrame()
        cote.setProperty("panel", "raised")
        cote.setFixedWidth(300)
        lc = QVBoxLayout(cote)
        lc.setContentsMargins(sp("space-3"), sp("space-3"), sp("space-3"), sp("space-3"))
        lc.setSpacing(sp("space-2"))
        corps.addWidget(cote)

        self.b_ouvrir = socle_qt.variant(QPushButton(t("ouvrir")), "secondary")
        self.b_ouvrir.clicked.connect(self.ouvrir)
        lc.addWidget(self.b_ouvrir)
        self.b_ia = socle_qt.variant(QPushButton(t("ia_ouvrir")), "secondary")
        self.b_ia.clicked.connect(self.ouvrir_ia)
        lc.addWidget(self.b_ia)
        self.l_info = socle_qt.role(QLabel(t("aucune_image")), "subtle")
        self.l_info.setWordWrap(True)
        lc.addWidget(self.l_info)

        lc.addSpacing(sp("space-2"))
        lc.addWidget(socle_qt.role(QLabel(t("type")), "eyebrow"))
        self.c_type = QComboBox()
        self.c_type.addItem(t("type_appli"), "appli")
        self.c_type.addItem(t("type_dossier"), "dossier")
        self.c_type.currentIndexChanged.connect(self._changer_type)
        lc.addWidget(self.c_type)

        lc.addSpacing(sp("space-2"))
        self.l_fond = socle_qt.role(QLabel(t("fond")), "eyebrow")
        lc.addWidget(self.l_fond)
        self.c_fond = QComboBox()
        self.c_fond.currentIndexChanged.connect(self._depuis_controles)
        lc.addWidget(self.c_fond)
        self.b_couleur = socle_qt.variant(QPushButton(t("choisir_couleur")), "secondary")
        self.b_couleur.clicked.connect(self._choisir_couleur)
        lc.addWidget(self.b_couleur)
        self.k_aplat = socle_qt.WrapChoice(t("aplat"))
        self.k_aplat.toggled.connect(self._depuis_controles)
        lc.addWidget(self.k_aplat)

        lc.addSpacing(sp("space-2"))
        lc.addWidget(socle_qt.role(QLabel(t("motif")), "eyebrow"))
        self.c_ajust = QComboBox()
        self.c_ajust.addItem(t("ajustement_contenir"), "contenir")
        self.c_ajust.addItem(t("ajustement_remplir"), "remplir")
        self.c_ajust.currentIndexChanged.connect(self._depuis_controles)
        lc.addWidget(self.c_ajust)
        self.s_taille, self.l_taille = self._curseur(lc, t("taille"), 20, 100)
        self.s_decal, self.l_decal = self._curseur(lc, t("decalage"), -20, 20)
        self.k_recadrer = socle_qt.WrapChoice(t("recadrer"))
        self.k_recadrer.toggled.connect(self._depuis_controles)
        lc.addWidget(self.k_recadrer)
        self.k_detourer = socle_qt.WrapChoice(t("detourer"))
        self.k_detourer.toggled.connect(self._depuis_controles)
        lc.addWidget(self.k_detourer)
        self.k_grave = socle_qt.WrapChoice(t("grave"))
        self.k_grave.toggled.connect(self._depuis_controles)
        lc.addWidget(self.k_grave)

        lc.addSpacing(sp("space-2"))
        lc.addWidget(socle_qt.role(QLabel(t("effets")), "eyebrow"))
        self.k_verre = socle_qt.WrapChoice(t("verre"))
        self.k_ombre_motif = socle_qt.WrapChoice(t("ombre_motif"))
        self.k_ombre_icone = socle_qt.WrapChoice(t("ombre_icone"))
        for k in (self.k_verre, self.k_ombre_motif, self.k_ombre_icone):
            k.toggled.connect(self._depuis_controles)
            lc.addWidget(k)

        lc.addStretch(1)
        self.k_png = socle_qt.WrapChoice(t("png_aussi"))
        self.k_png.toggled.connect(self._depuis_controles)
        lc.addWidget(self.k_png)
        lc.addWidget(socle_qt.role(QLabel(t("rassurer")), "subtle"))
        self.b_creer = socle_qt.variant(QPushButton(t("creer")), "action")
        self.b_creer.setMinimumHeight(sp("size-cta"))
        self.b_creer.clicked.connect(self.exporter)
        lc.addWidget(self.b_creer)
        self.b_appliquer = socle_qt.variant(QPushButton(t("appliquer_dossier")), "secondary")
        self.b_appliquer.clicked.connect(self.appliquer)
        lc.addWidget(self.b_appliquer)

        # Zone de travail : dépôt ou aperçu.
        travail = QFrame()
        travail.setProperty("panel", "true")
        lt = QVBoxLayout(travail)
        lt.setContentsMargins(sp("space-3"), sp("space-3"), sp("space-3"), sp("space-3"))
        lt.setSpacing(sp("space-2"))
        corps.addWidget(travail, 1)

        self.pile = QStackedWidget()
        self.depot = ZoneDepot(self.ouvrir, self.ouvrir_ia)
        self.pile.addWidget(self.depot)

        vue = QWidget()
        lv = QVBoxLayout(vue)
        lv.setContentsMargins(0, 0, 0, 0)
        lv.setSpacing(sp("space-3"))
        lv.addWidget(socle_qt.role(QLabel(t("apercu")), "eyebrow"))
        self.l_apercu = QLabel()
        self.l_apercu.setFixedSize(APERCU, APERCU)
        self.l_apercu.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lv.addWidget(self.l_apercu, 0, Qt.AlignmentFlag.AlignHCenter)
        lv.addWidget(socle_qt.role(QLabel(t("tailles")), "eyebrow"))
        rangee = QHBoxLayout()
        rangee.setSpacing(sp("space-6"))
        rangee.addStretch(1)
        self.petites: dict[int, QLabel] = {}
        for cote_px in PETITES:
            col = QVBoxLayout()
            col.setSpacing(sp("space-1"))
            l = QLabel()
            l.setFixedSize(cote_px, cote_px)
            col.addWidget(l, 0, Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignBottom)
            legende = socle_qt.role(QLabel(f"{cote_px} px"), "subtle")
            legende.setAlignment(Qt.AlignmentFlag.AlignHCenter)
            col.addWidget(legende)
            rangee.addLayout(col)
            self.petites[cote_px] = l
        rangee.addStretch(1)
        lv.addLayout(rangee)
        lv.addStretch(1)
        self.pile.addWidget(vue)
        lt.addWidget(self.pile, 1)

        bas = QHBoxLayout()
        self.l_statut = socle_qt.role(QLabel(""), "muted")
        self.l_statut.setWordWrap(True)
        bas.addWidget(self.l_statut, 1)
        self.b_reveler = socle_qt.variant(QPushButton(t("reveler")), "tertiary")
        self.b_reveler.clicked.connect(self._reveler)
        self.b_reveler.hide()
        bas.addWidget(self.b_reveler)
        lt.addLayout(bas)

        self.setStyleSheet(
            f"QSlider::groove:horizontal {{ height: 4px; background: {socle_qt.c('control')}; border-radius: 2px; }}"
            f"QSlider::sub-page:horizontal {{ background: {socle_qt.c('accent')}; border-radius: 2px; }}"
            f"QSlider::handle:horizontal {{ background: {socle_qt.c('text-strong')}; width: 14px; height: 14px;"
            f" margin: -5px 0; border-radius: 7px; }}"
            f"QSlider::handle:horizontal:hover {{ background: {socle_qt.c('accent')}; }}"
            f"QSlider:focus {{ outline: none; }}")

    def _curseur(self, lay, libelle, mini, maxi):
        ligne = QHBoxLayout()
        ligne.addWidget(socle_qt.role(QLabel(libelle), "muted"))
        ligne.addStretch(1)
        valeur = socle_qt.role(QLabel(""), "mono")
        ligne.addWidget(valeur)
        lay.addLayout(ligne)
        s = QSlider(Qt.Orientation.Horizontal)
        s.setRange(mini, maxi)
        s.valueChanged.connect(self._depuis_controles)
        lay.addWidget(s)
        return s, valeur

    # ------------------------------------------------------------ réglages

    def _remplir_fonds(self):
        dossier = self.r.type == "dossier"
        self.c_fond.blockSignals(True)
        self.c_fond.clear()
        cles = (*rendu.DOSSIERS, "perso") if dossier else ("sombre", "graphite", "nuit", "clair", "perso")
        for cle in cles:
            self.c_fond.addItem(t(f"{'dossier' if dossier else 'fond'}_{cle}"), cle)
        self.c_fond.setCurrentIndex(max(0, self.c_fond.findData(self.r.fond_dossier if dossier else self.r.fond)))
        self.c_fond.blockSignals(False)
        self.l_fond.setText(t("couleur_dossier" if dossier else "fond"))

    def _changer_type(self, *_):
        self.r.type = self.c_type.currentData()
        self._remplir_fonds()
        self._depuis_controles()

    def _vers_controles(self):
        r = self.r
        self.c_type.blockSignals(True)
        self.c_type.setCurrentIndex(max(0, self.c_type.findData(r.type)))
        self.c_type.blockSignals(False)
        self._remplir_fonds()
        for k, v in ((self.k_grave, r.grave), (self.k_detourer, r.detourer)):
            k.box.blockSignals(True)
            k.setChecked(v)
            k.box.blockSignals(False)
        for w in (self.c_fond, self.c_ajust, self.s_taille, self.s_decal, self.k_recadrer.box, self.k_aplat.box,
                  self.k_verre.box, self.k_ombre_motif.box, self.k_ombre_icone.box, self.k_png.box):
            w.blockSignals(True)
        self.c_ajust.setCurrentIndex(max(0, self.c_ajust.findData(r.ajustement)))
        self.s_taille.setValue(r.taille)
        self.s_decal.setValue(r.decalage_y)
        self.k_recadrer.setChecked(r.recadrer)
        self.k_aplat.setChecked(r.aplat)
        self.k_verre.setChecked(r.verre)
        self.k_ombre_motif.setChecked(r.ombre_motif)
        self.k_ombre_icone.setChecked(r.ombre_icone)
        self.k_png.setChecked(self.png_aussi)
        for w in (self.c_fond, self.c_ajust, self.s_taille, self.s_decal, self.k_recadrer.box, self.k_aplat.box,
                  self.k_verre.box, self.k_ombre_motif.box, self.k_ombre_icone.box, self.k_png.box):
            w.blockSignals(False)
        self._etat_controles()

    def _depuis_controles(self, *_):
        r = self.r
        r.type = self.c_type.currentData()
        if r.type == "dossier":
            r.fond_dossier = self.c_fond.currentData()
        else:
            r.fond = self.c_fond.currentData()
        r.grave = self.k_grave.isChecked()
        r.detourer = self.k_detourer.isChecked()
        r.ajustement = self.c_ajust.currentData()
        r.taille = self.s_taille.value()
        r.decalage_y = self.s_decal.value()
        r.recadrer = self.k_recadrer.isChecked()
        r.aplat = self.k_aplat.isChecked()
        r.verre = self.k_verre.isChecked()
        r.ombre_motif = self.k_ombre_motif.isChecked()
        r.ombre_icone = self.k_ombre_icone.isChecked()
        self.png_aussi = self.k_png.isChecked()
        self.reglages_qt.setValue("reglages", r.vers_dict())
        self.reglages_qt.setValue("png_aussi", self.png_aussi)
        self._etat_controles()
        self._minuteur.start()

    def _etat_controles(self):
        dossier = self.r.type == "dossier"
        self.b_couleur.setVisible((self.r.fond_dossier if dossier else self.r.fond) == "perso")
        self.k_grave.setVisible(dossier)
        self.b_appliquer.setVisible(dossier)
        self.b_appliquer.setEnabled(self.source is not None)
        self.b_couleur.setText(f"{t('choisir_couleur')}  {self.r.couleur.upper()}")
        contenir = self.r.ajustement == "contenir"
        self.s_taille.setEnabled(contenir)
        self.s_decal.setEnabled(contenir)
        self.k_ombre_motif.setEnabled(contenir)
        self.l_taille.setText(f"{self.r.taille} %")
        self.l_decal.setText(f"{self.r.decalage_y:+d} %")
        self.b_creer.setEnabled(self.source is not None)

    def _choisir_couleur(self):
        c = QColorDialog.getColor(QColor(self.r.couleur), self, t("choisir_couleur"))
        if c.isValid():
            self.r.couleur = c.name()
            self._depuis_controles()

    # ------------------------------------------------------------ image

    def ouvrir(self):
        dossier = self.reglages_qt.value("dossier", os.path.expanduser("~/Pictures"))
        motifs = " ".join(f"*{e}" for e in EXTENSIONS)
        chemin, _ = QFileDialog.getOpenFileName(self, t("ouvrir"), dossier, t("filtre_images", motifs=motifs))
        if chemin:
            self.charger(chemin)

    def ouvrir_ia(self):
        if self.dialogue_ia is None:
            self.dialogue_ia = DialogueIA(self)
            self.dialogue_ia.image_choisie.connect(self.charger)
        self.dialogue_ia.show()
        self.dialogue_ia.raise_()
        self.dialogue_ia.activateWindow()

    def charger(self, chemin: str):
        try:
            img = rendu.charger(chemin)
        except rendu.ErreurImage as e:
            self._statut(str(e), "danger")
            return
        self.source, self.chemin_source, self._detouree = img, chemin, None
        self.reglages_qt.setValue("dossier", os.path.dirname(chemin))
        self.l_info.setText(t("image_info", nom=os.path.basename(chemin), l=img.width(), h=img.height()))
        self.pile.setCurrentIndex(1)
        self._statut("", "none")
        self.b_reveler.hide()
        self._etat_controles()
        self._rendre()

    def _rendre(self):
        if self.source is None:
            return
        self.icone = rendu.rendre(self._motif(), self.r)
        dpr = self.devicePixelRatioF()
        self.l_apercu.setPixmap(_pixmap(self.icone, APERCU, dpr))
        for cote_px, l in self.petites.items():
            l.setPixmap(_pixmap(self.icone, cote_px, dpr))

    def _motif(self) -> QImage:
        """Image source, sans son fond si l'option est cochée (calcul gardé en cache)."""
        if not self.r.detourer:
            return self.source
        if self._detouree is None:
            QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
            try:
                self._detouree = ia.detourer_auto(self.source)
            finally:
                QApplication.restoreOverrideCursor()
        return self._detouree

    def exporter(self):
        if self.icone is None:
            return
        base = os.path.splitext(self.chemin_source)[0] + ".icns"
        chemin, _ = QFileDialog.getSaveFileName(self, t("enregistrer_sous"), base, t("filtre_icns"))
        if not chemin:
            return
        try:
            self.dernier_export = rendu.exporter_icns(rendu.rendre(self._motif(), self.r), chemin, self.png_aussi)
        except OSError as e:
            self._statut(t("erreur_export", erreur=e), "danger")
            return
        self._statut(t("ok_export", chemin=self.dernier_export), "success")
        self.b_reveler.show()

    def appliquer(self):
        if self.source is None:
            return
        depart = self.reglages_qt.value("dossier_cible", os.path.expanduser("~"))
        cible = QFileDialog.getExistingDirectory(self, t("appliquer_dossier"), depart)
        if not cible:
            return
        self.reglages_qt.setValue("dossier_cible", os.path.dirname(cible))
        try:
            rendu.appliquer_dossier(rendu.rendre(self._motif(), self.r), cible)
        except OSError as e:
            self._statut(t("erreur_export", erreur=e), "danger")
            return
        self.dernier_export = cible
        self._statut(t("ok_applique", chemin=cible), "success")
        self.b_reveler.show()

    def _reveler(self):
        if self.dernier_export:
            subprocess.run(["open", "-R", self.dernier_export])

    def _statut(self, texte: str, statut: str):
        self.l_statut.setText(texte)
        socle_qt.status(self.l_statut, statut)

    # ------------------------------------------------------------ glisser-déposer

    @staticmethod
    def _image_deposee(event) -> str | None:
        for url in event.mimeData().urls():
            p = url.toLocalFile()
            if p.lower().endswith(EXTENSIONS):
                return p
        return None

    def dragEnterEvent(self, event):
        if self._image_deposee(event):
            event.acceptProposedAction()
            self.depot.survol(True)

    def dragLeaveEvent(self, event):
        self.depot.survol(False)

    def dropEvent(self, event):
        self.depot.survol(False)
        p = self._image_deposee(event)
        if p:
            self.charger(p)


class Appli(QApplication):
    """Reçoit aussi les fichiers déposés sur l'icône du Dock (« Ouvrir avec »)."""

    def __init__(self, argv):
        super().__init__(argv)
        self.fenetre: Fenetre | None = None
        self.en_attente: str | None = None

    def event(self, e):
        if e.type() == QEvent.Type.FileOpen:
            if self.fenetre:
                self.fenetre.charger(e.file())
            else:
                self.en_attente = e.file()
            return True
        return super().event(e)


def ligne_de_commande(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="MiCONE --cli", description="Image → icône macOS (.ICNS)")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--sortie", help="dossier de sortie (défaut : à côté de chaque image)")
    ap.add_argument("--fond", default="sombre", choices=[*rendu.FONDS, "perso"])
    ap.add_argument("--couleur", default="#2d6cdf", help="base du fond « perso »")
    ap.add_argument("--taille", type=int, default=72)
    ap.add_argument("--remplir", action="store_true")
    ap.add_argument("--sans-verre", action="store_true")
    ap.add_argument("--dossier", action="store_true", help="icône de dossier (façon Finder)")
    ap.add_argument("--png", action="store_true", help="enregistre aussi le .PNG 1024 px")
    a = ap.parse_args(argv)
    QGuiApplication(sys.argv[:1])
    r = rendu.Reglages(fond=a.fond, couleur=a.couleur, taille=a.taille,
                       ajustement="remplir" if a.remplir else "contenir", verre=not a.sans_verre,
                       type="dossier" if a.dossier else "appli")
    code = 0
    for img in a.images:
        dest = os.path.splitext(img)[0] + ".icns"
        if a.sortie:
            os.makedirs(a.sortie, exist_ok=True)
            dest = os.path.join(a.sortie, os.path.basename(dest))
        try:
            print(rendu.exporter_icns(rendu.rendre(rendu.charger(img), r), dest, a.png))
        except (rendu.ErreurImage, OSError) as e:
            print(e, file=sys.stderr)
            code = 1
    return code


if __name__ == "__main__":
    if "--cli" in sys.argv:
        sys.exit(ligne_de_commande([x for x in sys.argv[1:] if x != "--cli"]))
    app = Appli(sys.argv)
    socle_qt.apply(app)
    socle_qt.brand(app, "MiCONE", "#4090f0")   # la minuscule du nom prend la couleur du logo
    socle_qt.traduire_qt(app, LANGUE)   # menu de l'appli (Masquer, Quitter, Services…) dans la langue choisie
    app.fenetre = Fenetre()
    app.fenetre.show()
    QTimer.singleShot(3000, app.fenetre.maj.verifier)   # nouvelle version ? (au plus une fois par jour)
    a_ouvrir = app.en_attente or next((x for x in sys.argv[1:] if os.path.isfile(x)), None)
    if a_ouvrir:
        app.fenetre.charger(a_ouvrir)
    sys.exit(app.exec())
