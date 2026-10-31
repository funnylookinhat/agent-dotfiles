#!/usr/bin/env bash
# Runs list-unresolved-threads.sh against a stubbed GraphQL response. Usage: tests/run-tests.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/list-unresolved-threads.sh"
export PATH="$here/bin:$PATH" GH_FIXTURE_DIR="$here/fixtures/mixed"
fail=0
check() { if jq -e "$2" <<<"$3" >/dev/null; then echo "  ok   $1"; else echo "  FAIL $1 :: $2"; jq -c . <<<"$3"; fail=1; fi; }
echo "default (self-replied threads dropped)"
out="$("$S" o/r#7 2>/tmp/lut-stderr)"
check count            'length == 3' "$out"
check dropped-T2       '[.[] | .threadId] | index("T2") == null' "$out"
check resolved-dropped '[.[] | .threadId] | index("T5") == null' "$out"
check T1-origin        '.[] | select(.threadId=="T1") | .origin=="moz-review" and .severity=="blocking" and .awaitingUs==true' "$out"
check T3-origin        '.[] | select(.threadId=="T3") | .origin=="reviewing-pr" and .severity==null and .awaitingUs==true and .lastIsOurs==false' "$out"
check T4-human         '.[] | select(.threadId=="T4") | .origin=="human" and .severity==null' "$out"
grep -q "skipped 1 unresolved" /tmp/lut-stderr && echo "  ok   stderr notice" || { echo "  FAIL stderr notice"; cat /tmp/lut-stderr; fail=1; }
echo "--all"
out="$("$S" --all o/r#7 2>/dev/null)"
check count            'length == 4' "$out"
check T2-ours          '.[] | select(.threadId=="T2") | .origin=="moz-review" and .severity=="pre-existing" and .lastIsOurs==true and .awaitingUs==false' "$out"
[[ $fail -eq 0 ]] && echo "all passed" || { echo "FAILURES"; exit 1; }
