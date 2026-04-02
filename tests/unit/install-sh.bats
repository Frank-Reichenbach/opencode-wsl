#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_ROOT="$(mktemp -d)"
    TEST_BIN="$TEST_ROOT/bin"
    export OPENCODE_WSL_ROOT_PREFIX="$TEST_ROOT"
    export MOCK_LOG="$TEST_ROOT/mock.log"
    export PATH="$TEST_BIN:$PATH"
    mkdir -p "$TEST_BIN" "$TEST_ROOT/tmp"
    : > "$TEST_ROOT/tmp/install.sh"
    cp "$PROJECT_ROOT/config/opencode.json" "$TEST_ROOT/tmp/opencode.json"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

create_mock() {
    local name="$1"
    cat > "$TEST_BIN/$name"
    chmod +x "$TEST_BIN/$name"
}

setup_bootstrap_mocks() {
    create_mock id <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
    echo 0
else
    /usr/bin/id "$@"
fi
EOF

    create_mock apt-get <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "update" ]]; then
    mkdir -p "$OPENCODE_WSL_ROOT_PREFIX/var/lib/apt/lists"
fi
printf 'apt-get %s\n' "$*" >> "$MOCK_LOG"
EOF

    create_mock dpkg <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--print-architecture" ]]; then
    echo amd64
else
    echo "unexpected dpkg invocation: $*" >&2
    exit 1
fi
EOF

    create_mock curl <<'CURLMOCK'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$MOCK_LOG"
case "$*" in
    *https://cli.github.com/packages/githubcli-archive-keyring.gpg*)
        printf 'keyring'
        ;;
    *https://opencode.ai/install*)
        cat <<'SCRIPT'
mkdir -p "$OPENCODE_WSL_ROOT_PREFIX/root/.opencode/bin"
cat > "$OPENCODE_WSL_ROOT_PREFIX/root/.opencode/bin/opencode" <<'EOF'
#!/usr/bin/env bash
echo "opencode 0.0.0-test"
EOF
chmod +x "$OPENCODE_WSL_ROOT_PREFIX/root/.opencode/bin/opencode"
SCRIPT
        ;;
    *)
        echo "unexpected curl invocation: $*" >&2
        exit 1
        ;;
esac
CURLMOCK

    create_mock gh <<'EOF'
#!/usr/bin/env bash
echo "gh version 0.0.0-test"
EOF

    create_mock podman <<'EOF'
#!/usr/bin/env bash
echo "podman version 0.0.0-test"
EOF
}

@test "install.sh rejects non-root execution" {
    run bash "$PROJECT_ROOT/bootstrap/install.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be run as root"* ]]
}

@test "install.sh uses strict error handling (set -euo pipefail)" {
    # Verify the script enables bash strict mode in the first 15 lines
    run bash -c "head -15 '$PROJECT_ROOT/bootstrap/install.sh' | grep -q 'set -euo pipefail'"
    [ "$status" -eq 0 ]
}

@test "install.sh bootstraps a fake root successfully" {
    setup_bootstrap_mocks

    run bash "$PROJECT_ROOT/bootstrap/install.sh"

    [ "$status" -eq 0 ]
    [ -x "$TEST_ROOT/root/.opencode/bin/opencode" ]
    [ -L "$TEST_ROOT/usr/local/bin/opencode" ]
    [ "$(readlink "$TEST_ROOT/usr/local/bin/opencode")" = "$TEST_ROOT/root/.opencode/bin/opencode" ]
    cmp -s "$PROJECT_ROOT/config/opencode.json" "$TEST_ROOT/root/.config/opencode/opencode.json"
    grep -Fq 'export COLORTERM=truecolor' "$TEST_ROOT/root/.bashrc"
    grep -Fq 'export BROWSER="/mnt/c/Progra~2/Microsoft/Edge/Application/msedge.exe"' "$TEST_ROOT/root/.bashrc"
    [ ! -e "$TEST_ROOT/etc/profile.d/local-bin.sh" ]
    [ ! -e "$TEST_ROOT/tmp/install.sh" ]
    [ ! -e "$TEST_ROOT/tmp/opencode.json" ]
    [[ "$output" == *"gh version 0.0.0-test"* ]]
    [[ "$output" == *"podman version 0.0.0-test"* ]]
    [[ "$output" == *"opencode 0.0.0-test"* ]]
}

@test "install.sh invokes the expected package and installer commands" {
    setup_bootstrap_mocks

    run bash "$PROJECT_ROOT/bootstrap/install.sh"

    [ "$status" -eq 0 ]
    [ "$(grep -Fc 'apt-get update -q' "$MOCK_LOG")" -eq 2 ]
    grep -Fq 'apt-get install -y --no-install-recommends git curl unzip wget xdg-utils ca-certificates gnupg lsb-release apt-transport-https' "$MOCK_LOG"
    grep -Fq 'apt-get install -y gh' "$MOCK_LOG"
    grep -Fq 'apt-get install -y podman podman-docker' "$MOCK_LOG"
    grep -Fq 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg' "$MOCK_LOG"
    grep -Fq 'curl -fsSL https://opencode.ai/install' "$MOCK_LOG"
}
