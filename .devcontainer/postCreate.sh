#!/bin/bash
set -euo pipefail

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.69}"
CODEX_VERSION="${CODEX_VERSION:-0.106.0}"
PNPM_VERSION="${PNPM_VERSION:-10.30.3}"

# Install AI tools
npm install -g \
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  "@openai/codex@${CODEX_VERSION}" \
  "pnpm@${PNPM_VERSION}"

# Setup SSH keys if mounted
if [ -d "$HOME/.ssh-host" ]; then
  mkdir -p ~/.ssh
  cp "$HOME"/.ssh-host/* ~/.ssh/ 2>/dev/null || true
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/* 2>/dev/null || true
fi

# Setup gitconfig if mounted
[ -f "$HOME/.gitconfig-host" ] && cp "$HOME/.gitconfig-host" ~/.gitconfig || true
