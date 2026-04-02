#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "build-base.ps1 exists" {
    [ -f "$PROJECT_ROOT/build-base.ps1" ]
}

@test "new-project.ps1 exists" {
    [ -f "$PROJECT_ROOT/new-project.ps1" ]
}

@test "bootstrap/install.sh exists" {
    [ -f "$PROJECT_ROOT/bootstrap/install.sh" ]
}

@test "bootstrap/install.sh is executable" {
    [ -x "$PROJECT_ROOT/bootstrap/install.sh" ]
}

@test "config/opencode.json exists" {
    [ -f "$PROJECT_ROOT/config/opencode.json" ]
}

@test "README.md exists" {
    [ -f "$PROJECT_ROOT/README.md" ]
}

@test "LICENSE exists" {
    [ -f "$PROJECT_ROOT/LICENSE" ]
}

@test "no .env files are tracked" {
    cd "$PROJECT_ROOT"
    run git ls-files '*.env' '.env*'
    [ -z "$output" ]
}

@test "no credential files are tracked" {
    cd "$PROJECT_ROOT"
    run git ls-files '*credentials*' '*secret*' '*.pem' '*.key'
    [ -z "$output" ]
}
