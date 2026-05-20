# myvibe

**Get your story known with AI assisted editing and stand out in the AI slop era.**

Talking-head video editing for Claude Code. Cut silences, pick the best take, overlay product demos, and burn in Mino Lee–style captions — all driven by Claude using the conventions in `SKILL.md`.

> **Mac-only.** The renderer uses `hevc_videotoolbox`, Apple's hardware HEVC encoder.

## Install

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/Beemo-AI/myvibe/main/install.sh | bash
```

Or manually from inside Claude Code:

```
/plugin marketplace add Beemo-AI/myvibe
/plugin install myvibe
/myvibe-setup
```

`/myvibe-setup` installs Homebrew (if missing), `ffmpeg`, the bundled Proxima Nova Semibold font, and verifies the `claude-video-vision` plugin.

## Use

Three explicit edit modes — pick the one that matches your input:

```
/myvibe-talking-head [path-or-folder] <optional direction>
```
Speaker-on-camera clips only. Cuts silences, picks the best take of each line across all clips (subdirectories included), captions. No overlays.

```
/myvibe-storyteller <voiceover.mp3> [clips-folder] <optional focus>
```
Voiceover-driven. The audio is the timeline; silences in the voiceover are cut, visual clips are matched to each line and overlaid, captions burned from the cleaned transcript.

```
/myvibe-product-demo [folder] <optional direction>
```
Mixed input — talking-head clips, product demo screen recordings, and b-roll all in one folder. Auto-classifies each clip, builds the talking-head spine, overlays demos at semantically-matching phrases, captions.

Not sure which to use? `/myvibe-edit <path>` inspects your input and recommends one.

**Universal defaults** (apply to every mode):
- Directory inputs are searched **recursively**
- Duplicate takes are deduped across all clips
- Silences are removed per the standard rules (zero silence, +0.5s tail buffer)
- Every key file is video-analyzed before editing
- No story direction or focus → uses all source material

Examples:
```
/myvibe-talking-head ~/Downloads/raw-takes/ a 30-second hook about ADHD note apps
/myvibe-storyteller ~/Downloads/vo.mp3 ~/Downloads/broll/ focus on the funny moments
/myvibe-product-demo ~/Downloads/launch-folder/ a one-minute pitch
```

Outputs land in the input directory: `<stem>_myvibe.mp4`.

For finer control you can also drive the skill in natural language:

1. `cd` into a folder containing a source video (`.MOV`, `.mp4`).
2. Open Claude Code.
3. Ask: *"Edit `adhd.MOV` into a 30-second TikTok hook with the storytelling arc."*

Claude follows the workflow in `skills/myvibe/SKILL.md`:
1. Watches the source via `claude-video-vision` (silence detection + transcription + scene changes).
2. Identifies duplicate takes and picks the best one based on facial expression, framing, and audio.
3. Builds a cut list (zero silence, words intact).
4. Renders with `ffmpeg` + `hevc_videotoolbox`.
5. Overlays product demos when relevant.
6. Burns in Mino Lee captions **only when explicitly asked**.

## Commands

- `/myvibe-talking-head [path] <direction>` — clean talking-head edits, no overlays
- `/myvibe-storyteller <vo.mp3> [clips] <focus>` — voiceover spine + visual clips
- `/myvibe-product-demo [folder] <direction>` — talking-head + auto-overlaid demos + b-roll
- `/myvibe-edit [path]` — chooser; recommends which mode to run
- `/myvibe-setup` — install ffmpeg, the font, and verify deps
- `/myvibe-doctor` — verify the environment without installing

## What ships with the plugin

```
myvibe/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/myvibe/SKILL.md
├── commands/
│   ├── myvibe-edit.md              # chooser
│   ├── myvibe-talking-head.md
│   ├── myvibe-storyteller.md
│   ├── myvibe-product-demo.md
│   ├── myvibe-setup.md
│   └── myvibe-doctor.md
├── scripts/
│   ├── setup.sh
│   ├── doctor.sh
│   └── mino_captions.py
└── assets/fonts/
    └── Proxima-Nova-Semibold.ttf
```

## Font license

The bundled `Proxima-Nova-Semibold.ttf` is included under a license held by Beemo. Redistribution of this plugin includes redistribution of the font under that license. If you fork and intend to publish under your own name, you must obtain your own Proxima Nova license or substitute a freely-licensed font (e.g. Montserrat SemiBold).

## Hard rules baked in

- **No silence in the output.** Cuts are exact at silence boundaries, with a 0.5s tail buffer so soft consonants survive.
- **No captions unless explicitly requested.** The default render is caption-free.
- **iPhone 4K HEVC is downscaled to 1080×1920** at render time.

See `skills/myvibe/SKILL.md` for the complete spec.

## License

MIT for the plugin code. Proxima Nova font under separate license (see above).
