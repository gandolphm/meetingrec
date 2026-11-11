"""Tests for the transcription path: transcribe_session.py and transcribe.sh.

    python3 -m unittest discover -s .engine/tests

No Whisper, model or real ffmpeg needed: ffmpeg's silence detection and whisper-cli
are replaced by small stub scripts, and the WAVs are generated here. Everything is
written to a temporary folder.
"""

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import textwrap
import unittest
import wave
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.normpath(os.path.join(HERE, "..", "lib"))
sys.path.insert(0, LIB)

_saved_path = os.environ.get("PATH", "")
import transcribe_session as ts  # noqa: E402  (it prepends meetingrec's bin to PATH)
os.environ["PATH"] = _saved_path

RATE = 16000


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def write_wav(path, seconds, rate=RATE, channels=1, value=None):
    """A WAV of `seconds` length. By default each sample holds the second it sits
    in (0, 1, 2, ...), so a test can tell which part of the source a frame came
    from."""
    n = int(seconds * rate)
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        samples = [(value if value is not None else i // rate) for i in range(n)]
        frames = struct.pack(f"<{n}h", *samples)
        if channels == 2:
            frames = b"".join(frames[i:i + 2] * 2 for i in range(0, len(frames), 2))
        w.writeframes(frames)


def silencedetect_output(*marks):
    """ffmpeg's stderr for silencedetect: ("start", 0.0), ("end", 3.0), ..."""
    lines = ["Input #0, wav, from 'x.wav':"]
    for kind, t in marks:
        lines.append(f"[silencedetect @ 0x600] silence_{kind}: {t}"
                     + (" | silence_duration: 1.0" if kind == "end" else ""))
    return "\n".join(lines) + "\n"


def fake_run(stderr, returncode=0):
    return mock.patch.object(ts.subprocess, "run", return_value=subprocess.CompletedProcess(
        args=[], returncode=returncode, stdout="", stderr=stderr))


class SpeechRegions(unittest.TestCase):
    def assertRegions(self, got, want):
        self.assertEqual(len(got), len(want), got)
        for (gs, ge), (ws, we) in zip(got, want):
            self.assertAlmostEqual(gs, ws, places=6)
            self.assertAlmostEqual(ge, we, places=6)

    def test_inverts_pads_and_runs_silence_to_the_end(self):
        out = silencedetect_output(("start", 0.0), ("end", 3.0),
                                   ("start", 6.0), ("end", 12.0),
                                   ("start", 12.3))          # never ends: runs to 20 s
        with fake_run(out):
            got = ts.speech_regions("x.wav", 20.0)
        # Speech 3–6 and 12–12.3, each padded by 0.25 s.
        self.assertRegions(got, [(2.75, 6.25), (11.75, 12.55)])

    def test_regions_closer_than_the_merge_gap_are_joined(self):
        # Speech 2–4 and 4.9–6: padded, the gap between them is 0.4 s.
        out = silencedetect_output(("start", 0.0), ("end", 2.0),
                                   ("start", 4.0), ("end", 4.9),
                                   ("start", 6.0))
        with fake_run(out):
            got = ts.speech_regions("x.wav", 10.0)
        self.assertRegions(got, [(1.75, 6.25)])

    def test_padding_stays_inside_the_track(self):
        out = silencedetect_output(("start", 2.0), ("end", 9.9))
        with fake_run(out):
            got = ts.speech_regions("x.wav", 10.0)
        self.assertRegions(got, [(0.0, 2.25), (9.65, 10.0)])

    def test_no_silence_at_all_is_one_region(self):
        with fake_run(silencedetect_output()):
            got = ts.speech_regions("x.wav", 30.0)
        self.assertRegions(got, [(0.0, 30.0)])

    def test_all_silence_is_no_regions(self):
        with fake_run(silencedetect_output(("start", 0.0))):
            got = ts.speech_regions("x.wav", 30.0)
        self.assertEqual(got, [])

    def test_a_failed_ffmpeg_stops_instead_of_reading_as_all_speech(self):
        with fake_run("x.wav: Invalid data found when processing input\n", returncode=1):
            with self.assertRaises(SystemExit) as cm:
                ts.speech_regions("x.wav", 30.0)
        self.assertIn("silence detection failed", str(cm.exception.code))


class CompactAndMapBack(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.src = os.path.join(self.tmp, "mic.wav")
        write_wav(self.src, 10.0)
        self.out = os.path.join(self.tmp, "compact.wav")
        self.mapping = ts.compact(self.src, self.out, [(1.0, 2.0), (5.0, 5.5)], RATE)

    def test_keeps_only_the_regions_with_a_separator_between(self):
        with wave.open(self.out, "rb") as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (1, 2, RATE))
            n = w.getnframes()
            samples = struct.unpack(f"<{n}h", w.readframes(n))
        # 1.0 s of second 1, 1.0 s of separator silence, 0.5 s of second 5.
        self.assertEqual(n, int(2.5 * RATE))
        self.assertEqual(set(samples[:RATE]), {1})
        self.assertEqual(set(samples[RATE:2 * RATE]), {0})
        self.assertEqual(set(samples[2 * RATE:]), {5})

    def test_mapping(self):
        want = [(0.0, 1.0, 1.0), (2.0, 5.0, 0.5)]
        for got, w in zip(self.mapping, want):
            for a, b in zip(got, w):
                self.assertAlmostEqual(a, b, places=6)

    def test_times_map_back_to_the_original_track(self):
        m = self.mapping
        self.assertAlmostEqual(ts.to_real(0.0, m), 1.0)
        self.assertAlmostEqual(ts.to_real(0.5, m), 1.5)
        self.assertAlmostEqual(ts.to_real(1.5, m), 5.0)    # inside the separator
        self.assertAlmostEqual(ts.to_real(2.25, m), 5.25)
        self.assertAlmostEqual(ts.to_real(99.0, m), 5.5)   # past the end: the last moment

    def test_no_mapping_is_identity(self):
        self.assertEqual(ts.to_real(3.2, []), 3.2)


class Srt(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def write(self, text, newline=""):
        p = os.path.join(self.tmp, "t.srt")
        with open(p, "w", encoding="utf-8", newline=newline) as f:
            f.write(text)
        return p

    def test_bom_crlf_blank_audio_and_multiline_text(self):
        p = self.write("﻿1\r\n00:00:01,000 --> 00:00:02,500\r\nHello\r\nthere\r\n\r\n"
                       "2\r\n00:00:03.000 --> 00:00:04.000\r\n[BLANK_AUDIO]\r\n\r\n"
                       "3\r\n01:02:03,004 --> 01:02:05,000\r\n  Later.  \r\n")
        self.assertEqual(ts.parse_srt(p), [(1.0, 2.5, "Hello there"),
                                           (3723.004, 3725.0, "Later.")])

    def test_missing_file_is_no_cues(self):
        self.assertEqual(ts.parse_srt(os.path.join(self.tmp, "nope.srt")), [])

    def test_write_then_parse_round_trips(self):
        cues = [(0.0, 1.25, "One."), (3661.5, 3662.0, "Two, after an hour.")]
        p = os.path.join(self.tmp, "w.srt")
        ts.write_srt(p, cues)
        self.assertEqual(ts.parse_srt(p), cues)
        self.assertIn("01:01:01,500 --> 01:01:02,000", read(p))


class TrackOffsets(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        for name in ("mic", "system"):
            write_wav(os.path.join(self.tmp, f"{name}.wav"), 10.0, value=0)

    def test_from_session_json(self):
        with open(os.path.join(self.tmp, "session.json"), "w") as f:
            json.dump({"checks": {"mic.wav": {"start_offset_seconds": 4.7},
                                  "system.wav": {"start_offset_seconds": 0.0}}}, f)
        self.assertEqual(ts.track_offsets(self.tmp, ["mic", "system"]),
                         ({"mic": 4.7, "system": 0.0}, "session.json"))

    def test_falls_back_to_file_times(self):
        # 10 s of audio each. The mic file closed at 1010, so it began at 1000;
        # system closed at 1014, so it began 4 s later.
        os.utime(os.path.join(self.tmp, "mic.wav"), (1010, 1010))
        os.utime(os.path.join(self.tmp, "system.wav"), (1014, 1014))
        offsets, source = ts.track_offsets(self.tmp, ["mic", "system"])
        self.assertEqual(source, "file mtimes")
        self.assertAlmostEqual(offsets["mic"], 0.0)
        self.assertAlmostEqual(offsets["system"], 4.0)

    def test_session_json_missing_one_track_falls_back(self):
        with open(os.path.join(self.tmp, "session.json"), "w") as f:
            json.dump({"checks": {"mic.wav": {"start_offset_seconds": 4.7}}}, f)
        self.assertEqual(ts.track_offsets(self.tmp, ["mic", "system"])[1], "file mtimes")

    def test_unreadable_track_is_unavailable(self):
        write(os.path.join(self.tmp, "system.wav"), "not audio")
        self.assertEqual(ts.track_offsets(self.tmp, ["mic", "system"]),
                         ({"mic": 0.0, "system": 0.0}, "unavailable"))


class Timelines(unittest.TestCase):
    """A track that lost audio while recording: where a line sits in the file is
    earlier than when it was said, by more and more as the call goes on."""

    # Lost nothing for 30 s, then 20% of everything after that.
    TIMELINE = [[0.0, 0.0], [30.0, 30.0], [70.0, 80.0]]

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def session(self, checks):
        with open(os.path.join(self.tmp, "session.json"), "w") as f:
            json.dump({"checks": checks}, f)
        return ts.track_timelines(self.tmp, ["mic", "system"])

    def test_no_timeline_is_the_file_as_it_is(self):
        self.assertEqual(ts.to_capture(12.5, None), 12.5)

    def test_follows_the_loss_where_it_happened(self):
        self.assertAlmostEqual(ts.to_capture(15.0, self.TIMELINE), 15.0)
        self.assertAlmostEqual(ts.to_capture(30.0, self.TIMELINE), 30.0)
        self.assertAlmostEqual(ts.to_capture(50.0, self.TIMELINE), 55.0)
        self.assertAlmostEqual(ts.to_capture(70.0, self.TIMELINE), 80.0)

    def test_past_the_end_keeps_the_last_correction(self):
        self.assertAlmostEqual(ts.to_capture(71.0, self.TIMELINE), 81.0)

    def test_read_from_session_json_only_for_the_track_that_has_one(self):
        found = self.session({"mic.wav": {"lost_seconds": 10.0, "timeline": self.TIMELINE},
                              "system.wav": {"audio_seconds": 80.0}})
        self.assertEqual(list(found), ["mic"])
        self.assertEqual(found["mic"][1], 10.0)
        self.assertAlmostEqual(ts.to_capture(50.0, found["mic"][0]), 55.0)

    def test_a_timeline_that_runs_backwards_is_ignored(self):
        self.assertEqual(self.session({"mic.wav": {"timeline": [[0, 0], [30, 40], [20, 50]]}}), {})

    def test_no_session_json_is_no_timelines(self):
        self.assertEqual(ts.track_timelines(self.tmp, ["mic", "system"]), {})


def stub_bin(home):
    d = os.path.join(home, ".local", "share", "meetingrec", "bin")
    os.makedirs(d, exist_ok=True)
    return d


def write_script(path, body):
    with open(path, "w") as f:
        f.write(textwrap.dedent(body).lstrip())
    os.chmod(path, 0o755)


class WholeSession(unittest.TestCase):
    """transcribe_session.py end to end, with whisper replaced by a stub
    transcribe.sh and ffmpeg's silence detection by a stub that replays
    <track>.marks."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home = os.path.join(self.tmp, "home")
        self.lib = os.path.join(self.tmp, "lib")
        shutil.copytree(LIB, self.lib)
        # Writes one cue at the start of whatever it's given: in the compacted
        # timeline, so it lands at the start of the track's first speech region.
        write_script(os.path.join(self.lib, "transcribe.sh"), """
            #!/usr/bin/env bash
            base="$(basename "${1%.*}")"
            printf '1\\n00:00:00,000 --> 00:00:01,000\\nhello from %s\\n\\n' "$base" > "$2/$base.srt"
            """)
        write_script(os.path.join(stub_bin(self.home), "ffmpeg"), """
            #!/usr/bin/env python3
            import sys
            src = sys.argv[sys.argv.index("-i") + 1]
            sys.stderr.write(open(src + ".marks").read())
            """)
        self.session = os.path.join(self.tmp, "2026-01-01T10-00_test")
        os.makedirs(self.session)
        for name in ("mic", "system"):
            write_wav(os.path.join(self.session, f"{name}.wav"), 20.0, value=0)
        # Mic speaks 5–6 s, system 3–4 s of their own tracks.
        write(os.path.join(self.session, "mic.wav.marks"),
            silencedetect_output(("start", 0.0), ("end", 5.0), ("start", 6.0)))
        write(os.path.join(self.session, "system.wav.marks"),
            silencedetect_output(("start", 0.0), ("end", 3.0), ("start", 4.0)))

    def run_session(self, system_offset, mic_timeline=None):
        mic = {"start_offset_seconds": 0.0}
        if mic_timeline:
            mic.update(timeline=mic_timeline, lost_seconds=mic_timeline[-1][1] - mic_timeline[-1][0])
        with open(os.path.join(self.session, "session.json"), "w") as f:
            json.dump({"checks": {"mic.wav": mic,
                                  "system.wav": {"start_offset_seconds": system_offset}}}, f)
        env = dict(os.environ, HOME=self.home)
        p = subprocess.run([sys.executable, os.path.join(self.lib, "transcribe_session.py"),
                            self.session], capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        return p.stdout, read(os.path.join(self.session, "merged.txt")).splitlines()

    def test_the_start_offset_reorders_the_speakers(self):
        # System's speech is at 2.75 s of its own track, but that track started
        # 4 s late, so on the shared timeline it comes after the mic's 4.75 s.
        out, merged = self.run_session(system_offset=4.0)
        self.assertEqual(merged, ["[00:00:04] [Me]   hello from .mic.speech",
                                  "[00:00:06] [Them] hello from .system.speech"])
        self.assertIn("track alignment: system started 4.0s late (from session.json)", out)

    def test_lost_audio_moves_a_line_to_when_it_was_said(self):
        # The mic's speech is 4.75 s into its file, but the track lost half of
        # its first 10 s of audio, so it was said at 9.5 s: after system's
        # 6.75 s, where a plain shift would have left it before.
        out, merged = self.run_session(system_offset=4.0,
                                       mic_timeline=[[0.0, 0.0], [5.0, 10.0], [20.0, 25.0]])
        self.assertEqual(merged, ["[00:00:06] [Them] hello from .system.speech",
                                  "[00:00:09] [Me]   hello from .mic.speech"])
        self.assertIn("track timing: mic lost 5s of audio while recording, corrected", out)
        # The cue ends 5.75 s into the file, past the lossy stretch: 10 + 0.75.
        self.assertEqual(ts.parse_srt(os.path.join(self.session, "mic.srt")),
                         [(9.5, 10.75, "hello from .mic.speech")])

    def test_without_an_offset_the_order_is_as_recorded(self):
        _, merged = self.run_session(system_offset=0.0)
        self.assertEqual([line[:16] for line in merged], ["[00:00:02] [Them",
                                                          "[00:00:04] [Me] "])

    def test_per_track_srts_are_in_session_time_and_temp_files_go(self):
        self.run_session(system_offset=4.0)
        self.assertEqual(ts.parse_srt(os.path.join(self.session, "system.srt")),
                         [(6.75, 7.75, "hello from .system.speech")])
        leftovers = [f for f in os.listdir(self.session) if f.startswith(".")]
        self.assertEqual(leftovers, [])


class TranscribeSh(unittest.TestCase):
    """transcribe.sh with stub whisper-cli and ffmpeg that log what they were given."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home = os.path.join(self.tmp, "home")
        self.bin = stub_bin(self.home)
        self.log = os.path.join(self.tmp, "calls.log")
        self.models = os.path.join(self.home, ".local", "share", "meetingrec", "models")
        os.makedirs(self.models)
        open(os.path.join(self.models, "ggml-small.en.bin"), "w").close()
        write_script(os.path.join(self.bin, "whisper-cli"), f"""
            #!/usr/bin/env python3
            import sys
            a = sys.argv
            open({self.log!r}, "a").write("whisper-cli -f " + a[a.index("-f") + 1] + "\\n")
            open(a[a.index("-of") + 1] + ".srt", "w").write("1\\n00:00:00,000 --> 00:00:01,000\\nhi\\n")
            """)
        write_script(os.path.join(self.bin, "ffmpeg"), f"""
            #!/usr/bin/env python3
            import shutil, sys
            open({self.log!r}, "a").write("ffmpeg " + sys.argv[-1] + "\\n")
            shutil.copy(sys.argv[sys.argv.index("-i") + 1], sys.argv[-1])
            """)

    def run_sh(self, audio, out_dir=None):
        env = dict(os.environ, HOME=self.home)
        p = subprocess.run(["bash", os.path.join(LIB, "transcribe.sh"), audio,
                            out_dir or self.tmp], capture_output=True, text=True, env=env)
        calls = read(self.log).splitlines() if os.path.exists(self.log) else []
        return p, calls

    def test_a_16k_mono_wav_goes_straight_to_whisper(self):
        audio = os.path.join(self.tmp, "track.wav")
        write_wav(audio, 1.0)
        p, calls = self.run_sh(audio)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(calls, [f"whisper-cli -f {audio}"])
        self.assertTrue(os.path.exists(audio), "the input must not be deleted")
        self.assertIn("OK ", p.stdout)

    def test_other_audio_is_converted_and_the_copy_removed(self):
        for name, kwargs in (("cd.wav", {"rate": 44100}), ("stereo.wav", {"channels": 2})):
            with self.subTest(name):
                open(self.log, "w").close()
                audio = os.path.join(self.tmp, name)
                write_wav(audio, 0.5, **kwargs)
                copy = os.path.join(self.tmp, name[:-4] + ".16k.wav")
                p, calls = self.run_sh(audio)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertEqual(calls, [f"ffmpeg {copy}", f"whisper-cli -f {copy}"])
                self.assertFalse(os.path.exists(copy))
                self.assertTrue(os.path.exists(audio))

    def test_not_a_wav_is_converted(self):
        audio = os.path.join(self.tmp, "call.m4a")
        write(audio, "not really m4a")
        p, calls = self.run_sh(audio)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(calls[0], f"ffmpeg {os.path.join(self.tmp, 'call.16k.wav')}")

    def test_missing_model_fails_before_any_conversion(self):
        os.remove(os.path.join(self.models, "ggml-small.en.bin"))
        audio = os.path.join(self.tmp, "call.m4a")
        write(audio, "x")
        p, calls = self.run_sh(audio)
        if p.returncode != 3 and "MODEL_NOT_FOUND" not in p.stderr:
            self.skipTest("a ggml-small.en.bin elsewhere on this Mac was found")
        self.assertEqual(p.returncode, 3)
        self.assertIn("MODEL_NOT_FOUND", p.stderr)
        self.assertEqual(calls, [])

    def test_no_whisper_cli_is_no_engine(self):
        if any(os.path.exists(os.path.join(d, "whisper-cli"))
               for d in ("/opt/homebrew/bin", "/usr/local/bin")):
            self.skipTest("this Mac has a whisper-cli outside meetingrec")
        os.remove(os.path.join(self.bin, "whisper-cli"))
        # A pip-installed `whisper` used to be a fallback; it no longer counts.
        write_script(os.path.join(self.bin, "whisper"), "#!/bin/sh\nexit 0\n")
        audio = os.path.join(self.tmp, "track.wav")
        write_wav(audio, 0.5)
        p, _ = self.run_sh(audio)
        self.assertEqual(p.returncode, 2)
        self.assertIn("NO_ENGINE", p.stderr)


if __name__ == "__main__":
    unittest.main()
