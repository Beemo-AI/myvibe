---
description: Edit a mixed folder containing talking-head clips, product demo screen recordings, and b-roll. Auto-classifies each clip, builds a talking-head spine, and overlays demos at matching moments. Captioned.
argument-hint: [path/to/mixed-folder] <optional story direction>
---

# /myvibe-product-demo — talking + demos + b-roll

You are running `/myvibe-product-demo`. The input is a mixed folder. Auto-classify each clip into one of three roles, build the spine from talking-head clips, and overlay demos and b-roll at semantically-matching moments.

Run autonomously. Do not ask clarifying questions unless blocked.

**Raw arguments:** `$ARGUMENTS`

---

## Step 0 — Parse arguments

Tokenize respecting quotes. Find the first token resolving to an existing path.

- Path is a directory → `WORK_DIR=that_dir`. Search **recursively** for video files.
- Path is a file → treat the file as the only talking-head source and look for siblings recursively under its parent dir for demos/b-roll.
- No path token → `WORK_DIR=$(pwd)`, recurse from cwd.

Remainder is the **story direction** (optional). If absent → incorporate all available talking-head content arranged chronologically, with all matching demos and b-roll overlaid at their natural moments.

## Step 1 — Recursively gather sources

Find all video files under `WORK_DIR` recursively. Same exclusions as `/myvibe-talking-head`.

## Step 2 — Classify each clip

For each video, sample 2–3 frames via `claude-video-vision:video_detail`. Classify into:

- **talking-head**: human face visible, person speaking, often portrait (vertical) framing
- **demo**: software/app UI, screen recording, no human face dominant, often landscape (1920×1080) or phone-portrait (882×1920)
- **broll**: ambient scene, object closeup, or environment — neither a face speaking nor a UI demo

Edge cases:
- Hands holding a phone with the app visible → **demo** (the product is the subject)
- Person walking through a space with no speech → **broll**
- Person on camera but no audio speech (b-roll of the creator) → **broll**

Save classifications to `${WORK_DIR}/myvibe-MASTER.md`:

| file | classification | duration | notes |

## Step 3 — Analyze every key file (required)

Run `claude-video-vision:watch-video` on every clip if no `<clip>-ANALYSIS.md` exists. Use `silence: true, transcription: true, scene_changes: true`. For demos and b-roll, transcription is usually empty but the scene description matters for matching.

## Step 4 — Build the talking-head spine

Apply the full `/myvibe-talking-head` workflow to the **talking-head clips only**:
- Dedupe takes across clips
- Pick best take per phrase
- Apply SKILL.md silence-cut rules
- Order by story direction (or chronologically if none given)
- Save the cut list to `myvibe-MASTER.md` with `source_file`, `src_start`, `src_end`, `edited_start`, `edited_end`, `transcript`

Render the spine as an intermediate: `${WORK_DIR}/${stem}_clean.mp4` per the SKILL.md multi-source ffmpeg pattern.

## Step 5 — Match demos to phrases

For each demo clip, read its analysis (scene description, UI text, app name) and match it to phrases in the cut transcript that semantically reference it ("instantly capture" → capture demo, "recall later" → search/recall demo).

Compute the **edited-timeline** start time for each matched phrase using cumulative sub-range durations from Step 4.

Stagger demos sequentially — no overlap. If a demo is longer than its target phrase, let it extend until the next demo starts. If total demo runtime exceeds remaining speaker audio, extend the spine with `tpad=stop_mode=clone:stop_duration=...`.

## Step 6 — Match b-roll to gaps

For each gap between demos (or moments in the spine that don't have a demo overlay) where the speaker is talking about something visualizable, optionally overlay a b-roll clip from the b-roll bucket. Match by scene description.

B-roll is *optional* — don't force a match if nothing fits. Demos are primary; b-roll is filler.

## Step 7 — Render overlays

Use the SKILL.md overlay pattern (portrait 1080×1920 canvas, demos centered with speaker visible above/below, mobile demos full-frame). Output: `${WORK_DIR}/${stem}_overlay.mp4`.

## Step 8 — Burn in Mino Lee captions

Build the recipe JSON from the cut list (transcript + edited timeline positions) and run `mino_captions.py`. Output: `${WORK_DIR}/${stem}_myvibe.mp4`.

## Step 9 — Report

Resolve the actual absolute path of the final file (no template placeholders, no `~`, no `${...}`). Print it on its own line at the very end so it's easy to copy:

```
✓ Product-demo edit complete
  Sources:      <total> file(s) under <WORK_DIR>
    talking:    <n>
    demos:      <n>
    b-roll:     <n>
  Duration:     <secs>s
  Takes used:   <kept> of <total candidates>
  Demos used:   <matched> of <available>
  B-roll used:  <matched> of <available>
  Render:       <total ffmpeg time>

Final file:
/absolute/path/to/<stem>_myvibe.mp4
```

**Verify the path exists** with `ls -lh "$FINAL_PATH"` before printing. If missing or 0 bytes, report the failure instead.

## Failures

Same as `/myvibe-talking-head`. If zero talking-head clips are classified → fall back to `/myvibe-storyteller` semantics if an audio file is present in the folder, otherwise stop and report.
