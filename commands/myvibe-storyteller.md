---
description: Build a storyteller edit from a voiceover audio file plus b-roll clips. The voiceover is the timeline spine; clips are matched to lines and laid on top. Auto-captioned.
argument-hint: <path/to/voiceover.mp3> [path/to/clips-folder] <optional focus>
---

# /myvibe-storyteller — voiceover-driven edit

You are running `/myvibe-storyteller`. The voiceover audio is the **timeline spine**: its duration is the final duration. Visual clips are matched to lines in the voiceover transcript and overlaid as b-roll. No silence cuts applied to the voiceover itself (the user wrote that pacing intentionally).

Run autonomously. Do not ask clarifying questions unless blocked.

**Raw arguments:** `$ARGUMENTS`

---

## Step 0 — Parse arguments

Tokenize respecting quotes. Find tokens that resolve to existing paths.

- First **audio file** path → `VO_AUDIO`. Required. Detection:
  - Extension is one of: `.mp3 .wav .m4a .aac .flac .opus .ogg` → audio
  - OR `ffprobe -v error -select_streams v:0 -show_entries stream=codec_type "$path"` returns empty (no video stream) → audio
- Next **path** (file or directory) → `CLIPS_PATH`. If it's a directory → recurse. If it's a file → it's a single b-roll clip. If absent → search `dirname(VO_AUDIO)` recursively.
- Remaining text → **focus** (optional). If no focus given, **incorporate all available clips** distributed across the voiceover timeline.

If no audio file present → report:
*"Usage: /myvibe-storyteller <voiceover.mp3> [clips-folder] [focus]. The first path must be an audio file."*
and stop.

`WORK_DIR` = `dirname(VO_AUDIO)`. Outputs land there.

## Step 1 — Recursively gather b-roll clips

Find all video files (any extension `.mp4 .mov .mkv .webm`) under `CLIPS_PATH`, recursively. Apply the same derivative exclusions as `/myvibe-talking-head`.

If zero clips found → report and stop. Storyteller edits without visuals are not useful.

## Step 2 — Analyze the voiceover (silence + transcript)

Wrap the audio as video so `claude-video-vision` can process it:

```bash
ffmpeg -y -i "$VO_AUDIO" -f lavfi -i color=black:s=640x360:r=1 -shortest -c:v libx264 -c:a aac "${VO_AUDIO%.*}_for_analysis.mp4"
```

Run `claude-video-vision:watch-video` on that wrapper with `silence: true, transcription: true`. Save full analysis (silence intervals + word-level transcript) to `${VO_AUDIO%.*}-ANALYSIS.md` per SKILL.md format.

## Step 2.5 — Cut silences from the voiceover (required)

Apply the SKILL.md **Hard rules** to the voiceover audio:
- Each sub-range starts EXACTLY at `silence_end` (= `silence_start + duration`). Zero padding.
- Each sub-range ends at the next `silence_start + 0.5s` (soft-consonant buffer), except the last sub-range which ends at `silence_start` cleanly.
- First sub-range trims ~30–50ms further into speech to drop ramp-up.

Build a cut list with `edited_start`, `edited_end`, `transcript` columns where `edited_*` are positions in the CLEANED timeline (cumulative durations).

Render the cleaned voiceover to `${WORK_DIR}/${VO_STEM}_voiceover_clean.m4a`:

```bash
ffmpeg -y -i "$VO_AUDIO" -filter_complex "\
  [0:a]atrim=A1:B1,asetpts=PTS-STARTPTS[a1];\
  [0:a]atrim=A2:B2,asetpts=PTS-STARTPTS[a2];\
  ...\
  [a1][a2]...concat=n=N:v=0:a=1[a]" \
  -map "[a]" -c:a aac -b:a 192k \
  "${WORK_DIR}/${VO_STEM}_voiceover_clean.m4a"
```

The CLEANED voiceover is the timeline spine from here on. All clip matching, overlay timing, and captions reference its edited timestamps — not the original audio's.

Save the cut list to `${WORK_DIR}/myvibe-MASTER.md`.

## Step 3 — Analyze every clip (required)

Same as `/myvibe-talking-head` Step 2 — every clip in `CLIPS_PATH` must have an analysis file. Run `claude-video-vision:watch-video` on each. Save `<clip>-ANALYSIS.md` next to each clip.

