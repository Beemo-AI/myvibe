---
name: myvibe
description: Edit talking-head videos (TikTok / Reels / Shorts) with silence cuts, take selection, demo overlays, and optional Mino Lee captions. Use when the user asks to edit a video, cut silences, build a viral hook, overlay product demos, or burn in captions. Mac-only — requires ffmpeg with hevc_videotoolbox.
---

# Video editing workflow

## Universal defaults — apply to every edit command

These rules hold across `/myvibe-talking-head`, `/myvibe-storyteller`, and `/myvibe-product-demo` unless the command file explicitly overrides:

- **Recursive directory traversal.** When given a directory, search subdirectories too (excluding `desktop-app-demos/`, `mobile-demos/`, `overlays/`, and derivative names `*_clean*`, `*_overlay*`, `*_myvibe*`).
- **Dedupe takes across all sources.** If the same line appears in multiple files (or multiple times within one file), pick one winner via frame-sampling + the SKILL.md scoring criteria. Drop the rest.
- **Cut silences per the Hard rules below.** Zero silence in any output. The `+0.5s` tail buffer is mandatory for non-final cuts.
- **Video analysis on every key file is required.** Run `claude-video-vision:watch-video` on every source clip if no `<clip>-ANALYSIS.md` exists. Don't skip this even if it's slow on first run — subsequent runs reuse the cache.
- **No focus → use everything.** If the user doesn't specify "focus on X" or a story direction that prunes content, incorporate all available source material. Don't be selective without a reason.

## File rules — read carefully

When the user asks for further edits:
- **Source video to edit FROM**: the *last iteration* of the video the user originally started with. If the user said "edit `/Users/.../adhd.MOV`" and we have produced `adhd_clean.mp4` from it, the next iteration edits `adhd_clean.mp4` (the latest derivative), not the original `.MOV`. Always look at the user video the user used
- **Output video to edit TO**: the *latest output* path the user has been referencing. Overwrite it (do not create new `_v2`, `_v3` files unless the user asks).
- **Do not touch any other videos** in the project directory or sibling demo folders. Demo clips are read-only sources for overlays.

Tracking: at the end of each session, the latest output is whatever path was last written.

## Hard rules — DO NOT violate

- **NEVER add captions / burned-in subtitles** to any output. Do not use the `subtitles` ffmpeg filter, do not generate SRT/ASS files for caption burn-in. Only add captions if the user explicitly asks for them in the current request. **Exception:** the `/myvibe-talking-head`, `/myvibe-storyteller`, and `/myvibe-product-demo` slash commands ARE explicit requests for captions — those commands always produce a captioned final.
- **NEVER include silence** in the output. Not at the front, not at the end, not between cuts.
  - Cut START: EXACTLY at silence-end (`silence_start + duration`). Zero padding before speech.
  - Cut END: at the next `silence_start + ~0.5s`. The `+0.5s` is critical — `silencedetect` is too aggressive and clips trailing soft consonants (e.g. the "s" in "months", the "t" in "it"). Without this buffer, words get cut off mid-sound. The tail buffer is trailing word audio, not silence.
  - For the very first sub-range, trim an extra ~30–50 ms into speech at the start to remove any pre-speech ramp-up.
  - For the very last sub-range, end exactly at silence-start (no `+0.5s` buffer) to avoid trailing pause.
  - Result: cuts feel back-to-back, words are complete, no audible silence.

## Setup check (run this first if the user is new)

Before editing, verify the environment:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

If anything is missing, run `/myvibe-setup` to install it. The doctor script checks: ffmpeg, hevc_videotoolbox, the Proxima Nova font, and the `claude-video-vision` plugin.

## Workflow

### 1. Watch and analyze the source

Use the `claude-video-vision:watch-video` skill on the source. Always run `video_analyze` with `silence: true, transcription: true, scene_changes: true` first — the silence intervals + whisper transcript drive every cut decision.

Use this on any b-roll clips / overlay clips the user mentioned. Then after this watch, save in the same folder `<clip-name>-ANALYSIS.md`.

In future, always check for an existing analysis file before calling claude-video-vision on it.

### 2. Identify duplicates and bad takes from the transcript

Look for:
- Repeated lines (the speaker re-recording the same sentence multiple times) — keep the cleanest take, usually the last one before a long silence.
- Stutters, false starts ("the one project that worked, the one project of mine that...").
- Off-script confusion ("echo echo, what's the echo called?").
- Trailing silences before the speaker resets.

When two takes deliver the same line, **do not pick by transcript alone**. Use `video_detail` / `video_watch` to sample frames inside each take and choose the one with the stronger visual:
- More alluring/enticing facial expression (eye contact, confident delivery, expressive mouth shape mid-word vs flat/closed).
- Clearest, best-framed product demo (phone screen visible and readable, hands steady, app UI in focus, no glare/motion blur).
- Better composition (subject framed, no awkward looking-off, no half-blink).
- Better lighting / less blown-out highlights / less motion blur.

