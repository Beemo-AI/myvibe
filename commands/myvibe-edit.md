---
description: Edit a video end-to-end given a story direction. Accepts a file, a directory of clips, or nothing (uses cwd). Auto-analyzes, cuts silences, picks best takes across all clips, overlays demos, and burns in Mino Lee captions. Zero questions to the user.
argument-hint: [path/to/video-or-folder] <story direction>
---

# /myvibe-edit — turnkey video edit

You are running the `/myvibe-edit` command. Execute the entire myvibe workflow autonomously. **Do not ask the user any clarifying questions** unless a step physically cannot complete (missing source video, missing dependency). The user has signed off on the full pipeline by invoking this command.

**Raw arguments:** `$ARGUMENTS`

---

## Step 0 — Parse arguments

Three pieces can appear in `$ARGUMENTS`, in any order:
- A **video file path** (ends in `.mp4`, `.mov`, `.MOV`, `.MP4`, `.mkv`, or `.webm`)
- A **directory path** (a folder containing one or more video clips, intended as multiple takes)
- A **story direction** (everything else — the free-form text describing the desired narrative)

Parse them out:
1. Tokenize `$ARGUMENTS` respecting quoted strings.
2. Find the first token that resolves to an existing path. Expand `~` to `$HOME`. Strip surrounding quotes. Unescape `\ ` to space.
3. If the path is a **file** → set `SRC_FILES=[that_file]`, set `WORK_DIR=dirname(file)`. Remove the token from arguments.
4. If the path is a **directory** → set `WORK_DIR=that_dir`, and `SRC_FILES` is the list of video files inside it (top-level only, not recursive). Remove the token from arguments.
5. If no path token resolves → fall through to Step 1's cwd search.

The remainder (after removing the path token) is the **story direction**.

If the story direction is empty after parsing → report:
*"Usage: /myvibe-edit [path/to/video-or-folder] <story direction>. Examples:*
*  /myvibe-edit a 30-second hook about why traditional note apps fail ADHD brains*
*  /myvibe-edit ~/Downloads/adhd.MOV story about ADHD-friendly capture*
*  /myvibe-edit ~/Downloads/raw-takes/ a one-minute pitch for my note-taking app"*
and stop.

All output files for this run live in `WORK_DIR`. The user can invoke from anywhere; outputs land next to (or inside) the input.

## Step 1 — Locate source clips (only if no path was passed)

- Set `WORK_DIR=$(pwd)`.
- Search `WORK_DIR` for `.MOV`, `.mp4`, `.mov`, `.MP4`, `.mkv`, `.webm` files at top level (not recursive).
- Exclude anything in `desktop-app-demos/`, `mobile-demos/`, or any path containing `_clean`, `_overlay`, `_myvibe`, `_v2`, or `_final` (those are derivatives from prior runs).
- Set `SRC_FILES` to the resulting list.
- If zero candidates → report *"No source video found in $(pwd) and no path was passed. Pass a file, pass a directory, or cd into a folder containing video clips."* and stop.

## Step 1.5 — Multi-clip vs single-clip

After Step 0 or Step 1, `SRC_FILES` may contain one or many videos. Both modes use the same workflow but the cut list and ffmpeg call differ:

- **Single clip:** treat it as you would today. The cuts trim ranges out of one source.
- **Multi clip:** treat each file as one or more candidate takes (often a creator records one file per take). The cuts may pull from any of the files. Story order is determined by the story direction, not file mtime.

For multi-clip mode, the final output is named `<WORK_DIR basename>_myvibe.mp4` (e.g. `raw-takes_myvibe.mp4`). For single-clip mode it remains `<source stem>_myvibe.mp4`.

## Step 2 — Analyze each clip (cached)

For each file in `SRC_FILES`:
- Check for `${file%.*}-ANALYSIS.md`
- **If it exists** and contains transcript + silence intervals → load it
- **Else** run `claude-video-vision:watch-video` with `video_analyze` and `silence: true, transcription: true, scene_changes: true`
- Save to `${file%.*}-ANALYSIS.md` in the SKILL.md format

In multi-clip mode, also write a top-level `${WORK_DIR}/myvibe-MASTER.md` that links to each per-clip analysis file and will hold the combined cut list.

## Step 3 — Identify takes and pick winners (cross-clip)

In multi-clip mode, the same line often exists in multiple files (the creator recorded take 1 as `take1.MOV`, take 2 as `take2.MOV`, etc.). Group takes by transcript content **across files**, not just within a single file.

- Build a mapping `phrase → [(file_idx, src_start, src_end), ...]` covering every appearance of each spoken line across all source clips
- For each phrase group, sample frames from each candidate take via `claude-video-vision:video_detail` / `video_watch`
- Score on: facial expressiveness, eye contact, framing, audio clarity, blink/half-blink (per SKILL.md)
- Pick one winner per phrase. Record the choice + reasoning in `myvibe-MASTER.md` (or the single per-clip analysis if single-clip mode)

## Step 4 — Build cut list aligned to the story direction

The user's direction is: `$ARGUMENTS` (with the path token stripped).

