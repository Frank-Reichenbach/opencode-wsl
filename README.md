# opencode-wsl

A reproducible, privacy-first setup for using [opencode](https://opencode.ai) in isolated WSL2 environments — one clean instance per project, ready in seconds.

---

## Philosophy

- **One project, one environment.** Each project runs in its own WSL2 instance. No cross-project pollution of tools, history, or credentials.
- **Pre-baked base image.** Tools are installed once into a base image and exported as a tarball. Creating a new project is just a fast import — no downloads, no waiting.
- **Privacy by default.** opencode is configured to disable filesystem snapshots, session sharing, and telemetry. No opencode.ai cloud account required.
- **Per-instance credentials.** Each instance logs into its AI provider (Claude, OpenAI) independently via browser OAuth. Credentials are fully isolated.

---

## How It Works

```
Phase 1 — Build the base image once
────────────────────────────────────────────────────────────
build-base.ps1
  ↓ downloads Ubuntu 24.04 rootfs (Canonical)
  ↓ imports into temporary builder instance
  ↓ runs bootstrap/install.sh  (installs all tools + config)
  ↓ exports → C:\wsl\base\opencode-base.tar.gz
  ↓ cleans up builder instance

Phase 2 — Create a new project (~5 seconds, no network)
────────────────────────────────────────────────────────────
new-project.ps1 my-api
  ↓ wsl --import ubuntu-my-api  ←  opencode-base.tar.gz  →  C:\wsl\my-api\
  ↓ done

First use inside the instance:
  opencode auth login   ← browser OAuth for Claude / OpenAI (once per instance)
  opencode              ← start coding
```

---

## Repo Structure

```
opencode-wsl/
├── README.md              ← this file
├── build-base.ps1         ← one-time base image builder
├── new-project.ps1        ← creates a new project instance
├── bootstrap/
│   └── install.sh         ← runs inside the builder, NOT per project
└── config/
    └── opencode.json      ← opencode privacy configuration
```

---

## Prerequisites

- **Windows 11** with WSL2 enabled
- **VS Code** with the [WSL Remote extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl) (optional but recommended)
- A subscription to a **supported AI provider** (e.g. Claude Pro, OpenAI Plus)

---

## One-Time Setup

### 1. Enable WSL2

```powershell
wsl --install
# Restart if prompted
wsl --set-default-version 2
```

### 2. Clone this repo

```powershell
git clone https://github.com/<your-username>/opencode-wsl
cd opencode-wsl
```

### 3. Build the base image

```powershell
.\build-base.ps1
```

This downloads Ubuntu 24.04 from Canonical, installs all tools via `bootstrap/install.sh`, exports the result to `C:\wsl\base\opencode-base.tar.gz`, and removes the temporary builder instance. Takes several minutes — done once.

> To store files elsewhere: `.\build-base.ps1 -BaseDir D:\wsl\base`

---

## Creating a New Project

```powershell
.\new-project.ps1 my-project-name
# or just: .\new-project.ps1   (will prompt for the name)
```

This imports a fresh instance from the pre-baked base. No network access needed, completes in seconds. The instance is named `ubuntu-<name>` and stored at `C:\wsl\<name>\`.

### Connect

```powershell
wsl -d ubuntu-my-project-name
```

Or in VS Code: `Ctrl+Shift+P` → `Remote-WSL: Connect to WSL using Distro...` → select the instance. VS Code installs its server component automatically on first connect.

### First-time login (once per instance)

```bash
opencode auth login
```

This opens your Windows browser for OAuth. Choose your provider (Claude, OpenAI, GitHub Copilot, etc.) and complete the login. The credential is stored inside the instance and reused automatically from then on.

> `opencode auth login` authenticates to your **AI provider** (Claude, OpenAI, etc.) — not to an opencode.ai cloud account. No cloud account is needed or configured.

---

## What's Installed in Each Instance

| Tool | Purpose | Install method |
|------|---------|----------------|
| git | Version control | apt |
| curl, unzip, wget | Download utilities | apt |
| xdg-utils | Browser integration for OAuth from WSL | apt |
| gh | GitHub CLI | official deb repo |
| podman + podman-docker | Container engine; podman-docker provides `/usr/bin/docker` symlink | apt |
| Node.js LTS | Required by opencode | NodeSource (system-wide) |
| opencode | AI coding agent | official curl installer |

**Shell configuration (in `.bashrc`):**
- `COLORTERM=truecolor` — true color support in the terminal
- `BROWSER=/mnt/c/Progra~2/Microsoft/Edge/Application/msedge.exe` — routes browser OAuth to Edge on Windows

**Not installed:** nvm (Node is system-wide via NodeSource), Docker (Podman + podman-docker is the preferred alternative), language-specific runtimes (install per project as needed).

---

## opencode Configuration

`config/opencode.json` is applied during bootstrap and baked into the base image at `~/.config/opencode/config.json`:

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
| `snapshot` | `false` | Disables git-based filesystem snapshots (7-day local retention by default). Off for a leaner, more predictable environment. |
| `autoshare` | `false` | Prevents session content from being uploaded to opencode's cloud backend. Sharing is opt-in — this keeps it off unless you explicitly enable it. |
| `experimental.openTelemetry` | `false` | Disables telemetry. Off by default upstream; made explicit here. |

---

## Project Lifecycle

### Create
```powershell
.\new-project.ps1 my-project-name
```

### Work
```powershell
wsl -d ubuntu-my-project-name
# or connect via VS Code WSL Remote
```

### Pause
WSL instances pause automatically when not in use. No action needed.

### Archive
```powershell
wsl --export ubuntu-my-project-name "C:\wsl\archive\ubuntu-my-project-name.tar.gz"
wsl --unregister ubuntu-my-project-name
```

### Delete
```powershell
wsl --unregister ubuntu-my-project-name
Remove-Item -Recurse "C:\wsl\my-project-name"
```

### List all instances
```powershell
wsl --list --verbose
```

---

## Keeping Things Up to Date

### Updating opencode in an existing instance
```bash
opencode upgrade
```

### Rebuilding the base image
Run `build-base.ps1` again. It downloads a fresh Ubuntu rootfs, re-runs `bootstrap/install.sh`, and overwrites `opencode-base.tar.gz`. Existing project instances are unaffected; new projects created after the rebuild will use the updated base.

```powershell
.\build-base.ps1
```

---

## FAQ

**Do I need an opencode.ai cloud account?**
No. `opencode auth login` authenticates to your AI provider (Claude, OpenAI, etc.), not to an opencode.ai account. The cloud account (`opencode.ai/auth`) is for opencode's own subscription tier — it is not used here, and `autoshare: false` ensures no session data is uploaded.

**Do I need to re-login when my token expires?**
Yes, in the affected instance: `opencode auth login`. Since credentials are per-instance, other instances are unaffected.

**Can I use OpenAI, GitHub Copilot, or other providers?**
Yes. `opencode auth login` supports 75+ providers. Choose your provider during the OAuth flow.

**Edge is not at that path / I use a different browser.**
Override the `BROWSER` variable in the instance's `~/.bashrc`:
```bash
# Chrome
export BROWSER="/mnt/c/Progra~1/Google/Chrome/Application/chrome.exe"
# Edge (alternative path, e.g. 64-bit install)
export BROWSER="/mnt/c/Progra~1/Microsoft/Edge/Application/msedge.exe"
```

**Podman vs Docker — are they really compatible?**
For most workflows, yes. The `podman-docker` package installs a real `/usr/bin/docker` symlink to Podman, so both interactive use and tools that call `docker` as a subprocess work without any alias. Known limitations: tools that connect to the Docker daemon socket (`/var/run/docker.sock`) require `podman system service` to expose a compatible socket, and BuildKit-specific features are not supported. For compose files, use `podman compose` (built-in in Podman 4.x).

**What's the disk footprint per project?**
The base image is approximately 800 MB–1 GB. Your project code, dependencies, and container images add on top. Each instance is a separate WSL virtual disk.

**VS Code doesn't find my instance automatically.**
Press `Ctrl+Shift+P`, type `Remote-WSL: Connect to WSL using Distro...`, and select the instance. VS Code installs its server component on first connect — no manual WSL-side setup needed.

**Should I keep the base image updated?**
Periodically, yes. Running `.\build-base.ps1` every few months keeps the base packages current and reduces `apt upgrade` churn in new projects. Note that `build-base.ps1` re-downloads the Ubuntu rootfs tarball from Canonical each time, so the Ubuntu version itself (e.g. 24.04) does not change automatically — to move to a newer Ubuntu release you would need to update the download URL in `build-base.ps1` manually.

---

## License

The scripts, configuration, and documentation in this repository are released
under the **MIT License** — see [LICENSE](LICENSE) for the full text.

This repository does not bundle any third-party software. Tools installed by
the scripts are downloaded from their official sources at build time.
For attribution and license details of those tools, see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
