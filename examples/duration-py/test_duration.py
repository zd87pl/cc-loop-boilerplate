"""Tests for the duration parser — one test per SPEC-000 acceptance criterion.

Run by the python adapter's `test` verb (``python3 -m unittest discover``), so
these are exercised as a REAL gate, not a skipped one.
"""

import os
import subprocess
import sys
import unittest

from duration import DurationError, parse_duration

_HERE = os.path.dirname(os.path.abspath(__file__))


class TestParseDuration(unittest.TestCase):
    def test_ac1_hours_minutes(self):          # AC-1  (REQ-001, REQ-003)
        self.assertEqual(parse_duration("1h30m"), 5400)

    def test_ac2_seconds(self):                # AC-2  (REQ-001)
        self.assertEqual(parse_duration("90s"), 90)

    def test_ac3_days(self):                   # AC-3  (REQ-002)
        self.assertEqual(parse_duration("2d"), 172800)

    def test_ac4_weeks(self):                  # AC-4  (REQ-002)
        self.assertEqual(parse_duration("1w"), 604800)

    def test_ac7_all_units(self):              # AC-7  (REQ-001, REQ-003)
        self.assertEqual(parse_duration("1w2d3h4m5s"), 788645)

    def test_ac5_empty_is_error(self):         # AC-5  (REQ-004)
        with self.assertRaises(DurationError):
            parse_duration("")

    def test_ac6_unknown_unit_names_it(self):  # AC-6  (REQ-005)
        with self.assertRaises(DurationError) as cm:
            parse_duration("5x")
        self.assertIn("x", str(cm.exception))

    def test_ac8_overflow(self):               # AC-8  (REQ-006)
        with self.assertRaises(DurationError):
            parse_duration("9999999999999w")

    def test_ac9_sign_or_space_rejected(self):  # AC-9 (REQ-007)
        for bad in ("-1h", "1 h"):
            with self.assertRaises(DurationError):
                parse_duration(bad)

    def test_ac10_cli(self):                   # AC-10 (REQ-008)
        proc = subprocess.run(
            [sys.executable, os.path.join(_HERE, "duration.py"), "1h30m"],
            capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "5400")


if __name__ == "__main__":
    unittest.main()
