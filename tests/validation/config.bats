#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/config/opencode.json"
}

@test "opencode.json is valid JSON" {
    run jq empty "$CONFIG"
    [ "$status" -eq 0 ]
}

@test "opencode.json is an object" {
    result="$(jq -r 'type' "$CONFIG" | tr -d '\r')"
    [ "$result" = "object" ]
}

@test "opencode.json has 'snapshot' set to false" {
    result="$(jq -r 'if (.snapshot | type) == "boolean" then .snapshot else "invalid" end' "$CONFIG" | tr -d '\r')"
    [ "$result" = "false" ]
}

@test "opencode.json has 'share' set to disabled" {
    result="$(jq -r '.share' "$CONFIG" | tr -d '\r')"
    [ "$result" = "disabled" ]
}

@test "opencode.json optional schema is a string when present" {
    result="$(jq -r 'if has("$schema") then .["$schema"] | type else "absent" end' "$CONFIG" | tr -d '\r')"
    [[ "$result" = "string" || "$result" = "absent" ]]
}

@test "opencode.json has an experimental object" {
    result="$(jq -r '.experimental | type' "$CONFIG" | tr -d '\r')"
    [ "$result" = "object" ]
}

@test "opencode.json has 'experimental.openTelemetry' set to false" {
    result="$(jq -r 'if (.experimental.openTelemetry | type) == "boolean" then .experimental.openTelemetry else "invalid" end' "$CONFIG" | tr -d '\r')"
    [ "$result" = "false" ]
}
