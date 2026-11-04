import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import iconiq  # noqa: E402


class LienIconiq(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        iconiq.RACINE = self.tmp
        iconiq.BOITE = os.path.join(self.tmp, "Inbox")
        patch = mock.patch.object(iconiq.subprocess, "Popen")   # pas de lancement réel d'iCONIQ
        patch.start()
        self.addCleanup(patch.stop)

    def test_depot_et_descripteur(self):
        src = os.path.join(self.tmp, "Mon.icns")
        open(src, "wb").write(b"icns")
        self.assertTrue(iconiq.envoyer("Mon", src, src, "app"))
        noms = os.listdir(iconiq.BOITE)
        js = [n for n in noms if n.endswith(".json")]
        self.assertEqual(len(js), 1)
        d = json.load(open(os.path.join(iconiq.BOITE, js[0])))
        self.assertEqual((d["name"], d["origin"], d["kind"], d["source"]), ("Mon", src, "app", "MiCONE"))
        self.assertTrue(os.path.isfile(os.path.join(iconiq.BOITE, d["file"])))
        self.assertFalse([n for n in noms if n.endswith(".tmp")])

    def test_fichier_absent(self):
        self.assertFalse(iconiq.envoyer("x", "/inexistant.icns", "/inexistant.icns"))


if __name__ == "__main__":
    unittest.main()