For storyteller clips, what matters most from the analysis is: scene description, dominant colors, motion energy, on-screen subject. The clip's own audio is muted in the final mux.

## Step 4 — Match clips to voiceover lines

Split the **cleaned** voiceover transcript into sentences using `edited_start` / `edited_end` timestamps from the cut list (Step 2.5), not the original source timestamps.

For each line, score every clip on semantic match using the clip's analysis (description, subject, motion). Pick the best clip for each line.

Rules:
- A clip can be reused if there are not enough unique matches — but prefer not to reuse within 10 seconds.
- If `focus` was specified, weight clips matching the focus higher.
- If no focus, **distribute all available clips** so the visual track stays varied across the voiceover duration.
- Clips that don't match any line still get used as transitional b-roll, distributed evenly in unfilled gaps.

Save the matching to `${WORK_DIR}/myvibe-MASTER.md` as:

| vo_start | vo_end | clip_file | clip_in | clip_out | line |

`clip_in` / `clip_out` are sub-ranges within the clip. If the clip is shorter than the line, the clip plays once and the next-best clip fills the rest. If longer than the line, trim from a visually-strong portion.

## Step 5 — Render

Portrait 1080×1920 canvas. The voiceover audio is the only audio track. For each `(vo_start, vo_end, clip)` row, scale/pad the clip to fill the canvas and overlay during its window, with `eof_action=pass` so gaps fall through to whatever the previous clip was (or black if first).

Pattern:

```bash
ffmpeg -y \
  -i "${WORK_DIR}/${VO_STEM}_voiceover_clean.m4a" \
  -i CLIP_1 -i CLIP_2 -i CLIP_3 \
  -filter_complex "
    color=black:s=1080x1920:d=DURATION,setsar=1[bg];
    [1:v]scale=1080:1920:force_original_aspect_ratio=cover,crop=1080:1920,setpts=PTS-STARTPTS+T1/TB,setsar=1[c1];
    [2:v]scale=1080:1920:force_original_aspect_ratio=cover,crop=1080:1920,setpts=PTS-STARTPTS+T2/TB,setsar=1[c2];
    [3:v]scale=1080:1920:force_original_aspect_ratio=cover,crop=1080:1920,setpts=PTS-STARTPTS+T3/TB,setsar=1[c3];
    [bg][c1]overlay=0:0:enable='between(t,T1,T1+DUR1)':eof_action=pass[v1];
    [v1][c2]overlay=0:0:enable='between(t,T2,T2+DUR2)':eof_action=pass[v2];
    [v2][c3]overlay=0:0:enable='between(t,T3,T3+DUR3)':eof_action=pass[vout]
  " \
  -map "[vout]" -map "0:a" \
  -t DURATION \
  -c:v hevc_videotoolbox -b:v 14M -tag:v hvc1 \
  -c:a aac -b:a 192k \
  "${WORK_DIR}/${VO_STEM}_clean.mp4"
```

`DURATION` is the **cleaned** voiceover duration (sum of edited sub-ranges from Step 2.5). `VO_STEM` is the voiceover filename without extension.

## Step 6 — Captions from the cleaned voiceover

Build a recipe JSON from the cleaned cut list. The `edited_*` positions already match the rendered video timeline:

```json
{
  "input": "${WORK_DIR}/${VO_STEM}_clean.mp4",
  "output": "${WORK_DIR}/${VO_STEM}_myvibe.mp4",
  "cuts": [{"edited_start": ..., "edited_end": ..., "transcript": "..."}, ...]
}
```

Run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/mino_captions.py" "${WORK_DIR}/${VO_STEM}-captions.json"
```

## Step 7 — Report

```
✓ Storyteller edit complete
  Voiceover:  <VO_AUDIO> (<secs>s)
  Clips used: <n unique> of <m available>
  Final:      <WORK_DIR>/<VO_STEM>_myvibe.mp4
  Render:     <total ffmpeg time>
```

## Failures

- Audio file missing or unreadable → stop
- No clips found → stop
- Transcription empty → stop, suggest the user re-record or check audio quality
- ffmpeg error → surface stderr verbatim
