#!/usr/bin/env bash
# bootstrap/install.sh
#
# Runs inside the temporary builder WSL instance to set up the pre-baked base image.
# Do NOT run this per project — it is only used by build-base.ps1.
#
# Expected: run as root inside a fresh Ubuntu 24.04 WSL instance.
# Expected: /tmp/opencode.json has been copied in by build-base.ps1.

set -euo pipefail

resolve_path() {
    local path="$1"
    if [[ -n "${OPENCODE_WSL_ROOT_PREFIX:-}" ]]; then
        printf '%s%s' "$OPENCODE_WSL_ROOT_PREFIX" "$path"
    else
        printf '%s' "$path"
    fi
}

TMP_INSTALL_SH="$(resolve_path /tmp/install.sh)"
TMP_CONFIG="$(resolve_path /tmp/opencode.json)"
ROOT_HOME="$(resolve_path /root)"
ROOT_BASHRC="$ROOT_HOME/.bashrc"
OPENCODE_BIN="$ROOT_HOME/.opencode/bin/opencode"
LOCAL_BIN_DIR="$(resolve_path /usr/local/bin)"
LOCAL_BIN_OPENCODE="$LOCAL_BIN_DIR/opencode"
CONFIG_DIR="$ROOT_HOME/.config/opencode"
CONFIG_PATH="$CONFIG_DIR/opencode.json"
KEYRING_DIR="$(resolve_path /usr/share/keyrings)"
GITHUB_KEYRING="$KEYRING_DIR/githubcli-archive-keyring.gpg"
APT_SOURCES_DIR="$(resolve_path /etc/apt/sources.list.d)"
GITHUB_SOURCE_LIST="$APT_SOURCES_DIR/github-cli.list"

# ── Guard clauses ─────────────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

if [[ ! -f "$TMP_CONFIG" ]]; then
    echo "ERROR: /tmp/opencode.json not found. This script should be run by build-base.ps1." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ── Prepare directories ────────────────────────────────────────────────────────
echo "==> Preparing filesystem layout..."
mkdir -p "$KEYRING_DIR" "$APT_SOURCES_DIR" "$(dirname "$ROOT_BASHRC")" "$CONFIG_DIR" "$LOCAL_BIN_DIR"

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
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of="$GITHUB_KEYRING" 2>/dev/null
chmod go+r "$GITHUB_KEYRING"
echo "deb [arch=$(dpkg --print-architecture) signed-by=$GITHUB_KEYRING] https://cli.github.com/packages stable main" \
  > "$GITHUB_SOURCE_LIST"
apt-get update -q
apt-get install -y gh

# ── Podman ─────────────────────────────────────────────────────────────────────
# podman-docker provides /usr/bin/docker → podman, so tools calling docker as a
# subprocess (not just in the shell) also work without any alias.
echo "==> Installing Podman..."
apt-get install -y podman podman-docker

# ── opencode ───────────────────────────────────────────────────────────────────
echo "==> Installing opencode..."
# Trust model: Official opencode installer from opencode.ai.
# Installs the opencode binary to ~/.opencode/bin.
# The Bats unit test mocks this installer under OPENCODE_WSL_ROOT_PREFIX.
# Real installer behavior is covered end-to-end by tests/integration/E2E.Tests.ps1.
curl -fsSL https://opencode.ai/install | bash

# Make opencode available system-wide (install script puts it in ~/.opencode/bin)
if [[ -f "$OPENCODE_BIN" ]]; then
  ln -sf "$OPENCODE_BIN" "$LOCAL_BIN_OPENCODE"
fi

# ── Shell configuration ────────────────────────────────────────────────────────
echo "==> Configuring shell..."

cat >> "$ROOT_BASHRC" << 'BASHRC'

# opencode-wsl
export COLORTERM=truecolor
export BROWSER="/mnt/c/Progra~2/Microsoft/Edge/Application/msedge.exe"
BASHRC

# ── opencode config ────────────────────────────────────────────────────
echo "==> Applying opencode config..."
cp "$TMP_CONFIG" "$CONFIG_PATH"

# ── Cleanup ────────────────────────────────────────────────────────────────────
echo "==> Cleaning up..."
apt-get clean
apt_lists_dir="$(resolve_path /var/lib/apt/lists)"
if [[ ! -d "$apt_lists_dir" ]]; then
  echo "ERROR: Expected apt lists directory does not exist: $apt_lists_dir" >&2
  exit 1
fi
rm -rf "${apt_lists_dir:?}/"*

rm -f "$TMP_INSTALL_SH" "$TMP_CONFIG"

echo ""
echo "Bootstrap complete."
echo "Versions installed:"
gh --version | head -1
podman --version
"$OPENCODE_BIN" --version