Note which take wins AND why in the analysis file so the rationale is recoverable.

### 3. Build the cut list

For each kept take, compute sub-ranges from the silence-detection data:
- Sub-range START: EXACTLY at `silence_start + duration` (the moment speech resumes). Zero padding.
- Sub-range END: at the next `silence_start + 0.5s` — the buffer preserves trailing soft consonants that silencedetect clips off.
- For the very first sub-range, trim an extra ~30–50 ms into speech at the start. For the very last sub-range, end at `silence_start` (no `+0.5s` buffer) so the video doesn't trail off into silence.
- The result: no silence anywhere in the output, but words are complete (no clipped "months" → "month").
- See the "Hard rules" section above — this rule is non-negotiable.

**Always save the cut list to the analysis file** as a table with three columns per sub-range: `(src_start, src_end, verified_transcript)`. Also compute and save the **edited-timeline** position of each cut (cumulative sum of durations). This data is the source of truth for caption rendering in step 6 — do not re-derive it from whisper later.

**Storytelling structure** for "viral TikTok hook → storytelling" requests: hook (relatable pain, 1 sentence) → problem (status quo / why it's painful) → solution intro ("I made X where I just…") → demo action → result / reveal → recall or benefit → close. Pick the take of each line that best serves this arc; cut anything that doesn't advance it.

### 4. Render with ffmpeg

Use `hevc_videotoolbox` for hardware acceleration on Mac. iPhone source is recorded as 3840×2160 with `rotation=90` metadata → effective portrait 2160×3840; scale and pad to 1080×1920 in the filter chain.

```bash
ffmpeg -y -i SOURCE -filter_complex "\
  [0:v]trim=A1:B1,setpts=PTS-STARTPTS,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1[v1];\
  [0:a]atrim=A1:B1,asetpts=PTS-STARTPTS[a1];\
  ... \
  [v1][a1][v2][a2]...concat=n=N:v=1:a=1[v][a]" \
  -map "[v]" -map "[a]" \
  -c:v hevc_videotoolbox -b:v 14M -tag:v hvc1 \
  -c:a aac -b:a 192k \
  OUTPUT
```

14 Mb/s is sufficient for 1080×1920 HEVC; bump to 25M only when the source remains 4K landscape.

### 5. Overlay product demos

When the user wants to lay demo clips on top of the cleaned speaker video:
- Identify which phrase in the transcript each demo corresponds to ("instantly capture" → capture demo, "recall them later" → recall demo, etc.).
- Look through any demo folders the user has (e.g. `desktop-app-demos/`, `mobile-demos/`) and pick the one whose title or analysis matches the phrase. If no existing analysis matches, watch a candidate clip with `claude-video-vision:watch-video` and save its analysis.
- Compute the cleaned-video timestamp where that phrase starts (cumulative sum of sub-range durations from step 3).
- Show demos in **full** (don't truncate). If a demo is longer than the relevant phrase, let it extend; if total demo runtime exceeds remaining speaker audio, the audio plays under the first demos and later demos play silently.
- Stagger sequentially to avoid overlap. Each demo starts when the previous ends (or at its target phrase, whichever is later).
- Extend the speaker video with `tpad=stop_mode=clone:stop_duration=...` if demos extend past speaker audio.
- Make sure to pick only the overlays and product demos that match this, ignore all others.

Pattern (portrait 1080×1920 canvas, landscape demos centered with speaker visible above/below, mobile portrait fills):

```bash
ffmpeg -y \
  -i CLEANED_SPEAKER \
  -i DEMO1 -i DEMO2 -i DEMO3 \
  -filter_complex "
    [0:v]scale=1080:1920,tpad=stop_mode=clone:stop_duration=PAD,setsar=1[bg];
    [1:v]scale=1080:-2,setsar=1,setpts=PTS-STARTPTS+T1/TB[d1];
    [2:v]scale=1080:-2,setsar=1,setpts=PTS-STARTPTS+T2/TB[d2];
    [3:v]scale=-2:1920,setsar=1,setpts=PTS-STARTPTS+T3/TB[d3];
    [bg][d1]overlay=(W-w)/2:(H-h)/2:enable='between(t,T1,T1+DUR1)':eof_action=pass[v1];
    [v1][d2]overlay=(W-w)/2:(H-h)/2:enable='between(t,T2,T2+DUR2)':eof_action=pass[v2];
    [v2][d3]overlay=(W-w)/2:(H-h)/2:enable='between(t,T3,T3+DUR3)':eof_action=pass[vout]
  " \
  -map "[vout]" -map "0:a" \
  -t TOTAL \
  -c:v hevc_videotoolbox -b:v 12M -tag:v hvc1 \
  -c:a aac -b:a 192k \
  OUTPUT
```

Key flags:
- `setpts=PTS-STARTPTS+T/TB` shifts the demo's first frame to output time `T`.
- `enable='between(t,T,T+DUR)'` only renders the overlay during its window.
- `eof_action=pass` lets the background show through when the demo ends.

### 6. Burn-in captions (only when the user asks)

When captions are requested, use a caption profile (see "Caption profiles" section) and follow these rules:

- **Do NOT re-transcribe the cut video to get word timings.** Tight back-to-back speech causes whisper to hallucinate duplicates and drop boundary words. Re-transcribing the original source also drifts at cut boundaries.
- **Use the verified per-cut transcript saved in the analysis file (step 3) as the source of truth.** Distribute word timings evenly across each cut's edited-timeline duration:
  ```python
  per_word = (edited_end - edited_start) / len(cut.split())
  for i, word in enumerate(cut.split()):
      w_start = edited_start + i * per_word
      w_end   = edited_start + (i + 1) * per_word
  ```
- **Never let a chunk straddle a cut boundary.** Force a break at every cut boundary AND at every terminal punctuation mark (`,`, `.`, `!`, `?`). Within a cut, group into chunks of the size the profile specifies (2 words for Mino Lee).
- **Hold each chunk until the next chunk begins** (or until the end of the video for the last chunk), so a caption is always on screen — no flicker gaps.
- Render with a `drawtext` chain (one filter per chunk) and `-c:a copy` since audio is unchanged.

A reference implementation lives at `${CLAUDE_PLUGIN_ROOT}/scripts/mino_captions.py` — copy and adapt for new edits rather than re-deriving the chunking logic.

## Caveats

- `silencedetect` and whisper sometimes disagree on speech boundaries (whisper may extend timestamps past silent gaps). When they conflict, trust `silencedetect` for cut points based on actual audio energy.
- iPhone 4K HEVC is slow to re-encode even with hardware acceleration (~1x realtime). Prefer downscaling to 1080p when overlaying demos to keep render times reasonable.
- Demo videos are landscape (1920×1080) and mobile is portrait (882×1920). The portrait canvas (1080×1920) lets the speaker frame the landscape demos naturally.

## Caption profiles

The "no captions" hard rule above still applies — only add captions when the user explicitly asks. When they do, use one of the profiles below by name.

### Mino Lee profile

The viral-minimalist style used by creator Mino Lee — TikTok's "Classic" font with a tight drop shadow, 2-word chunks synced to speech.

- **Font:** Proxima Nova Semibold (TikTok "Classic"). The plugin ships this font and installs it to `~/Library/Fonts/Proxima-Nova-Semibold.ttf` during `/myvibe-setup`. If the system install is missing, fall back to the plugin-bundled copy at `${CLAUDE_PLUGIN_ROOT}/assets/fonts/Proxima-Nova-Semibold.ttf`. Final fallback: `Montserrat-SemiBold.ttf` → `/System/Library/Fonts/HelveticaNeue.ttc`. Always check the installed path before falling back, and note any fallback used in the output summary.
- **Chunking:** ~2 words per on-screen chunk, advanced word-by-word. Never break a phrase across a comma — split at the next natural beat instead.
- **Layout (portrait 1080×1920):**
  - Text block width: **30% of video width** → max 324 px wide; wrap or shrink font to fit.
  - **Horizontally centered** (`x=(w-text_w)/2`).
  - **Vertically positioned at 60% from top** = `y=0.6*h` (= 40% from bottom, = 1152 px from top on a 1920-tall frame). Anchor by top edge of the text block.
- **Color:** white fill, with a tight drop shadow — `shadowcolor=black@0.85:shadowx=3:shadowy=3` (or 4/4 on 4K). No outline/stroke.
- **Weight/size:** start at `fontsize=72` for 1080×1920 and let the 30% width constraint shrink it for longer chunks. Bold/semibold only — never regular or italic.
- **Timing:** chunk visible from the first word's start to the last word's end + ~80 ms tail. No fade — hard cut on/off (Mino Lee's signature feel).

**ffmpeg pattern** (per-chunk drawtext, one line per chunk):

```bash
FONT="$HOME/Library/Fonts/Proxima-Nova-Semibold.ttf"
[ -f "$FONT" ] || FONT="${CLAUDE_PLUGIN_ROOT}/assets/fonts/Proxima-Nova-Semibold.ttf"

ffmpeg -y -i INPUT -vf "\
drawtext=fontfile='$FONT':text='two words':fontcolor=white:fontsize=72:shadowcolor=black@0.85:shadowx=3:shadowy=3:x=(w-text_w)/2:y=0.6*h:enable='between(t,T1,T2)',\
drawtext=fontfile='$FONT':text='next two':fontcolor=white:fontsize=72:shadowcolor=black@0.85:shadowx=3:shadowy=3:x=(w-text_w)/2:y=0.6*h:enable='between(t,T2,T3)'" \
  -c:v hevc_videotoolbox -b:v 14M -tag:v hvc1 -c:a copy OUTPUT
```

For long chunk lists, generate the drawtext chain programmatically using `${CLAUDE_PLUGIN_ROOT}/scripts/mino_captions.py`.
