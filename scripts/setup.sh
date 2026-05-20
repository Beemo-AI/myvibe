#!/usr/bin/env bash
# edits-workflow setup — installs ffmpeg, the bundled Proxima Nova font, and verifies claude-video-vision.
# Idempotent: safe to re-run.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FONT_SRC="$PLUGIN_ROOT/assets/fonts/Proxima-Nova-Semibold.ttf"
FONT_DEST="$HOME/Library/Fonts/Proxima-Nova-Semibold.ttf"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
step()  { printf "\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n" "$*"; }

# ---------- 1. OS check ----------
step "Checking platform"
if [[ "$(uname)" != "Darwin" ]]; then
  red "edits-workflow requires macOS — hevc_videotoolbox (Apple hardware encoder) is not available on other platforms."
  exit 1
fi
green "✓ macOS detected"

# ---------- 2. Homebrew ----------
step "Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  yellow "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # shellcheck disable=SC2016
  if [[ -d /opt/homebrew/bin ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  if [[ -d /usr/local/bin ]]; then eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"; fi
fi
green "✓ Homebrew: $(brew --version | head -1)"

# ---------- 3. ffmpeg ----------
step "Checking ffmpeg"
if ! command -v ffmpeg >/dev/null 2>&1; then
  yellow "ffmpeg not found. Installing via Homebrew (this can take a few minutes)..."
  brew install ffmpeg
else
  green "✓ ffmpeg: $(ffmpeg -version | head -1)"
fi

# ---------- 4. hevc_videotoolbox availability ----------
step "Checking hevc_videotoolbox encoder"
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_videotoolbox; then
  green "✓ hevc_videotoolbox available"
else
  red "✗ hevc_videotoolbox not present in this ffmpeg build. Renders will be slow."
  yellow "  Try: brew reinstall ffmpeg"
fi

# ---------- 5. Proxima Nova font ----------
step "Installing Proxima Nova Semibold font"
if [[ ! -f "$FONT_SRC" ]]; then
  red "✗ Bundled font missing at $FONT_SRC"
  exit 1
fi
mkdir -p "$HOME/Library/Fonts"
if [[ -f "$FONT_DEST" ]] && cmp -s "$FONT_SRC" "$FONT_DEST"; then
  green "✓ Font already installed at $FONT_DEST"
else
  cp "$FONT_SRC" "$FONT_DEST"
  green "✓ Installed font to $FONT_DEST"
  # Refresh font cache so apps see it immediately
  if command -v atsutil >/dev/null 2>&1; then
    atsutil databases -remove >/dev/null 2>&1 || true
  fi
fi

# ---------- 6. claude-video-vision plugin ----------
step "Checking claude-video-vision plugin"
VV_DIR=$(find "$HOME/.claude/plugins" -maxdepth 6 -type d -name "*claude-video-vision*" 2>/dev/null | head -1)
if [[ -n "$VV_DIR" ]]; then
  green "✓ claude-video-vision installed at $VV_DIR"
else
  yellow "claude-video-vision plugin not detected."
  yellow "  Install with:"
  yellow "    /plugin marketplace add anthropics/claude-video-vision"
  yellow "    /plugin install claude-video-vision"
  yellow "  Then run the setup wizard: invoke skill 'claude-video-vision:setup-video-vision'"
fi

# ---------- 7. Python (for caption helper) ----------
step "Checking Python 3 (used by mino_captions.py)"
if command -v python3 >/dev/null 2>&1; then
  green "✓ python3: $(python3 --version)"
else
  yellow "python3 not found. Captions helper will not run. Install via: brew install python"
fi

echo
bold "Setup complete."
echo "Next: open a folder with a source video and ask Claude to edit it."
echo "  Example: 'edit ./adhd.MOV — cut silences, build a TikTok hook'"
