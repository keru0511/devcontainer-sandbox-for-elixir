#!/bin/bash
set -euo pipefail

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.69}"
CODEX_VERSION="${CODEX_VERSION:-0.106.0}"
PNPM_VERSION="${PNPM_VERSION:-10.30.3}"

# Install AI tools
npm install -g "pnpm@${PNPM_VERSION}"
export PNPM_HOME="${HOME}/.local/share/pnpm"
mkdir -p "${PNPM_HOME}"
export PATH="${PNPM_HOME}:${PATH}"
grep -qF 'PNPM_HOME' ~/.zshrc || echo 'export PNPM_HOME="${HOME}/.local/share/pnpm"
export PATH="${PNPM_HOME}:${PATH}"' >> ~/.zshrc
pnpm add -g \
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  "@openai/codex@${CODEX_VERSION}"

# Setup SSH keys if mounted
if [ -d "$HOME/.ssh-host" ]; then
  mkdir -p ~/.ssh
  cp "$HOME"/.ssh-host/* ~/.ssh/ 2>/dev/null || true
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/* 2>/dev/null || true
fi

# Setup gitconfig if mounted
[ -f "$HOME/.gitconfig-host" ] && cp "$HOME/.gitconfig-host" ~/.gitconfig || true

# Install mise (script saved before execution to avoid direct pipe-to-sh)
curl -fSL https://mise.run -o /tmp/mise-install.sh
sh /tmp/mise-install.sh
rm /tmp/mise-install.sh

grep -qF 'mise activate zsh' ~/.zshrc || echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
~/.local/bin/mise use -g erlang@27 elixir@1.18-otp-27

# Setup LazyVim
if [ ! -d ~/.config/nvim ]; then
  git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
fi
