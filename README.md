# myvibe

AI-assisted talking-head video editing for Claude Code. Cut silences, pick the best take, overlay product demos, and (optionally) burn in Mino Lee–style captions — all driven by Claude using the conventions in `SKILL.md`.

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

The fast path is one command:

```
/myvibe-edit <story direction>
```

Example:
```
/myvibe-edit a 30-second hook about why traditional note apps fail ADHD brains
```

It picks the newest video in the current folder, analyzes it, cuts silences, picks the best take of each line, overlays any matching product demos from sibling `desktop-app-demos/` / `mobile-demos/` folders, burns in Mino Lee captions, and writes `<source>_myvibe.mp4`. No questions asked.

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

- `/myvibe-edit <story direction>` — full pipeline, analyze → cut → overlay → caption → render
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
│   ├── myvibe-edit.md
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
