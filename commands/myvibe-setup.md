---
description: Install ffmpeg, the Proxima Nova font, and the claude-video-vision plugin needed for the myvibe skill.
---

Run the setup script bundled with this plugin to install everything needed for video editing.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```

The script will:
1. Verify macOS (the workflow uses `hevc_videotoolbox` which is Apple-only)
2. Install Homebrew if missing
3. `brew install ffmpeg` if missing
4. Copy the bundled Proxima Nova Semibold font to `~/Library/Fonts/` and refresh the font cache
5. Check that the `claude-video-vision` plugin is installed; if missing, print the install command

After it finishes, run `/myvibe-doctor` to verify everything is working.
