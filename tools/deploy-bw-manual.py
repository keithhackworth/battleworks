#!/usr/bin/env python3
"""Install only the public manual endpoint/artifact in the existing API.
Does not change world storage auth, namespaces, schemas, or saved documents.
"""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
api = Path('/home/studio/defyant-tech/groupboard/groupboard-public-api')
route = api / 'app/routes/battleworks.py'
text = route.read_text()
if 'def manual_download():' not in text:
    text = text.replace('import re\n', 'import re\nfrom pathlib import Path\n')
    text = text.replace('g, jsonify, request\n', 'g, jsonify, request, send_file\n')
    text = text.replace('def authenticate():\n', 'def authenticate():\n    # Only the public, read-only handbook is unauthenticated.\n    if request.endpoint == "battleworks.manual_download":\n        return\n')
    marker = '@bp.get("/health")'
    assert marker in text
    text = text.replace(marker, '''@bp.get("/manual.txt")
def manual_download():
    manual = Path(__file__).resolve().parents[1] / "static" / "BattleWorks-BW-Manual.txt"
    if not manual.is_file():
        return jsonify(ok=False, code="manual_unavailable", message="The BW manual is being updated."), 503
    return send_file(manual, mimetype="text/plain", as_attachment=True,
                     download_name="BattleWorks-BW-Manual.txt", conditional=True, max_age=0)


''' + marker)
compile(text, str(route), 'exec')
manual = api / 'app/static/BattleWorks-BW-Manual.txt'
manual.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'docs/BW_MANUAL.txt', manual)
route.write_text(text)
test = api / 'tests/test_battleworks_manual.py'
test.write_text('''import unittest
from unittest.mock import patch
from flask import Flask
from app.routes import battleworks as route


class ManualDownloadTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.testing = True
        self.app.register_blueprint(route.bp)
        self.client = self.app.test_client()

    def test_public_complete_utf8_attachment_without_database(self):
        with patch.object(route, "fetch_one", side_effect=AssertionError("Manual must not query worlds")):
            response = self.client.get("/api/battleworks/v1/manual.txt")
            self.addCleanup(response.close)
            self.assertEqual(response.status_code, 200)
            self.assertIn("text/plain", response.content_type)
            self.assertIn("attachment", response.headers["Content-Disposition"])
            self.assertIn("BattleWorks-BW-Manual.txt", response.headers["Content-Disposition"])
            text = response.data.decode("utf-8")
            for expected in ("CONTENTS", "COMMAND: forward", "function travel(distance):", "get_tank_state", "material_depth", "Immutable aliases for built-in commands"):
                self.assertTrue(expected in text, expected)
            self.assertGreater(len(response.data), 50000)
            response.close()

    def test_world_routes_still_require_server_auth(self):
        response = self.client.get("/api/battleworks/v1/players/101/worlds")
        self.assertIn(response.status_code, (401, 503))
        self.assertFalse(response.json["ok"])

    def test_missing_manual_is_explicit(self):
        with patch.object(route.Path, "is_file", return_value=False):
            response = self.client.get("/api/battleworks/v1/manual.txt")
            self.addCleanup(response.close)
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json["code"], "manual_unavailable")
''')
subprocess.run(['python3', '-m', 'unittest', 'tests.test_battleworks_manual', 'tests.test_battleworks'], cwd=api, check=True)
print('Manual route/artifact installed; world authorization tests passed.')

# Nginx already serves this public static fallback; no process restart required.
public = api.parent / 'groupboard-app/static/battleworks'
public.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'docs/BW_MANUAL.txt', public / 'BattleWorks-BW-Manual.txt')
(public / 'manual.html').write_text('''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BattleWorks BW Manual</title>
<style>body{max-width:46rem;margin:12vh auto;padding:1.5rem;background:#151e23;color:#f0f1df;font:18px system-ui;line-height:1.6}a{display:inline-block;background:#358056;color:white;padding:.8rem 1.2rem;border-radius:.5rem;text-decoration:none}small{display:block;margin-top:1rem;color:#c4cdbd}</style>
<h1>BattleWorks BW Manual</h1>
<p>The complete BW language and tank-programming reference in one UTF-8 text file: commands, syntax, CPU costs, hardware, own-state APIs, scanner data and examples.</p>
<a href="BattleWorks-BW-Manual.txt" download="BattleWorks-BW-Manual.txt">Download full manual (.txt)</a>
<small>Save the file or attach it to your preferred AI when writing a tank program. No account or Roblox key is required.</small>
</html>''', encoding='utf-8')
print('Published static download page: https://groupboard.app/battleworks/manual.html')
