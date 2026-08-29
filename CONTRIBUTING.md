# Contributing

## Prerequisites

- **Windows 10 version 2004+ (Build 19041+) or Windows 11**, on x64 hardware, with WSL2 enabled
- For the default `.tar.gz` base-image workflow, use a recent WSL release that supports `wsl --export --format`. Older WSL builds can still be tested with plain `.tar` image paths.
- **ShellCheck** ([install](https://github.com/koalaman/shellcheck#installing))
- **bats-core** ([install](https://bats-core.readthedocs.io/en/stable/installation.html))
- **jq** ([download](https://jqlang.github.io/jq/download/))
- **Pester** and **PSScriptAnalyzer** PowerShell modules:
  ```powershell
  Install-Module -Name Pester -RequiredVersion 6.1.0 -Force -Scope CurrentUser -SkipPublisherCheck
  Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
  ```

  The CI workflow pins Pester `6.1.0` so local runs and GitHub Actions use the same major/minor behavior.

## Running Tests

**All bash tests** (static analysis, validation, unit):
```bash
# Requires: shellcheck, bats-core, jq
bats tests/static/ tests/validation/ tests/unit/
```

**All PowerShell tests** (static analysis, unit):
```powershell
# Requires: Pester and PSScriptAnalyzer modules
Invoke-Pester tests/static/, tests/unit/
```

**Integration tests** (creates real WSL instances — slow):
```powershell
# Requires: Pester module and WSL2 installed and configured
Invoke-Pester tests/integration/ -Output Detailed
```

All tests must pass locally before opening a PR.

## Coding Standards

**PowerShell scripts must be ASCII-only.** Non-ASCII characters (box-drawing, em dashes, arrows, etc.) cause parse errors on Windows PowerShell 5.1 when the file is UTF-8 without BOM. CI enforces this via the static test suite. Use ASCII equivalents: `--` for em dashes, `->` for arrows, `-` for horizontal rules.

**Line endings are part of the repo policy.** `.gitattributes` and `.editorconfig` define `LF` for text files by default and `CRLF` for `.ps1` files. The Windows static test suite validates the checked-out working-tree endings, so avoid overriding line endings globally in your editor.

## Submitting Changes

1. Fork the repo and create a branch from `master`.
2. Make your changes. Add or update tests as needed.
3. Run the full test suite locally.
4. Open a PR — the template will guide you.
