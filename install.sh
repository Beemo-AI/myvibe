#!/usr/bin/env bash
# One-line installer for the myvibe Claude Code plugin.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Beemo-AI/myvibe/main/install.sh | bash

set -euo pipefail

REPO="${MYVIBE_REPO:-Beemo-AI/myvibe}"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }

if [[ "$(uname)" != "Darwin" ]]; then
  red "myvibe requires macOS. Detected: $(uname)"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  red "Claude Code CLI not found."
  yellow "Install it first: https://docs.anthropic.com/claude/docs/claude-code"
  exit 1
fi

bold "Adding myvibe marketplace from $REPO"
claude plugin marketplace add "$REPO" || true

bold "Installing myvibe plugin"
claude plugin install myvibe@myvibe || claude plugin install myvibe

bold "Running /myvibe-setup"
if [[ -t 0 ]]; then
  claude --command "/myvibe-setup" || yellow "Run /myvibe-setup inside Claude Code to finish setup."
else
  green "Plugin installed."
  yellow "Open Claude Code and run:  /myvibe-setup"
fi

green "Done. Open a folder with a video and ask Claude to edit it."
