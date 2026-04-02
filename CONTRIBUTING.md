# Contributing

## Prerequisites

- **Windows 11 (x64)** with WSL2 enabled
- **PowerShell 7** (`winget install Microsoft.PowerShell`)
- **ShellCheck** ([install](https://github.com/koalaman/shellcheck#installing))
- **bats-core** ([install](https://bats-core.readthedocs.io/en/stable/installation.html))
- **jq** ([download](https://jqlang.github.io/jq/download/))
- **Pester** and **PSScriptAnalyzer** PowerShell modules:
  ```powershell
  Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck
  Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
  ```

## Running Tests

**All bash tests** (static analysis, validation, unit):
```bash
# Requires: shellcheck, bats-core, jq
bats tests/static/ tests/validation/ tests/unit/
```

**All PowerShell tests** (static analysis, unit):
```powershell
# Requires: pwsh with Pester and PSScriptAnalyzer
Invoke-Pester tests/static/, tests/unit/
```

**Integration tests** (creates real WSL instances — slow):
```powershell
# Requires: pwsh with Pester and WSL2 is installed and configured
Invoke-Pester tests/integration/ -Output Detailed
```

All tests must pass locally before opening a PR.

## Submitting Changes

1. Fork the repo and create a branch from `master`.
2. Make your changes. Add or update tests as needed.
3. Run the full test suite locally.
4. Open a PR — the template will guide you.
