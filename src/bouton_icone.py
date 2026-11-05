"""Bouton carré à pictogramme dessiné (roue crantée, « i » d'information) pour la barre d'en-tête, aux couleurs de Socle."""
from __future__ import annotations

import math

from PyQt6.QtCore import QPointF, QRectF, Qt
from PyQt6.QtGui import QColor, QPainter, QPainterPath, QPen
from PyQt6.QtWidgets import QPushButton

import socle_qt


def _roue(p: QPainter, r: QRectF, couleur: QColor):
    """Roue à 8 dents : couronne dentée percée d'un trou central."""
    c, ext = r.center(), r.width() / 2
    corps, dent, trou = ext * 0.70, ext, ext * 0.34
    chemin = QPainterPath()
    n = 8
    for i in range(n * 4):
        a = (i / (n * 4)) * 2 * math.tau / 2 - math.pi / 2   # 4 points par dent
        rayon = dent if (i % 4) in (1, 2) else corps
        pt = QPointF(c.x() + rayon * math.cos(a), c.y() + rayon * math.sin(a))
        chemin.moveTo(pt) if i == 0 else chemin.lineTo(pt)
    chemin.closeSubpath()
    chemin.addEllipse(c, trou, trou)
    chemin.setFillRule(Qt.FillRule.OddEvenFill)
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(couleur)
    p.drawPath(chemin)


def _info(p: QPainter, r: QRectF, couleur: QColor):
    """Cercle contour avec un « i »."""
    ep = r.width() * 0.10
    p.setBrush(Qt.BrushStyle.NoBrush)
    p.setPen(QPen(couleur, ep))
    p.drawEllipse(r.adjusted(ep / 2, ep / 2, -ep / 2, -ep / 2))
    c = r.center()
    p.setPen(QPen(couleur, ep * 1.1, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
    p.drawLine(QPointF(c.x(), c.y() - r.height() * 0.02), QPointF(c.x(), c.y() + r.height() * 0.20))
    p.drawPoint(QPointF(c.x(), c.y() - r.height() * 0.20))


PICTOS = {"reglages": _roue, "info": _info}


class BoutonIcone(QPushButton):
    def __init__(self, picto: str, aide: str):
        super().__init__()
        self._picto = PICTOS[picto]
        self.setToolTip(aide)
        self.setAccessibleName(aide)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setFlat(True)
        self.setFixedSize(int(socle_qt.m("size-control")), int(socle_qt.m("size-control")))
        self.setFocusPolicy(Qt.FocusPolicy.TabFocus)

    def paintEvent(self, _event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        survol = self.underMouse() or self.isDown()
        if survol:
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QColor(socle_qt.c("control")))
            p.drawRoundedRect(QRectF(self.rect()), socle_qt.m("radius-md"), socle_qt.m("radius-md"))
        marge = self.width() * 0.25
        self._picto(p, QRectF(self.rect()).adjusted(marge, marge, -marge, -marge),
                    QColor(socle_qt.c("text-strong" if survol else "text-muted")))
        p.end()
