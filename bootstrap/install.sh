#!/usr/bin/env bash
# bootstrap/install.sh
#
# Runs inside the temporary builder WSL instance to set up the pre-baked base image.
# Do NOT run this per project — it is only used by build-base.ps1.
#
# Expected: run as root inside a fresh Ubuntu 24.04 WSL instance.
# Expected: /tmp/opencode.json has been copied in by build-base.ps1.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "==> Updating package lists..."
apt-get update -q

echo "==> Installing base packages..."
apt-get install -y --no-install-recommends \
  git \
  curl \
  unzip \
  wget \
  xdg-utils \
  ca-certificates \
  gnupg \
  lsb-release \
  apt-transport-https

# ── GitHub CLI ─────────────────────────────────────────────────────────────────
echo "==> Installing GitHub CLI..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update -q
apt-get install -y gh

# ── Podman ─────────────────────────────────────────────────────────────────────
echo "==> Installing Podman..."
apt-get install -y podman

# ── Node.js LTS (system-wide via NodeSource) ───────────────────────────────────
# Installs to /usr/bin/node — available in all shell contexts, no sourcing needed.
echo "==> Installing Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# ── opencode ───────────────────────────────────────────────────────────────────
echo "==> Installing opencode..."
curl -fsSL https://opencode.ai/install | bash

# Make opencode available system-wide (install script puts it in ~/.local/bin)
if [ -f "/root/.local/bin/opencode" ]; then
  ln -sf /root/.local/bin/opencode /usr/local/bin/opencode
fi

# ── Shell configuration ────────────────────────────────────────────────────────
echo "==> Configuring shell..."

cat >> /root/.bashrc << 'BASHRC'

# opencode-wsl
export COLORTERM=truecolor
export BROWSER="/mnt/c/Progra~1/Google/Chrome/Application/chrome.exe"
alias docker=podman
BASHRC

# Also expose ~/.local/bin for login shells and non-login contexts
cat > /etc/profile.d/local-bin.sh << 'PROFILE'
export PATH="/root/.local/bin:$PATH"
PROFILE

# ── opencode privacy config ────────────────────────────────────────────────────
echo "==> Applying opencode privacy config..."
mkdir -p /root/.config/opencode
cp /tmp/opencode.json /root/.config/opencode/config.json

# ── Cleanup ────────────────────────────────────────────────────────────────────
echo "==> Cleaning up apt cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "Bootstrap complete."
echo "Versions installed:"
node --version
gh --version | head -1
podman --version
opencode --version 2>/dev/null || echo "opencode: installed (run 'opencode --version' to verify)"
