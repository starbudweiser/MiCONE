"""Tests de MiCONE : textes (4 langues), versions, lecture des releases, script d'installation. `python3 -m unittest discover tests`"""
import json
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import maj  # noqa: E402
import textes  # noqa: E402

LANGUES = ("fr", "en", "es", "it")
CHAMPS = re.compile(r"\{(\w+)\}")


class Textes(unittest.TestCase):
    def test_memes_cles(self):
        fr = set(textes.TEXTES["fr"])
        for lg in LANGUES[1:]:
            self.assertEqual(fr - set(textes.TEXTES[lg]), set(), f"clés absentes en {lg}")
            self.assertEqual(set(textes.TEXTES[lg]) - fr, set(), f"clés en trop en {lg}")

    def test_memes_champs_et_pas_de_vide(self):
        for cle, fr in textes.TEXTES["fr"].items():
            for lg in LANGUES:
                texte = textes.TEXTES[lg][cle]
                self.assertTrue(texte.strip(), f"{cle} vide en {lg}")
                self.assertEqual(set(CHAMPS.findall(texte)), set(CHAMPS.findall(fr)), f"{cle} : champs différents en {lg}")

    def test_cles_utilisees_existent(self):
        src = os.path.join(os.path.dirname(__file__), "..", "src")
        utilisees = set()
        for f in os.listdir(src):
            if f.endswith(".py") and f != "textes.py":
                utilisees |= set(re.findall(r'\bt\(\s*"([a-z_0-9]+)"', open(os.path.join(src, f), encoding="utf-8").read()))
        for cle in utilisees:
            self.assertIn(cle, textes.TEXTES["fr"], f"clé utilisée absente : {cle}")
        for cle in ("maj_err_reseau", "maj_err_verif", "maj_err_install"):
            self.assertIn(cle, textes.TEXTES["en"])
        self.assertIn("apropos_menu", utilisees)
        self.assertIn("maj_menu", utilisees)

    def test_langue_de_secours_anglaise(self):
        self.assertEqual(textes.choisir(["ja-JP", "fr"]), "en")
        self.assertEqual(textes.choisir(["it-IT"]), "it")


class Versions(unittest.TestCase):
    def test_ordre(self):
        self.assertTrue(maj.est_plus_recente("v1.10.0", "1.9.9"))
        self.assertTrue(maj.est_plus_recente("1.0.1", "1.0"))
        self.assertFalse(maj.est_plus_recente("1.0.0", "1.0.0"))
        self.assertFalse(maj.est_plus_recente("0.9", "1.0.0"))
        self.assertFalse(maj.est_plus_recente("n'importe quoi", "1.0.0"))
        self.assertEqual(maj.parse_version("2.0.0-beta"), (2, 0, 0))
        self.assertEqual(maj.parse_version("1.2.3.4"), ())


def _release(tag="v1.2.0", draft=False, pre=False, nom="MiCONE-1.2.0.zip", url="https://api.github.com/repos/a/b/releases/assets/7"):
    return json.dumps({"tag_name": tag, "draft": draft, "prerelease": pre,
                       "assets": [{"name": "autre.txt", "url": url}, {"name": nom, "url": url}]}).encode()


class Releases(unittest.TestCase):
    def test_lecture(self):
        r = maj.analyser_release(_release())
        self.assertEqual((r.version, r.nom), ("1.2.0", "MiCONE-1.2.0.zip"))
        self.assertIsNone(maj.analyser_release(_release(draft=True)))
        self.assertIsNone(maj.analyser_release(_release(pre=True)))
        self.assertIsNone(maj.analyser_release(_release(nom="autre-1.2.0.zip")))
        self.assertIsNone(maj.analyser_release(_release(tag="nightly")))
        self.assertIsNone(maj.analyser_release(b"[]"))
        self.assertIsNone(maj.analyser_release(b"pas du json"))

    def test_archive_seulement_depuis_l_api_github(self):
        self.assertIsNone(maj.analyser_release(_release(url="https://evil.example/MiCONE.zip")))
        self.assertIsNone(maj.analyser_release(_release(url="http://api.github.com/x")))

    def test_script_installation(self):
        s = maj.script_installation(42, "/tmp/it's new/MiCONE.app", "/Users/x y/Apps/MiCONE.app", True)
        self.assertIn("kill -0 42", s)
        self.assertIn("'/tmp/it'\"'\"'s new/MiCONE.app'", s)
        self.assertIn("mv '/Users/x y/Apps/MiCONE.app.old' '/Users/x y/Apps/MiCONE.app'", s)   # remise en place si la copie échoue
        self.assertIn("open -g", s)
        self.assertNotIn("open -g", maj.script_installation(42, "/tmp/n.app", "/tmp/d.app", False))

    def test_archive_invalide_refusee(self):
        import tempfile
        faux = os.path.join(tempfile.mkdtemp(), "MiCONE-9.9.9.zip")
        open(faux, "wb").write(b"pas une archive")
        from pathlib import Path
        self.assertIsNone(maj.preparer(Path(faux), "9.9.9", "MiCONE", "designated => x"))


if __name__ == "__main__":
    unittest.main()
