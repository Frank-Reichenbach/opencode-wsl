#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$PROJECT_ROOT" || return 1
    REMEDY="correct the rule in .gitattributes, then run: git add --renormalize ."
}

# Guards the line-ending policy declared in .gitattributes.
#
# "git ls-files --eol" reports the recorded (i/) and checked-out (w/) endings.
# eolinfo is one of -text, none, lf, crlf or mixed. Output is tab-separated
# between the eol/attr columns and the path, so awk -F'\t' gives $1=columns,
# $2=path.

@test "no tracked file is stored with CRLF in the index" {
    run git ls-files --eol
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    offenders="$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /i\/(crlf|mixed)/')"
    echo "CRLF reached the index -- $REMEDY"
    echo "$offenders"
    [ -z "$offenders" ]
}

@test "only .ps1 files check out with CRLF" {
    run git ls-files --eol
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    offenders="$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /w\/(crlf|mixed)/ && $2 !~ /\.ps1$/')"
    echo "non-.ps1 file checks out as CRLF -- $REMEDY"
    echo "$offenders"
    [ -z "$offenders" ]
}

@test ".ps1 files check out with CRLF" {
    run git ls-files --eol -- '*.ps1'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    offenders="$(printf '%s\n' "$output" | awk -F'\t' '$1 !~ /w\/crlf/')"
    echo ".ps1 file does not check out as CRLF -- $REMEDY"
    echo "$offenders"
    [ -z "$offenders" ]
}

@test "no script is classified as binary" {
    run git ls-files --eol
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    offenders="$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /(i|w)\/-text/ && $2 ~ /\.(sh|bats|ps1)$/')"
    echo "script stored as binary, so git skips EOL normalization."
    echo "Usually a UTF-16 file from PowerShell redirection; re-save it as UTF-8."
    echo "$offenders"
    [ -z "$offenders" ]
}

@test ".gitattributes resolves the intended EOL for every managed type" {
    for probe in probe.sh=lf probe.bats=lf probe.md=lf probe.yml=lf \
                 probe.json=lf probe.ps1=crlf; do
        path="${probe%=*}"
        want="${probe#*=}"
        run git check-attr eol -- "$path"
        [ "$status" -eq 0 ]
        if [ "$output" != "$path: eol: $want" ]; then
            echo "expected '$path: eol: $want' but got '$output' -- $REMEDY"
            return 1
        fi
    done
}
