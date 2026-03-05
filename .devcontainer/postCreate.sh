#!/bin/bash
set -euo pipefail

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.69}"
CODEX_VERSION="${CODEX_VERSION:-0.106.0}"
PNPM_VERSION="${PNPM_VERSION:-10.30.3}"
MISE_VERSION="${MISE_VERSION:-v2024.12.20}"
LAZYVIM_VERSION="${LAZYVIM_VERSION:-v14.0.0}"

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

# Install mise (version-pinned, checksum-verified)
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then MISE_PLATFORM="linux-x86_64"; else MISE_PLATFORM="linux-arm64"; fi
MISE_BINARY="mise-${MISE_VERSION}-${MISE_PLATFORM}"
curl -fSL "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/${MISE_BINARY}" -o /tmp/mise
curl -fSL "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/${MISE_BINARY}.sha256" -o /tmp/mise.sha256
EXPECTED=$(awk '{print $1}' /tmp/mise.sha256)
ACTUAL=$(sha256sum /tmp/mise | awk '{print $1}')
[ "$EXPECTED" = "$ACTUAL" ] || { echo "mise SHA256 mismatch"; exit 1; }
mkdir -p ~/.local/bin
install -m 755 /tmp/mise ~/.local/bin/mise
rm /tmp/mise /tmp/mise.sha256

grep -qF 'mise activate zsh' ~/.zshrc || echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
~/.local/bin/mise use -g erlang@27 elixir@1.18

# Setup LazyVim (version-pinned)
if [ ! -d ~/.config/nvim ]; then
  git clone --branch "${LAZYVIM_VERSION}" --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
fi
