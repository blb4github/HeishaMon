#!/usr/bin/env bash
# Verify that compact 4-byte bytecode accepts valid forward jumps and
# rejects offsets that cannot be represented by its uint8_t operand.
# The real Rules engine is used by the host-side harness.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$DIR/../harness/harness"
"$DIR/../harness/build.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

generate_rules() {
    local kind="$1" count="$2" target="$3" i
    {
        printf 'on System#Boot then\n'
        printf '    #guard = 0;\n    #counter = 0;\n'
        case "$kind" in
            then)
                printf '    if #guard == 1 then\n'
                ;;
            else)
                printf '    if #guard == 1 then\n'
                printf '        #counter = #counter + 1;\n'
                printf '    else\n'
                ;;
            elseif)
                printf '    if #guard == 1 then\n'
                printf '        #counter = #counter + 1;\n'
                printf '    elseif #guard == 2 then\n'
                ;;
            *)
                printf 'invalid test kind: %s\n' "$kind" >&2
                return 1
                ;;
        esac
        for ((i=0; i<count; i++)); do
            printf '        #counter = #counter + 1;\n'
        done
        printf '    end\n'
        printf '    @SetQuietMode = 1;\n'
        printf 'end\n'
    } > "$target"
}

printf 'boot\nexpectcmd SetQuietMode 1\nexpectnone\n' > "$TMP/pass.scenario"
for kind in then else elseif; do
    generate_rules "$kind" 8 "$TMP/$kind-valid.rules"
    if ! "$HARNESS" "$TMP/$kind-valid.rules" "$TMP/pass.scenario" > "$TMP/$kind-valid.log" 2>&1; then
        echo "FAIL: valid $kind branch must compile, skip safely and continue"
        tail -40 "$TMP/$kind-valid.log"
        exit 1
    fi
    echo "PASS: valid $kind branch compiled and executed"

    generate_rules "$kind" 140 "$TMP/$kind-too-long.rules"
    if HARNESS_VERBOSE=1 "$HARNESS" "$TMP/$kind-too-long.rules" parse > "$TMP/$kind-too-long.log" 2>&1; then
        echo "FAIL: oversized $kind branch was silently accepted"
        exit 1
    fi
    if ! grep -q 'PARSE FAILED' "$TMP/$kind-too-long.log" ||
       ! grep -q 'conditional jump of .* exceeds 255' "$TMP/$kind-too-long.log"; then
        echo "FAIL: oversized $kind branch rejected without clear jump error"
        tail -40 "$TMP/$kind-too-long.log"
        exit 1
    fi
    echo "PASS: oversized $kind branch rejected before truncated bytecode was accepted"
done
