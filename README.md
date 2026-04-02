# opencode-wsl

[![CI](https://github.com/Frank-Reichenbach/opencode-wsl/actions/workflows/ci.yml/badge.svg)](https://github.com/Frank-Reichenbach/opencode-wsl/actions/workflows/ci.yml)

A convenience setup for using [opencode](https://opencode.ai) in isolated WSL2 environments — one clean instance per project, ready in seconds.

---

## Philosophy

- **One project, one environment.** Each project runs in its own WSL2 instance. No cross-project pollution of tools, history, or credentials.
- **Pre-baked base image.** Tools are installed once into a base image and exported as a tarball. Creating a new project is just a fast import — no downloads, no waiting.
- **Per-instance credentials.** Each instance logs into its AI provider independently. Credentials are fully isolated.

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
  opencode auth login   ← authenticate with your AI provider (once per instance)
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
├── config/
│   └── opencode.json      ← opencode configuration
├── tests/
│   ├── static/            ← ShellCheck + PSScriptAnalyzer
│   ├── validation/        ← file structure + config checks
│   ├── unit/              ← install.sh, build-base, new-project
│   └── integration/       ← end-to-end WSL tests (Windows only)
└── .github/
    └── workflows/
        └── ci.yml         ← GitHub Actions CI
```

---

## Prerequisites

- **Windows 11 (x64)** with WSL2 enabled
- **VS Code** with the [WSL Remote extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl) (optional but recommended)

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
git clone https://github.com/Frank-Reichenbach/opencode-wsl
cd opencode-wsl
```

### 3. Build the base image

```powershell
.\build-base.ps1
```

This downloads Ubuntu 24.04 from Canonical, installs all tools via `bootstrap/install.sh`, exports the result to `C:\wsl\base\opencode-base.tar.gz`, and removes the temporary builder instance. Takes several minutes — done once.

> To store the image elsewhere: `.\build-base.ps1 -BaseImage C:\elsewhere\opencode-base.tar.gz`
> If you use a custom path, pass it when creating projects:
> `.\new-project.ps1 my-api -BaseImage C:\elsewhere\opencode-base.tar.gz`

---

## Creating a New Project

```powershell
.\new-project.ps1 my-project-name
# or just: .\new-project.ps1   (will prompt for the name)
```

This imports a fresh instance from the pre-baked base. No network access needed, completes in seconds. The instance is named `ubuntu-<name>` and stored at `C:\wsl\<name>\`.

> To store instances elsewhere: `.\new-project.ps1 my-api -ProjectDir C:\elsewhere`

### Connect

```powershell
wsl -d ubuntu-my-project-name
```

Or in VS Code: `Ctrl+Shift+P` → `Remote-WSL: Connect to WSL using Distro...` → select the instance. VS Code installs its server component automatically on first connect.

### First-time login (once per instance)

```bash
opencode auth login
```

For browser-based providers (ChatGPT Plus, GitHub Copilot, etc.) this opens your Windows browser to complete OAuth. For API-key providers (Anthropic, OpenAI API, etc.) it prompts for your key in the terminal. The credential is stored inside the instance and reused automatically from then on.

> `opencode auth login` authenticates to your **AI provider** — not to an opencode.ai cloud account. No cloud account is needed or configured.

---

## What's Installed in Each Instance

| Tool | Purpose | Install method |
|------|---------|----------------|
| git | Version control | apt |
| curl, unzip, wget | Download utilities | apt |
| xdg-utils | Browser integration for OAuth from WSL | apt |
| gh | GitHub CLI | official deb repo |
| podman + podman-docker | Container engine; podman-docker provides `/usr/bin/docker` symlink | apt |
| opencode | AI coding agent | official curl installer |

**Runtime user:** Instances run as `root` by default. This is intentional — each instance is an isolated, disposable, single-user environment with reduced risk compared to a shared system. Note that root in WSL can still access mounted Windows files under `/mnt/c` and bind network ports.

**Shell configuration (in `.bashrc`):**
- `COLORTERM=truecolor` — true color support in the terminal
- `BROWSER=/mnt/c/Progra~2/Microsoft/Edge/Application/msedge.exe` — routes browser OAuth to Edge on Windows

---

## opencode Configuration

`config/opencode.json` is applied during bootstrap and baked into the base image as the default global config at `~/.config/opencode/opencode.json`:

```json
{
  "snapshot": false,
  "share": "disabled",
  "experimental": {
    "openTelemetry": false
  }
}
```

| Setting | Value | Why |
|---------|-------|-----|
| `snapshot` | `false` | Disables git-based filesystem snapshots (7-day local retention by default). Off for a leaner, more predictable environment. |
| `share` | `"disabled"` | Sets the default global policy to disable session uploads to opencode's cloud backend. Other modes: `"manual"`, `"auto"`. Repo-local config, `OPENCODE_CONFIG`, or inline overrides can still change it inside an instance. |
| `experimental.openTelemetry` | `false` | Disables telemetry. Off by default upstream; made explicit here. |

This repo bakes in opinionated defaults, but opencode still honors repo-local config files, `OPENCODE_CONFIG`, and explicit runtime overrides inside an instance.

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
Run `build-base.ps1` again. It reuses the cached Ubuntu rootfs if present after verifying it against Canonical's current published checksum, re-runs `bootstrap/install.sh`, and overwrites the base image. Existing project instances are unaffected; new projects created after the rebuild will use the updated base. Delete `ubuntu-24.04.tar.gz` from the base image directory (`C:\wsl\base\` by default) if you want to force a fresh download immediately. Rebuilds intentionally track Canonical's current Ubuntu 24.04 WSL rootfs and the latest opencode installer, so results can change over time.

```powershell
.\build-base.ps1
```

---

## FAQ

**Do I need an opencode.ai cloud account?**

No. `opencode auth login` authenticates to your AI provider, not to an opencode.ai account. The cloud account (`opencode.ai/auth`) is for opencode's own subscription tier — it is not used here, and this repo sets `share: "disabled"` in the baked-in global config by default. Repo-local config files, `OPENCODE_CONFIG`, or explicit overrides can still change that behavior inside an instance.

**Edge is not at that path / I use a different browser.**

Override the `BROWSER` variable in the instance's `~/.bashrc`:
```bash
# Chrome
export BROWSER="/mnt/c/Progra~1/Google/Chrome/Application/chrome.exe"
# Edge (alternative path, e.g. 64-bit install)
export BROWSER="/mnt/c/Progra~1/Microsoft/Edge/Application/msedge.exe"
```

**VS Code doesn't find my instance automatically.**

Press `Ctrl+Shift+P`, type `Remote-WSL: Connect to WSL using Distro...`, and select the instance. VS Code installs its server component on first connect — no manual WSL-side setup needed.

---

## Development

### Running tests locally

[See Running Tests in CONTRIBUTING.md](CONTRIBUTING.md#running-tests)

### CI

GitHub Actions runs on pushes to `master` and on pull requests. Both trigger the full test suite including integration tests on a Windows + WSL runner.

---

## License

The scripts, configuration, and documentation in this repository are released
under the **MIT License** — see [LICENSE](LICENSE) for the full text.

This repository does not bundle any third-party software. Tools installed by
the scripts are downloaded from their official sources at build time.
For attribution and license details of those tools, see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
