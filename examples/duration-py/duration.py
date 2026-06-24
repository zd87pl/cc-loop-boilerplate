"""Reference implementation of SPEC-000 — the duration-string parser.

Pure, dependency-free, single-pass; returns whole seconds and raises explicit
errors instead of returning sentinels (ADR-001). Implements REQ-001..008.
"""

import re
import sys

# Unit -> seconds (REQ-002). Calendar units are intentionally excluded (ADR-001).
_UNITS = {"w": 604800, "d": 86400, "h": 3600, "m": 60, "s": 1}
_SEGMENT = re.compile(r"(\d+)([wdhms])")

# Cross-language "safe integer" bound (REQ-006). 2**53-1 is the largest integer
# exactly representable as an IEEE-754 double, so the result is portable.
MAX_SAFE_SECONDS = 2**53 - 1


class DurationError(ValueError):
    """Raised for invalid input, unknown units, or overflow (REQ-004..006)."""


def parse_duration(text):
    """Parse a duration like ``1h30m`` into whole seconds.

    >>> parse_duration("1h30m")
    5400
    >>> parse_duration("1w2d3h4m5s")
    788645
    """
    if not isinstance(text, str) or text == "":
        raise DurationError("invalid input: empty")

    pos = 0
    total = 0
    matched_any = False
    for m in _SEGMENT.finditer(text):
        if m.start() != pos:  # a gap means a stray sign/space/char (REQ-007)
            break
        pos = m.end()
        total += int(m.group(1)) * _UNITS[m.group(2)]
        matched_any = True
        if total > MAX_SAFE_SECONDS:  # REQ-006
            raise DurationError("overflow: duration exceeds the safe integer range")

    if pos != len(text) or not matched_any:
        bad = re.search(r"\d+([^wdhms\d])", text)
        if bad:
            ch = bad.group(1)
            if ch.strip() == "" or ch in "+-":  # whitespace/sign (REQ-007)
                raise DurationError("invalid input: unexpected character")
            raise DurationError("unknown unit %r" % ch)  # REQ-005
        raise DurationError("invalid input")  # REQ-004

    return total


def _main(argv):
    """Thin CLI wrapper (REQ-008)."""
    if len(argv) != 2:
        print("usage: duration.py <duration>", file=sys.stderr)
        return 2
    try:
        print(parse_duration(argv[1]))
        return 0
    except DurationError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
