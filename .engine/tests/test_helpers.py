"""Tests for the small Python helpers meetingrec runs from .engine/lib/: the
update's backup list and fingerprints, and session-info.

    python3 -m unittest discover -s .engine/tests

The recorder's own helpers (stop_checks.py, write_session_json.py and the rest)
are exercised end to end by recorder.sh, with stand-ins for ffmpeg and audiotee.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.normpath(os.path.join(HERE, "..", "lib"))


def run(script, *args, stdin=b""):
    return subprocess.run([sys.executable, os.path.join(LIB, script), *args],
                          input=stdin, capture_output=True, check=False)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


class BackupList(unittest.TestCase):
    def test_keeps_the_users_files_only(self):
        names = [b"scribe/settings/personal.md", b"scribe/input/2026-11-17_x/mic.wav",
                 b"teamnotes/input/call.m4a", b"scribe/.DS_Store",
                 b".engine/lib/__pycache__/x.pyc", b"scribe/meeting-notes/Call.md",
                 "teamnotes/meeting-notes/Équipe — 2026-11-17.md".encode()]
        out = run("backup_list.py", stdin=b"\0".join(names) + b"\0")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.split(b"\0"),
                         [b"scribe/settings/personal.md", b"scribe/meeting-notes/Call.md",
                          "teamnotes/meeting-notes/Équipe — 2026-11-17.md".encode(), b""])

    def test_nothing_in_nothing_out(self):
        self.assertEqual(run("backup_list.py").stdout, b"")


class BackupSums(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        write(os.path.join(self.root, "scribe/settings/personal.md"), b"me\n")
        write(os.path.join(self.root, "scribe/meeting-notes/Call (2026-11-17).md"), b"note\n")
        write(os.path.join(self.root, "teamnotes/Action Items.md"), b"items\n")
        self.list = os.path.join(self.root, "list")
        write(self.list, b"scribe/settings/personal.md\0scribe/meeting-notes/Call (2026-11-17).md\0"
                         b"teamnotes/Action Items.md\0missing.md\0")
        out = run("backup_sums.py", self.root, self.list)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.sums = os.path.join(self.root, "sums.json")
        write(self.sums, out.stdout)

    def tearDown(self):
        self.tmp.cleanup()

    def changed(self):
        out = run("backup_changed.py", self.root, self.sums)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.decode().splitlines()

    def test_sums_cover_the_files_that_exist(self):
        with open(self.sums) as f:
            sums = json.load(f)
        self.assertEqual(sorted(sums), ["scribe/meeting-notes/Call (2026-11-17).md",
                                        "scribe/settings/personal.md", "teamnotes/Action Items.md"])

    def test_nothing_changed(self):
        self.assertEqual(self.changed(), [])

    def test_a_changed_and_a_removed_file_are_named(self):
        write(os.path.join(self.root, "scribe/settings/personal.md"), b"someone else\n")
        os.remove(os.path.join(self.root, "teamnotes/Action Items.md"))
        self.assertEqual(self.changed(), ["scribe/settings/personal.md", "teamnotes/Action Items.md"])


class SessionInfo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "2026-11-17T10-00_acme-check-in")
        os.makedirs(self.dir)

    def tearDown(self):
        self.tmp.cleanup()

    def info(self):
        out = run("session_info.py", self.dir)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.decode().splitlines()

    def test_without_session_json_it_goes_by_the_folder(self):
        write(os.path.join(self.dir, "mic.wav"), b"")
        self.assertEqual(self.info(), ["NO SESSION FILE", "TITLE=acme check in",
                                       "DATE=2026-11-17", "TRACKS=mic"])

    def test_reads_title_tracks_levels_and_warnings(self):
        doc = {"title": "Acme check-in", "started": "2026-11-17T15:00:00Z",
               "tracks": ["mic", "system"],
               "checks": {"startup_format": ["ok"],
                          "mic.wav": {"peak_dbfs": -4.2, "audio_seconds": 32.4},
                          "system.wav": {"peak_dbfs": -90.0, "audio_seconds": 33.6}},
               "warnings": ["system track is silent"]}
        write(os.path.join(self.dir, "session.json"), json.dumps(doc).encode())
        lines = self.info()
        self.assertEqual(lines[0], "TITLE=Acme check-in")
        self.assertTrue(lines[1].startswith("DATE=2026-11-1"))  # local date of 15:00 UTC
        self.assertEqual(lines[2], "TRACKS=mic,system")
        self.assertIn("TRACK mic.wav: peak -4.2 dBFS, 32.4s", lines)
        self.assertIn("SILENT system.wav", lines)
        self.assertNotIn("SILENT mic.wav", lines)
        self.assertEqual(lines[-1], "WARNING system track is silent")

    def test_a_broken_session_json_is_treated_as_missing(self):
        write(os.path.join(self.dir, "session.json"), b"{not json")
        self.assertEqual(self.info()[0], "NO SESSION FILE")


if __name__ == "__main__":
    unittest.main()
