#!/usr/bin/env bash
# Exercises resolve-base-branch.sh against a throwaway origin + clone. Usage: tests/test-resolve-base-branch.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/resolve-base-branch.sh"
fail=0
check() { # <name> <jq-expr that must be true> <json>
  if jq -e "$2" <<<"$3" >/dev/null; then echo "  ok   $1"; else echo "  FAIL $1 :: $2"; echo "$3" | jq -c . ; fail=1; fi
}
expect_exit() { # <name> <expected-code> <actual-code>
  if [[ "$2" == "$3" ]]; then echo "  ok   $1 (exit $3)"; else echo "  FAIL $1 :: expected exit $2, got $3"; fail=1; fi
}

root="$(mktemp -d)"; root="$(cd "$root" && pwd -P)"
trap 'rm -rf "$root"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- an "upstream" with main + release/1.x, and a clone of it -------------------------
up="$root/upstream"; mkdir -p "$up"
git -C "$up" init -q -b main
echo one >"$up/f"; git -C "$up" add f; git -C "$up" commit -q -m one
git -C "$up" branch release/1.x
origin="$root/origin.git"; git clone -q --bare "$up" "$origin"
git -C "$origin" symbolic-ref HEAD refs/heads/main
clone="$root/clone"; git clone -q "$origin" "$clone"
git -C "$clone" checkout -q -b flh/other-feature
echo feat >"$clone/g"; git -C "$clone" add g; git -C "$clone" commit -q -m feat

# upstream moves on
echo two >"$up/f"; git -C "$up" commit -q -am two
git -C "$up" push -q "$origin" main
new_main="$(git -C "$up" rev-parse main)"

echo "default branch, local main not checked out and behind: fetched and fast-forwarded"
out="$("$S" --cwd "$clone")"; code=$?
expect_exit exit 0 "$code"
check status   '.status == "OK"' "$out"
check branch   '.branch == "main" and .source == "default"' "$out"
check sha      ".sha == \"$new_main\"" "$out"
check base     '.base == "main"' "$out"
check ff       '.localFastForwarded == true and .localInSync == true' "$out"
check localRef "\"$(git -C "$clone" rev-parse main)\" == \"$new_main\"" '{}'
check headKept "\"$(git -C "$clone" branch --show-current)\" == \"flh/other-feature\"" '{}'

echo "already in sync: nothing to fast-forward, base is still the branch name"
out="$("$S" --cwd "$clone")"
check ff       '.localFastForwarded == false and .localInSync == true and .base == "main"' "$out"

echo "--base names a branch on origin: used instead of the default"
out="$("$S" --cwd "$clone" --base release/1.x)"; code=$?
expect_exit exit 0 "$code"
check branch   '.branch == "release/1.x" and .source == "arg"' "$out"
check sha      ".sha == \"$(git -C "$up" rev-parse release/1.x)\"" "$out"
check base     '.base == "release/1.x"' "$out"
check localRef "\"$(git -C "$clone" rev-parse -q --verify refs/heads/release/1.x)\" == \"$(git -C "$up" rev-parse release/1.x)\"" '{}'

echo "--base with an origin/ prefix is normalised"
out="$("$S" --cwd "$clone" --base origin/release/1.x)"
check branch   '.branch == "release/1.x"' "$out"

echo "--base names a local-only branch: used as is"
git -C "$clone" branch local-only
out="$("$S" --cwd "$clone" --base local-only)"; code=$?
expect_exit exit 0 "$code"
check status   '.status == "OK" and .onOrigin == false' "$out"
check base     '.base == "local-only"' "$out"

echo "--base names nothing anywhere: NOT_FOUND"
out="$("$S" --cwd "$clone" --base nope/never || true)"; code=$("$S" --cwd "$clone" --base nope/never >/dev/null 2>&1; echo $?)
expect_exit exit 1 "$code"
check status   '.status == "NOT_FOUND"' "$out"

echo "local main checked out and clean, behind: fast-forwarded in place"
echo three >"$up/f"; git -C "$up" commit -q -am three; git -C "$up" push -q "$origin" main
new_main="$(git -C "$up" rev-parse main)"
git -C "$clone" checkout -q main
out="$("$S" --cwd "$clone")"
check ff       '.localFastForwarded == true and .localInSync == true and .base == "main"' "$out"
check localRef "\"$(git -C "$clone" rev-parse main)\" == \"$new_main\"" '{}'

echo "local main checked out but dirty: left alone, base falls back to the fetched sha"
echo four >"$up/f"; git -C "$up" commit -q -am four; git -C "$up" push -q "$origin" main
new_main="$(git -C "$up" rev-parse main)"
echo dirty >>"$clone/f"
out="$("$S" --cwd "$clone")"; code=$?
expect_exit exit 0 "$code"
check notFf    '.localFastForwarded == false and .localInSync == false' "$out"
check base     ".base == \"$new_main\" and .sha == \"$new_main\"" "$out"
check localOld "\"$(git -C "$clone" rev-parse main)\" != \"$new_main\"" '{}'
git -C "$clone" checkout -q -- f

echo "local main diverged from origin: left alone, base is the fetched sha"
echo mine >"$clone/h"; git -C "$clone" add h; git -C "$clone" commit -q -m mine
out="$("$S" --cwd "$clone")"
check notFf    '.localFastForwarded == false and .localInSync == false' "$out"
check base     ".base == \"$new_main\"" "$out"
git -C "$clone" reset -q --hard "origin/main"
git -C "$clone" checkout -q flh/other-feature

echo "no origin/HEAD recorded: default branch recovered from the remote"
git -C "$clone" remote set-head origin -d
out="$("$S" --cwd "$clone")"; code=$?
expect_exit exit 0 "$code"
check branch   '.branch == "main" and .source == "default"' "$out"

echo "run from inside a linked worktree: resolves against the shared repo"
wt="$root/wt"; git -C "$clone" worktree add -q "$wt" -b flh/in-worktree
out="$("$S" --cwd "$wt")"
check branch   '.branch == "main" and .base == "main"' "$out"

echo "origin unreachable: FETCH_FAILED"
git -C "$clone" remote set-url origin "$root/does-not-exist.git"
out="$("$S" --cwd "$clone" || true)"; code=$("$S" --cwd "$clone" >/dev/null 2>&1; echo $?)
expect_exit exit 1 "$code"
check status   '.status == "FETCH_FAILED"' "$out"

echo "no origin remote: NO_ORIGIN"
git -C "$clone" remote remove origin
out="$("$S" --cwd "$clone" || true)"; code=$("$S" --cwd "$clone" >/dev/null 2>&1; echo $?)
expect_exit exit 1 "$code"
check status   '.status == "NO_ORIGIN"' "$out"

echo "not a repository: exit 2"
"$S" --cwd "$root" >/dev/null 2>&1; code=$?
expect_exit notRepo 2 "$code"

[[ $fail -eq 0 ]] && echo "resolve-base-branch: all passed" || { echo "resolve-base-branch: FAILURES"; exit 1; }
