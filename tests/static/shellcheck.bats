#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "bootstrap/install.sh passes ShellCheck" {
    run shellcheck "$PROJECT_ROOT/bootstrap/install.sh"
    echo "$output"
    [ "$status" -eq 0 ]
}
