#!/usr/bin/env bash
# Host-side boundary regression for Rules VM named-variable references.
# Run from any directory: bash Examples/Rules/Variable-Slot-Limits/test_variable_slots.sh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$DIR/../harness/harness"
"$DIR/../harness/build.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Slots = 1 (System#Boot event) + N distinct # globals + 1 (@SetQuietMode).
# Validate both read/write of the last variable via an emitted command.
for slots in 127 128 200 255 256; do
    vars=$((slots - 2))
    {
        printf 'on System#Boot then\n'
        for ((i=0;i<vars;i++)); do
            printf '    #slot%03d = %d;\n' "$i" "$((i % 99))"
        done
        printf '    if #slot%03d == %d then\n' "$((vars-1))" "$(((vars-1) % 99))"
        printf '        @SetQuietMode = 2;\n'
        printf '    end\nend\n'
    } > "$TMP/$slots.rules"
    printf 'boot\nexpectcmd SetQuietMode 2\nexpectnone\n' > "$TMP/$slots.scenario"
    if [ "$slots" -le 255 ]; then
        "$HARNESS" "$TMP/$slots.rules" "$TMP/$slots.scenario" > "$TMP/$slots.log" 2>&1 || {
            echo "FAIL: $slots slots must compile and execute"
            tail -25 "$TMP/$slots.log"
            echo "=== Verbose parser/VM diagnostic ==="
            HARNESS_VERBOSE=1 "$HARNESS" "$TMP/$slots.rules" "$TMP/$slots.scenario" 2>&1 | tail -65 || true
            exit 1
        }
        echo "PASS: $slots slots compile and execute"
    else
        if "$HARNESS" "$TMP/$slots.rules" parse > "$TMP/$slots.log" 2>&1; then
            echo "FAIL: 256 slots must be rejected"
            exit 1
        fi
        if ! grep -q 'PARSE FAILED' "$TMP/$slots.log"; then
            echo "FAIL: 256 slots rejected without harness parse-failure signal"
            tail -25 "$TMP/$slots.log"
            exit 1
        fi
        echo "PASS: 256 slots rejected safely"
    fi
done
