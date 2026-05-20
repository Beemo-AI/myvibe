#!/usr/bin/env bash
# edits-workflow doctor — verifies the environment without installing anything.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FONT_SYS="$HOME/Library/Fonts/Proxima-Nova-Semibold.ttf"
FONT_BUNDLED="$PLUGIN_ROOT/assets/fonts/Proxima-Nova-Semibold.ttf"

pass=0; fail=0; warn=0
ok()   { printf "\033[32m✓\033[0m %s\n" "$*"; pass=$((pass+1)); }
bad()  { printf "\033[31m✗\033[0m %s\n" "$*"; fail=$((fail+1)); }
warn() { printf "\033[33m!\033[0m %s\n" "$*"; warn=$((warn+1)); }

printf "\033[1medits-workflow doctor\033[0m\n\n"

[[ "$(uname)" == "Darwin" ]] && ok "macOS" || bad "macOS required (hevc_videotoolbox is Apple-only)"

command -v brew >/dev/null 2>&1 && ok "Homebrew" || bad "Homebrew missing — run /edits-setup"

if command -v ffmpeg >/dev/null 2>&1; then
  ok "ffmpeg ($(ffmpeg -version | head -1 | cut -d' ' -f1-3))"
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_videotoolbox; then
    ok "hevc_videotoolbox encoder"
  else
    bad "hevc_videotoolbox missing — brew reinstall ffmpeg"
  fi
else
  bad "ffmpeg missing — run /edits-setup"
fi

if [[ -f "$FONT_SYS" ]]; then
  ok "Proxima Nova Semibold installed at $FONT_SYS"
elif [[ -f "$FONT_BUNDLED" ]]; then
  warn "Font not installed system-wide, but bundled copy exists at $FONT_BUNDLED — captions still work via fontfile path"
else
  bad "Proxima Nova font missing entirely — run /edits-setup"
fi

if compgen -G "$HOME/.claude/plugins/**/*claude-video-vision*" >/dev/null 2>&1 \
   || find "$HOME/.claude/plugins" -maxdepth 6 -type d -name "*claude-video-vision*" 2>/dev/null | grep -q .; then
  ok "claude-video-vision plugin"
else
  warn "claude-video-vision plugin not detected — needed for silence detection + transcription"
fi

command -v python3 >/dev/null 2>&1 && ok "python3 ($(python3 --version 2>&1))" || warn "python3 missing — captions helper unavailable"

printf "\n\033[1m%d passed, %d warnings, %d failed\033[0m\n" "$pass" "$warn" "$fail"
[[ $fail -eq 0 ]] && exit 0 || exit 1
