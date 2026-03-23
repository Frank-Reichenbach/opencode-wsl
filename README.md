# opencode-wsl

A reproducible, privacy-first setup for using [opencode](https://github.com/anomalyco/opencode) in isolated WSL2 environments — one clean environment per project.

---

## Philosophy

- **One project, one environment.** Each project runs in its own WSL2 instance, imported from a shared base image. No cross-project pollution of tools, history, or configuration.
- **Automated setup.** A single script creates and bootstraps a new environment from scratch.
- **Privacy by default.** opencode is configured to disable filesystem snapshots, session sharing, and telemetry. No opencode.ai account required.
- **Credentials stay on Windows.** Claude Pro (and other provider) OAuth tokens are stored once on the Windows host filesystem and shared read-only into each WSL instance via symlink. You do the OAuth once in a browser — no re-login per project.

---

## How It Works

```
Windows Host
├── C:\Users\<you>\.opencode\auth.json   ← OAuth token, managed once
├── C:\wsl\base\ubuntu-24.04.tar.gz      ← base image (imported per project)
└── C:\wsl\projects\
    ├── proj-my-api\                      ← WSL instance for project A
    ├── proj-frontend\                    ← WSL instance for project B
    └── proj-data-pipeline\              ← WSL instance for project C

Each WSL instance contains:
├── Ubuntu 24.04 LTS (minimal)
├── git, curl, unzip, gh, podman, Node.js, opencode
├── ~/.local/share/opencode/auth.json    ← symlink → Windows host token
└── ~/.config/opencode/config.json       ← privacy config (from this repo)
```

When you run `new-project.ps1 my-api`:
1. A new WSL2 instance is created from the base tarball
2. The bootstrap script runs inside it: installs tools, applies opencode config, sets up the auth symlink
3. You open VS Code → `code .` → done

---

## Prerequisites

- **Windows 11** with WSL2 enabled
- **VS Code** with the [WSL Remote extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl) installed
- **Claude Pro** (or OpenAI Plus/GitHub Copilot) subscription
- **PowerShell** (built-in on Windows 11)

---

## Repo Structure

```
opencode-wsl/
├── README.md                  ← this file
├── new-project.ps1            ← creates a new WSL instance for a project
├── bootstrap/
│   └── install.sh             ← runs inside a fresh WSL instance
├── config/
│   └── opencode.json          ← opencode privacy configuration
└── base/
    └── build-base.md          ← how to obtain / rebuild the base Ubuntu image
```

---

## One-Time Setup

These steps are done once on your Windows machine, not per project.

### 1. Enable WSL2

```powershell
wsl --install
# Restart if prompted
wsl --set-default-version 2
```

### 2. Get the Base Ubuntu Image

Download the official Ubuntu 24.04 minimal cloud image for WSL:

```powershell
# Create a directory for WSL base images and project instances
New-Item -ItemType Directory -Force -Path "C:\wsl\base"
New-Item -ItemType Directory -Force -Path "C:\wsl\projects"

# Download Ubuntu 24.04 minimal rootfs
# Official source: https://cloud-images.ubuntu.com/wsl/releases/24.04/current/
Invoke-WebRequest -Uri "https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz" `
  -OutFile "C:\wsl\base\ubuntu-24.04.tar.gz"
```

> **Alternative:** If you already have a running Ubuntu 24.04 WSL instance you're happy with, export it:
> `wsl --export Ubuntu-24.04 C:\wsl\base\ubuntu-24.04.tar.gz`

### 3. Set Up the Shared Auth Token Folder

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.opencode"
```

This folder will hold your Claude Pro (or other provider) OAuth token, shared across all project instances.

### 4. Do Your First Login

Create a temporary WSL instance, do the OAuth login, then copy the token to Windows:

```powershell
# Import a temporary instance for the initial login
wsl --import oc-auth-setup "C:\wsl\projects\oc-auth-setup" "C:\wsl\base\ubuntu-24.04.tar.gz"
wsl -d oc-auth-setup
```

Inside WSL, install opencode minimally and log in:

```bash
# Install Node.js (required by opencode)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install --lts

# Install opencode
curl -fsSL https://opencode.ai/install | bash
source ~/.bashrc

# Log in — this opens your Windows browser for OAuth
opencode auth login

# Copy the token to the Windows-accessible location
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
cp ~/.local/share/opencode/auth.json /mnt/c/Users/$WIN_USER/.opencode/auth.json
exit
```

Back on Windows, clean up the temporary instance:

```powershell
wsl --unregister oc-auth-setup
```

Your token is now at `C:\Users\<you>\.opencode\auth.json`. All future project instances will use it via symlink.

---

## Creating a New Project

```powershell
# Clone this repo first (once)
git clone https://github.com/<your-username>/opencode-wsl
cd opencode-wsl

# Create a new project environment
.\new-project.ps1 my-project-name
```

This will:
1. Import a fresh Ubuntu 24.04 instance named `proj-my-project-name`
2. Run `bootstrap/install.sh` inside it
3. Symlink the shared auth token
4. Apply the opencode privacy config

When it's done, connect with VS Code:

```powershell
wsl -d proj-my-project-name -- bash -c "code /home/$env:USERNAME/project"
# Or simply: open VS Code and use "Remote: Connect to WSL distro"
```

---

## What's Installed in Each Instance

| Tool | Purpose | Install method |
|------|---------|----------------|
| git | Version control | apt |
| curl, unzip, wget | Download utilities | apt |
| gh | GitHub CLI | official deb repo |
| podman | Container engine (Docker-compatible, rootless) | apt |
| nvm | Node.js version manager | curl install script |
| Node.js LTS | Required by opencode wrapper script | nvm |
| opencode | AI coding agent | official curl install script |

**Not installed:** Bun (development tool for opencode itself, not needed to run it), Docker (Podman is the preferred alternative — fully CLI-compatible via `alias docker=podman`).

**Per-project tools** (language runtimes, databases, etc.) are intentionally left out of the base image. Install them in each project instance as needed, or extend `bootstrap/install.sh` with a project-specific overlay.

---

## opencode Configuration

The file `config/opencode.json` is copied into each instance at `~/.config/opencode/config.json` during bootstrap:

```json
{
  "snapshot": false,
  "autoshare": false,
  "experimental": {
    "openTelemetry": false
  }
}
```

| Setting | Value | Why |
|---------|-------|-----|
| `snapshot` | `false` | Disables git-based filesystem snapshots of your project. Snapshots are stored locally (7-day retention by default) but capture your entire project tree. Off for a cleaner, more predictable environment. |
| `autoshare` | `false` | Prevents session content (messages + code diffs) from being uploaded to opencode's cloud backend. Sharing is opt-in — this just ensures it stays off unless you explicitly enable it. |
| `experimental.openTelemetry` | `false` | Disables telemetry. Already off by default upstream, but made explicit here. |
| **opencode.ai account** | *not configured* | The account/sync feature (for opencode's own cloud dashboard) is not used. Simply don't run `opencode auth login --account`. The Claude Pro OAuth login (for actually using Claude) is a separate flow and is configured via the shared auth token. |

---

## Project Lifecycle

### Create
```powershell
.\new-project.ps1 my-project-name
```

### Work
```powershell
wsl -d proj-my-project-name
# or connect via VS Code WSL Remote
```

### Pause
WSL instances automatically pause when not in use. No action needed.

### Archive
If you want to save the environment before deleting:
```powershell
wsl --export proj-my-project-name "C:\wsl\archive\proj-my-project-name.tar.gz"
wsl --unregister proj-my-project-name
```

### Delete
```powershell
wsl --unregister proj-my-project-name
# Optionally remove the instance directory
Remove-Item -Recurse "C:\wsl\projects\proj-my-project-name"
```

List all instances:
```powershell
wsl --list --verbose
```

---

## Keeping Things Up to Date

### Updating opencode
Since each instance is independent, updates happen per-instance:
```bash
curl -fsSL https://opencode.ai/install | bash
```

### Rebuilding the Base Image
When you want a fresh base image (e.g., newer Ubuntu point release, updated default tools), rebuild it:

1. Import a fresh Ubuntu tarball into a temporary instance
2. Run `bootstrap/install.sh` inside it
3. Export it as your new base: `wsl --export oc-builder C:\wsl\base\ubuntu-24.04-updated.tar.gz`
4. Update `new-project.ps1` to point to the new tarball
5. Unregister the builder instance

See `base/build-base.md` for detailed steps.

---

## FAQ & Caveats

**Do I need to re-login to Claude when my token expires?**
Yes, but it's straightforward. Run `opencode auth login` in any project instance. The token is stored at the shared Windows path, so all other instances automatically use the refreshed token via the symlink.

**Can I use OpenAI Plus or GitHub Copilot instead of Claude Pro?**
Yes. opencode supports "Log in with OpenAI" (ChatGPT Plus/Pro) and "Log in with GitHub" (Copilot). The same token-sharing approach applies — the auth.json holds whichever provider token you use.

**Podman vs Docker — are they really compatible?**
For most use cases, yes. Podman is rootless by default (better security), uses the same CLI syntax, and supports Docker Compose files via `podman-compose`. If a tool specifically requires the Docker daemon socket (`/var/run/docker.sock`), you may need `podman system service` or to fall back to Docker. For standard container workflows, Podman is a drop-in replacement.

**VS Code doesn't connect to my WSL instance automatically.**
Open VS Code on Windows, press `Ctrl+Shift+P`, type `Remote-WSL: Connect to WSL using Distro...`, and select your instance. VS Code will install its server component automatically on first connect.

**Is running `code .` inside WSL enough?**
Yes. `code .` from inside the WSL terminal opens VS Code on Windows and connects it to that WSL instance. The VS Code server is installed automatically on first run — no manual setup needed.

**What's the disk footprint per project?**
A fresh Ubuntu 24.04 instance with the base tooling is approximately 1.5–2 GB. Your project code, dependencies, and container images add on top of that.

**Should I keep the base tarball updated?**
Periodically, yes. An outdated base means `apt upgrade` has more to do on each new project. Rebuilding the base every few months keeps bootstrap time short and packages current.
