"""Tests for make_share_copy.py, the team note → plain-Markdown share copy.

    python3 -m unittest discover -s .engine/tests

Golden files: each fixtures/share/<name>.md is converted and compared byte for
byte with <name>.expected.md. When the conversion is changed on purpose, check
the new output by eye, then replace the .expected.md file with it.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.normpath(os.path.join(HERE, "..", "lib", "make_share_copy.py"))
FIXTURES = os.path.join(HERE, "fixtures", "share")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


class ShareCopy(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def convert(self, note, *args):
        return subprocess.run([sys.executable, SCRIPT, note, *args],
                              capture_output=True, text=True)

    def golden(self, name):
        out_dir = os.path.join(self.tmp, "share")
        p = self.convert(os.path.join(FIXTURES, name + ".md"), "--out-dir", out_dir)
        got = read(os.path.join(out_dir, name + ".md"))
        self.assertEqual(got, read(os.path.join(FIXTURES, name + ".expected.md")))
        return p

    def test_every_construct(self):
        # Frontmatter roll call with an alias and an inline list, the callout,
        # wikilinks with and without aliases, all five priorities, due dates.
        p = self.golden("team-note")
        # Written, but the [note: …] flags must be fixed before sending.
        self.assertEqual(p.returncode, 2)
        self.assertIn("2 unresolved flag(s)", p.stderr)
        self.assertIn("[note: owner unclear]", p.stderr)
        self.assertIn("[note: number uncertain from audio]", p.stderr)

    def test_no_org_no_flags_untitled_callout(self):
        p = self.golden("minimal-note")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stderr, "")

    def test_default_output_is_share_beside_meeting_notes(self):
        notes = os.path.join(self.tmp, "vault", "meeting-notes")
        os.makedirs(notes)
        note = os.path.join(notes, "minimal-note.md")
        shutil.copy(os.path.join(FIXTURES, "minimal-note.md"), note)
        p = self.convert(note)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "vault", "share", "minimal-note.md")))

    def test_the_vault_note_is_left_alone(self):
        note = os.path.join(self.tmp, "team-note.md")
        shutil.copy(os.path.join(FIXTURES, "team-note.md"), note)
        before = read(note)
        self.convert(note, "--out-dir", os.path.join(self.tmp, "share"))
        self.assertEqual(read(note), before)

    def test_bad_input_exits_1(self):
        cases = {
            "no-frontmatter.md": "# Just a heading\n",
            "unclosed.md": "---\ndate: 2026-01-01\n\n# Title\n",
        }
        for name, text in cases.items():
            with self.subTest(name):
                path = os.path.join(self.tmp, name)
                write(path, text)
                p = self.convert(path, "--out-dir", os.path.join(self.tmp, "share"))
                self.assertEqual(p.returncode, 1)
        p = self.convert(os.path.join(self.tmp, "missing.md"))
        self.assertEqual(p.returncode, 1)
        self.assertIn("no such file", p.stderr)


if __name__ == "__main__":
    unittest.main()
