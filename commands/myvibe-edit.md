---
description: Edit a video end-to-end given a story direction. Accepts an optional file path. Auto-analyzes, cuts silences, picks best takes, overlays demos, and burns in Mino Lee captions. Zero questions to the user.
argument-hint: [path/to/video.mp4] <story direction>
---

# /myvibe-edit — turnkey video edit

You are running the `/myvibe-edit` command. Execute the entire myvibe workflow autonomously. **Do not ask the user any clarifying questions** unless a step physically cannot complete (missing source video, missing dependency). The user has signed off on the full pipeline by invoking this command.

**Raw arguments:** `$ARGUMENTS`

---

## Step 0 — Parse arguments

Two pieces can appear in `$ARGUMENTS`, in any order:
- A **video file path** (ends in `.mp4`, `.mov`, `.MOV`, `.MP4`, `.mkv`, or `.webm`, OR contains a `/`)
- A **story direction** (everything else)

Parse them out:
1. Tokenize `$ARGUMENTS` respecting quoted strings.
2. Find the first token that looks like a video path. Expand `~` to `$HOME`. Strip surrounding quotes. If the token contains escaped spaces (`\ `), unescape them.
3. If the path exists and resolves to a video file → that is `SRC`. Remove it from the arguments; the remainder is the story direction.
4. If no path token is found → fall through to Step 1's cwd search; the full `$ARGUMENTS` is the story direction.

If, after parsing, the story direction is empty → report:
*"Usage: /myvibe-edit [path/to/video] <story direction>. Examples:*
*  /myvibe-edit a 30-second hook about why traditional note apps fail ADHD brains*
*  /myvibe-edit ~/Downloads/adhd.MOV story about ADHD-friendly capture"*
and stop.

All output files for this run live **alongside the source** (same directory as `SRC`), not in the current working directory. This way the user can invoke from anywhere and outputs land next to the input.

## Step 1 — Locate source video (only if no path was passed)

- Search the current working directory for `.MOV`, `.mp4`, `.mov`, `.MP4` files
- Exclude anything in `desktop-app-demos/`, `mobile-demos/`, or any path containing `_clean`, `_overlay`, `_myvibe`, `_v2`, or `_final` (those are derivatives)
- If exactly one candidate → use it
- If multiple → pick the one with the most recent mtime
- If zero → report *"No source video found in $(pwd) and no path was passed. Either cd into a folder containing a video or paste a path into the command."* and stop
- Save the path as `SRC` for the remaining steps

## Step 2 — Analyze (cached)

Check for `${SRC%.*}-ANALYSIS.md` next to the source.

- **If it exists** and contains a cut list table → load it, skip to step 4
- **Else** run `claude-video-vision:watch-video` with `video_analyze` and `silence: true, transcription: true, scene_changes: true`
- Save the analysis to `${SRC%.*}-ANALYSIS.md` in the format specified in SKILL.md (header, silence intervals, transcript with timings, scene changes)

## Step 3 — Identify takes and pick winners

From the transcript:
- Group repeated lines (the speaker re-recording the same sentence)
- For each group of takes, sample frames from each take via `claude-video-vision:video_detail` / `video_watch`
- Score each take on: facial expressiveness, eye contact, framing, audio clarity, blink/half-blink
- Pick the winner per the criteria in SKILL.md
- Record the choice + reasoning in the analysis file

## Step 4 — Build cut list aligned to the story direction

The user's direction is: `$ARGUMENTS`

Build a cut list that follows the **storytelling arc** in SKILL.md:
1. Hook (relatable pain, 1 sentence)
2. Problem (status quo / why it's painful)
3. Solution intro ("I made X where I just…")
4. Demo action
5. Result / reveal
6. Recall or benefit
7. Close

Drop any take that doesn't advance the arc — even if it was the best take of that line. The story direction overrides take-coverage.

For each kept take, compute sub-ranges per the **Hard rules** in SKILL.md (zero silence, +0.5s tail buffer, special handling for first/last sub-range). Save the resulting cut list to the analysis file as a table:

| # | src_start | src_end | edited_start | edited_end | transcript |

## Step 5 — Render cleaned video

Use `hevc_videotoolbox`. Output path: `${SRC%.*}_clean.mp4`. Apply the cut list with the ffmpeg pattern in SKILL.md (trim/setpts/scale/pad → concat).

Verify the output exists and has duration > 0 before continuing.

## Step 6 — Overlay product demos (if available)

Look for sibling folders `desktop-app-demos/`, `mobile-demos/`, or `overlays/` relative to the source.

- If none exist → skip this step entirely, the cleaned video becomes the input to step 7
- If they exist → for each phrase in the cut transcript, find the demo clip whose name or `-ANALYSIS.md` matches semantically
  - If a candidate has no analysis, run `claude-video-vision:watch-video` on it once and save
- Compute the edited-timeline timestamp for each matched phrase (cumulative duration from step 4)
- Render overlays per the SKILL.md pattern (portrait 1080×1920 canvas, landscape demos centered, mobile demos full-frame, `tpad` to extend speaker, `eof_action=pass`)
- Output: `${SRC%.*}_overlay.mp4`

If no overlays match cleanly, skip rather than forcing bad matches.

## Step 7 — Burn in Mino Lee captions (always, in this command)

> **Override:** The SKILL.md hard rule "never add captions unless explicitly asked" does NOT apply to `/myvibe-edit`. Invoking this command IS the explicit request for captions.

Build a recipe JSON from the cut list in the analysis file:

```json
{
  "input": "<previous step output>",
  "output": "${SRC%.*}_myvibe.mp4",
  "cuts": [
    {"edited_start": ..., "edited_end": ..., "transcript": "..."},
    ...
  ]
}
```

Save it to `${SRC%.*}-captions.json`, then run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/mino_captions.py" "${SRC%.*}-captions.json"
```

The helper handles word-timing distribution, chunking, no-flicker holds, and the Mino Lee layout (Proxima Nova Semibold, 2-word chunks, y=0.6*h, white + drop shadow). Font path is auto-resolved from `~/Library/Fonts/Proxima-Nova-Semibold.ttf` with plugin-bundled fallback.

## Step 8 — Report

Print a final summary block:

```
✓ Edit complete
  Source:     <SRC>
  Final:      <SRC stem>_myvibe.mp4
  Duration:   <secs>s (from <orig>s, cut <pct>%)
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
