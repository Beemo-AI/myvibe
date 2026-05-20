#!/usr/bin/env python3
"""
Mino Lee caption burn-in helper.

Reads an analysis JSON of the form:
    {
      "input": "path/to/cleaned.mp4",
      "output": "path/to/captioned.mp4",
      "cuts": [
        {"edited_start": 0.0, "edited_end": 2.3, "transcript": "I built this app"},
        {"edited_start": 2.3, "edited_end": 5.1, "transcript": "to capture thoughts."}
      ],
      "font": "/Users/.../Proxima-Nova-Semibold.ttf"  # optional override
    }

Distributes word timings evenly within each cut, chunks into ~2-word groups,
forces breaks at terminal punctuation and cut boundaries, and emits a single
ffmpeg drawtext filter chain. Holds each chunk until the next begins.

Usage:
    python3 mino_captions.py recipe.json
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

CHUNK_SIZE = 2
TERMINAL_PUNCT = re.compile(r"[,.!?]$")
TAIL_PAD = 0.08  # seconds to extend the last chunk beyond its computed end

FONT_FALLBACKS = [
    os.path.expanduser("~/Library/Fonts/Proxima-Nova-Semibold.ttf"),
    os.path.join(os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "assets/fonts/Proxima-Nova-Semibold.ttf"),
    "/Library/Fonts/Montserrat-SemiBold.ttf",
    "/System/Library/Fonts/HelveticaNeue.ttc",
]


def pick_font(override: str | None) -> str:
    candidates = [override] if override else []
    candidates += FONT_FALLBACKS
    for c in candidates:
        if c and os.path.isfile(c):
            return c
    sys.exit("No usable font found. Run /edits-setup to install Proxima Nova.")


def chunk_words(cut_words: list[tuple[str, float, float]]) -> list[list[tuple[str, float, float]]]:
    """Group words into chunks of CHUNK_SIZE, breaking on terminal punctuation."""
    chunks: list[list[tuple[str, float, float]]] = []
    current: list[tuple[str, float, float]] = []
    for w, s, e in cut_words:
        current.append((w, s, e))
        if len(current) >= CHUNK_SIZE or TERMINAL_PUNCT.search(w):
            chunks.append(current)
            current = []
    if current:
        chunks.append(current)
    return chunks


def words_with_timings(transcript: str, t_start: float, t_end: float) -> list[tuple[str, float, float]]:
    words = transcript.split()
    if not words:
        return []
    per = (t_end - t_start) / len(words)
    return [(w, t_start + i * per, t_start + (i + 1) * per) for i, w in enumerate(words)]


def ffmpeg_escape(s: str) -> str:
    """Escape a string for use inside an ffmpeg drawtext text= field."""
    # Order matters: backslash first, then single quotes, then characters
    # that have special meaning to the filtergraph parser.
    s = s.replace("\\", "\\\\")
    s = s.replace("'", "\\'")
    s = s.replace(":", "\\:")
    s = s.replace("%", "\\%")
    return s


def build_drawtext_chain(chunks: list[tuple[str, float, float]], font: str, fontsize: int = 72) -> str:
    """Produce a comma-separated chain of drawtext filters, one per chunk."""
    n = len(chunks)
    parts = []
    for i, (text, start, end) in enumerate(chunks):
        # Hold each chunk until the next one begins (no flicker gaps).
        next_start = chunks[i + 1][1] if i + 1 < n else end + TAIL_PAD
        on_until = max(end, next_start)
        parts.append(
            f"drawtext="
            f"fontfile='{font}':"
            f"text='{ffmpeg_escape(text)}':"
            f"fontcolor=white:"
            f"fontsize={fontsize}:"
            f"shadowcolor=black@0.85:shadowx=3:shadowy=3:"
            f"x=(w-text_w)/2:y=0.6*h:"
            f"enable='between(t,{start:.3f},{on_until:.3f})'"
        )
    return ",".join(parts)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage: mino_captions.py recipe.json")
    recipe = json.loads(Path(sys.argv[1]).read_text())

    inp = recipe["input"]
    out = recipe["output"]
    font = pick_font(recipe.get("font"))

    # Build chunk list across all cuts. Chunks never straddle cut boundaries.
    all_chunks: list[tuple[str, float, float]] = []
    for cut in recipe["cuts"]:
        words = words_with_timings(
            cut["transcript"],
            float(cut["edited_start"]),
            float(cut["edited_end"]),
        )
        for grp in chunk_words(words):
            text = " ".join(w for w, _, _ in grp)
            start = grp[0][1]
            end = grp[-1][2]
            all_chunks.append((text, start, end))

    vf = build_drawtext_chain(all_chunks, font)

    cmd = [
        "ffmpeg", "-y", "-i", inp,
        "-vf", vf,
        "-c:v", "hevc_videotoolbox", "-b:v", "14M", "-tag:v", "hvc1",
        "-c:a", "copy",
        out,
    ]
    print("Rendering captions →", out)
    print(" ".join(shlex.quote(c) for c in cmd))
    subprocess.run(cmd, check=True)
    print("Done:", out)


if __name__ == "__main__":
    main()
