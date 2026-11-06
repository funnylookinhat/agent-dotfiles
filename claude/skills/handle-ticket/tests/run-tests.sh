#!/usr/bin/env bash
# Runs the bundled scripts against stubs and fixtures. Usage: tests/run-tests.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/review-status.sh"
export PATH="$here/bin:$PATH"
fail=0
check() { # <name> <jq-expr that must be true> <json>
  if jq -e "$2" <<<"$3" >/dev/null; then echo "  ok   $1"; else echo "  FAIL $1 :: $2"; echo "$3" | jq -c . ; fail=1; fi
}
echo "moz-inline (newest marker is a review with 3 attached findings; older legacy marker present)"
out="$(GH_FIXTURE_DIR="$here/fixtures/moz-inline" "$S" o/r#7)"
check engine        '.engine == "moz-wide:review-pr"' "$out"
check reviewedSha   '.reviewedSha == "bbbb000000000000000000000000000000000002"' "$out"
check upToDate      '.upToDate == true' "$out"
check inline        '.inline == 3' "$out"
check severities    '.blocking == 1 and .nit == 1 and .preExisting == 1' "$out"
check heading       '.heading == {blocking:1,nit:1,preExisting:1}' "$out"
check handling      '.handlingRepliesSince == true' "$out"
echo "moz-fallback (marker on an issue comment, standalone inline comments, one stale)"
out="$(GH_FIXTURE_DIR="$here/fixtures/moz-fallback" "$S" o/r#7)"
check engine        '.engine == "moz-wide:review-pr"' "$out"
check inline        '.inline == 2' "$out"
check severities    '.blocking == 2 and .nit == 0' "$out"
check handling      '.handlingRepliesSince == false' "$out"
echo "resolve-ticket-repo.sh"
bash "$here/test-resolve-ticket-repo.sh" || fail=1
echo "stop-worktree-services.sh"
bash "$here/test-stop-worktree-services.sh" || fail=1
[[ $fail -eq 0 ]] && echo "all passed" || { echo "FAILURES"; exit 1; }
