---
description: Picks the right myvibe edit mode for your input. Routes to /myvibe-talking-head, /myvibe-storyteller, or /myvibe-product-demo.
argument-hint: [path] <optional direction>
---

# /myvibe-edit — chooser

`/myvibe-edit` is no longer a single workflow. Inspect the input and tell the user which command to run. Do NOT execute the edit yourself from this command — just route them.

**Raw arguments:** `$ARGUMENTS`

---

## Routing logic

Parse `$ARGUMENTS` for the first path token (file or directory, with `~` expansion and quote handling).

- **Audio file** (`.mp3 .wav .m4a .aac .flac .opus`) → recommend `/myvibe-storyteller`
- **Single video file** → recommend `/myvibe-talking-head` (unless they say "demo", "product", or "overlay" in the direction, then `/myvibe-product-demo`)
- **Directory** → look inside (recursively, just file extensions, no analysis yet):
  - Audio file present → `/myvibe-storyteller`
  - Mix of portrait + landscape videos (heuristic for talking + screen recordings) → `/myvibe-product-demo`
  - All portrait videos → `/myvibe-talking-head`
- **No path** → search cwd with the same rules

Report:

```
Pick a mode:

  /myvibe-talking-head [path] <direction>
    For a clip or folder of speaker-on-camera takes. Cuts silences, picks the
    best take of each line across all files, captions. No overlays.

  /myvibe-storyteller <voiceover.mp3> [clips-folder] <focus>
    For a voiceover-driven edit. The audio is the timeline spine; visual clips
    are matched to lines and laid on top. Voiceover pacing is preserved.

  /myvibe-product-demo [folder] <direction>
    For a mixed folder of talking-head + product demos + b-roll. Auto-classifies,
    builds the talking spine, overlays demos at matching phrases, captions.

Based on your input (<path>), I recommend: <chosen command>

Run it as:
  <chosen command> $ARGUMENTS
```

Do not edit anything. Wait for the user to invoke the recommended command.
