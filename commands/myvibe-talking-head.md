---
description: Edit a talking-head video or folder of takes. Cuts silences, dedupes takes across clips, picks the best one per line, captions. No overlays, no demos.
argument-hint: [path/to/video-or-folder] <optional story direction>
---

# /myvibe-talking-head — pure talking-head edit

You are running `/myvibe-talking-head`. Treat every source as a speaker-on-camera clip. **Do not overlay anything.** **Do not narrate.** Just clean and concatenate.

Run autonomously. Do not ask clarifying questions unless something physically blocks completion (no source, missing dep).

**Raw arguments:** `$ARGUMENTS`

---

## Step 0 — Parse arguments

Tokenize `$ARGUMENTS` respecting quotes. Find the first token resolving to an existing path. Expand `~`, unescape `\ `.

- Path is a **file** → `SRC_FILES=[that_file]`, `WORK_DIR=dirname(file)`
- Path is a **directory** → `WORK_DIR=that_dir`, `SRC_FILES`=all video files found **recursively** under it (see Step 1 for the find pattern). Exclude derivatives.
- No path token → `WORK_DIR=$(pwd)`, search recursively from cwd.

The remainder of `$ARGUMENTS` (after stripping the path token) is the **story direction**. Story direction is OPTIONAL for this command — if absent, edit using all source material in story-neutral order (chronological by source mtime), still applying dedupe and silence rules.

## Step 1 — Recursively gather sources

Find video files under `WORK_DIR` using:
```bash
find "$WORK_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.webm" \) \
  -not -path "*/desktop-app-demos/*" \
  -not -path "*/mobile-demos/*" \
  -not -path "*/overlays/*" \
  -not -name "*_clean*" -not -name "*_overlay*" -not -name "*_myvibe*" \
  -not -name "*_v2*" -not -name "*_final*"
```

Subdirectories are part of the search. If zero results → report *"No source clips found under $WORK_DIR."* and stop.

## Step 2 — Analyze every key file (required)

For each file in `SRC_FILES`:
- If `${file%.*}-ANALYSIS.md` exists with transcript + silence intervals → load it
- Else run `claude-video-vision:watch-video` with `silence: true, transcription: true, scene_changes: true`
- Save to `${file%.*}-ANALYSIS.md` per SKILL.md format

**This step is non-optional.** Do not proceed without an analysis for every key file.

Write a top-level `${WORK_DIR}/myvibe-MASTER.md` linking each analysis. It will accumulate the cross-clip cut list.

## Step 3 — Cross-clip take selection (dedupe)

For each spoken line that appears across multiple files (or multiple times within one file), build a candidate group. Score each candidate via `claude-video-vision:video_detail` / `video_watch`:
- Facial expressiveness, eye contact, energy
- Framing, blink/half-blink
- Audio clarity
- Per SKILL.md criteria

Pick one winner per line. Record choice + reasoning in `myvibe-MASTER.md`. **Drop all losers — they do not appear in the output.**

## Step 4 — Build cut list

Apply SKILL.md hard rules for every kept take:
- Start at silence-end exactly (zero padding before speech)
- End at next `silence_start + 0.5s` (buffer for soft consonants), except final cut ends at `silence_start` cleanly
- First sub-range trims ~30–50 ms further into speech to remove ramp-up

Order:
- If a story direction was given → arrange winners to serve the arc (hook → problem → solution → demo → reveal → close, per SKILL.md)
- If no direction → arrange chronologically by source mtime, then by `src_start`. Use all the speaker's content.

Save cut list to `myvibe-MASTER.md`:

| # | source_file | src_start | src_end | edited_start | edited_end | transcript |

## Step 5 — Render

Single output: `${WORK_DIR}/${stem}_myvibe.mp4` where `stem` is the source basename in single-file mode or the work-dir basename in directory mode.

Use `hevc_videotoolbox`. Declare each unique source as a separate `-i` input; trim per the cut list; concat in story order. See SKILL.md "Render with ffmpeg" + multi-source pattern.

Verify output exists with duration > 0.

## Step 6 — Burn in Mino Lee captions

Always-on for this command (it produces a finished deliverable). Build a recipe JSON from the cut list:

```json
{
  "input": "${WORK_DIR}/${stem}_clean.mp4",
  "output": "${WORK_DIR}/${stem}_myvibe.mp4",
  "cuts": [{"edited_start": ..., "edited_end": ..., "transcript": "..."}, ...]
}
```

Save to `${WORK_DIR}/${stem}-captions.json`, run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/mino_captions.py" "${WORK_DIR}/${stem}-captions.json"
```

## Step 7 — Report

```
✓ Talking-head edit complete
  Sources:    <n> file(s) under <WORK_DIR>
  Final:      <WORK_DIR>/<stem>_myvibe.mp4
  Duration:   <secs>s (from <orig>s, cut <pct>%)
  Takes:      <kept> kept of <total candidates>
  Render:     <total ffmpeg time>
```

## Failures

- Missing dep → stop, point at `/myvibe-setup`
- ffmpeg error → surface stderr verbatim
- Cut list < 5s → stop, report
- No transcript on any clip → stop, report `video_analyze` failure