Build a cut list that follows the **storytelling arc** in SKILL.md:
1. Hook (relatable pain, 1 sentence)
2. Problem (status quo / why it's painful)
3. Solution intro ("I made X where I just…")
4. Demo action
5. Result / reveal
6. Recall or benefit
7. Close

Drop any take that doesn't advance the arc — even if it was the best take of that line. The story direction overrides take-coverage.

For each kept take, compute sub-ranges per the **Hard rules** in SKILL.md (zero silence, +0.5s tail buffer, special handling for first/last sub-range). Save the cut list to `myvibe-MASTER.md` as a table:

| # | source_file | src_start | src_end | edited_start | edited_end | transcript |

The `source_file` column refers to the index into `SRC_FILES` (0-based). In single-clip mode it's always 0 and can be omitted.

## Step 5 — Render cleaned video

Use `hevc_videotoolbox`.

**Single-clip mode:** output to `${WORK_DIR}/${SRC stem}_clean.mp4`. Apply the cut list with the standard SKILL.md ffmpeg pattern (trim/setpts/scale/pad → concat from one `-i` input).

**Multi-clip mode:** output to `${WORK_DIR}/${WORK_DIR basename}_clean.mp4`. Declare each unique source file as a separate `-i` input, then for each cut row, trim from the input matching `source_file`. Pattern:

```bash
ffmpeg -y \
  -i SRC_0 -i SRC_1 -i SRC_2 \
  -filter_complex "
    [0:v]trim=A1:B1,setpts=PTS-STARTPTS,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1[v1];
    [0:a]atrim=A1:B1,asetpts=PTS-STARTPTS[a1];
    [2:v]trim=A2:B2,setpts=PTS-STARTPTS,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1[v2];
    [2:a]atrim=A2:B2,asetpts=PTS-STARTPTS[a2];
    [1:v]trim=A3:B3,setpts=PTS-STARTPTS,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1[v3];
    [1:a]atrim=A3:B3,asetpts=PTS-STARTPTS[a3];
    [v1][a1][v2][a2][v3][a3]concat=n=3:v=1:a=1[v][a]
  " \
  -map "[v]" -map "[a]" \
  -c:v hevc_videotoolbox -b:v 14M -tag:v hvc1 \
  -c:a aac -b:a 192k \
  OUTPUT
```

Note the stream index `[0:v]` / `[1:v]` / `[2:v]` refers to which input file the cut pulls from (matches the `source_file` column in the cut list). The order of `[vN][aN]` pairs in the concat list is the **story order**, which may not match the input file order.

Verify the output exists and has duration > 0 before continuing.

## Step 6 — Overlay product demos (if available)

Look for sibling folders `desktop-app-demos/`, `mobile-demos/`, or `overlays/` relative to `WORK_DIR` (and one level up, in case the demos library sits beside the clips folder).

- If none exist → skip this step entirely, the cleaned video becomes the input to step 7
- If they exist → for each phrase in the cut transcript, find the demo clip whose name or `-ANALYSIS.md` matches semantically
  - If a candidate has no analysis, run `claude-video-vision:watch-video` on it once and save
- Compute the edited-timeline timestamp for each matched phrase (cumulative duration from step 4)
- Render overlays per the SKILL.md pattern (portrait 1080×1920 canvas, landscape demos centered, mobile demos full-frame, `tpad` to extend speaker, `eof_action=pass`)
- Output: `${WORK_DIR}/${stem}_overlay.mp4` where `stem` is the source stem in single-clip mode or the work-dir basename in multi-clip mode

If no overlays match cleanly, skip rather than forcing bad matches.

## Step 7 — Burn in Mino Lee captions (always, in this command)

> **Override:** The SKILL.md hard rule "never add captions unless explicitly asked" does NOT apply to `/myvibe-edit`. Invoking this command IS the explicit request for captions.

Build a recipe JSON from the cut list:

```json
{
  "input": "<previous step output, _overlay.mp4 if it exists else _clean.mp4>",
  "output": "${WORK_DIR}/${stem}_myvibe.mp4",
  "cuts": [
    {"edited_start": ..., "edited_end": ..., "transcript": "..."},
    ...
  ]
}
```

The captioner only cares about `edited_start` / `edited_end` / `transcript` — the multi-source `source_file` column is irrelevant here because captions run on the already-concatenated cleaned/overlay video.

Save the recipe to `${WORK_DIR}/${stem}-captions.json`, then run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/mino_captions.py" "${WORK_DIR}/${stem}-captions.json"
```

The helper handles word-timing distribution, chunking, no-flicker holds, and the Mino Lee layout (Proxima Nova Semibold, 2-word chunks, y=0.6*h, white + drop shadow). Font path is auto-resolved from `~/Library/Fonts/Proxima-Nova-Semibold.ttf` with plugin-bundled fallback.

## Step 8 — Report

Print a final summary block:

```
✓ Edit complete
  Mode:       <single-clip | multi-clip>
  Sources:    <n> file(s) in <WORK_DIR>
  Final:      <WORK_DIR>/<stem>_myvibe.mp4
  Duration:   <secs>s (from <orig total>s across all sources, cut <pct>%)
  Takes used: <n> winners from <m> candidates
  Demos:      <list, or "none">
  Render:     <total ffmpeg time>
```

Do NOT propose follow-up edits. The user can iterate by re-running `/myvibe-edit` with a different story direction or by asking naturally.

---

## Failure rules

- If `claude-video-vision` is not installed → report *"Run /myvibe-setup first."* and stop
- If `ffmpeg` errors → surface the actual ffmpeg stderr, don't paraphrase
- If a render output is 0 bytes or missing → halt, don't proceed to next step
- If the cut list would be < 5 seconds of content → report that the story direction may not have enough material and stop before rendering

Do not silently degrade. Loud failures are better than a sneakily-bad output.
