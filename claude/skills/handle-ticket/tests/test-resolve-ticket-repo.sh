#!/usr/bin/env bash
# Exercises resolve-ticket-repo.sh against a throwaway ~/source layout. Usage: tests/test-resolve-ticket-repo.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/resolve-ticket-repo.sh"
fail=0
check() { # <name> <jq-expr that must be true> <json>
  if jq -e "$2" <<<"$3" >/dev/null; then echo "  ok   $1"; else echo "  FAIL $1 :: $2"; echo "$3" | jq -c . ; fail=1; fi
}
expect_exit() { # <name> <expected-code> <actual-code>
  if [[ "$2" == "$3" ]]; then echo "  ok   $1 (exit $3)"; else echo "  FAIL $1 :: expected exit $2, got $3"; fail=1; fi
}

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export SOURCE_ROOT="$root/source"
mkrepo() { # <dir-under-github.com> <origin owner/repo>
  local d="$SOURCE_ROOT/github.com/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" remote add origin "git@github.com:$2.git"
}
mkrepo seomoz/app-api seomoz/app-api
mkrepo seomoz/nexus-alt seomoz/nexus          # dir name differs from repo name
mkrepo herdrdev/herdr herdrdev/herdr
mkdir -p "$SOURCE_ROOT/github.com/seomoz/not-a-repo"
outside="$root/outside"; mkdir -p "$outside"

t="$root/t.md"

echo "markdown heading, backtick form"
printf '# APDEV-1\n\n## Repository\n`seomoz/app-api` — https://github.com/seomoz/app-api\n\nAll work lands here.\n\n## Context\nstuff\n' >"$t"
out="$("$S" "$t")"; code=$?
expect_exit exit 0 "$code"
check status  '.status == "OK"' "$out"
check repo    '.repo == "seomoz/app-api" and .owner == "seomoz" and .name == "app-api"' "$out"
check path    ".path == \"$SOURCE_ROOT/github.com/seomoz/app-api\"" "$out"
check source  '.source == "ticket"' "$out"

echo "URL only, wiki-markup heading, .git suffix"
printf 'h2. Repository\nhttps://github.com/seomoz/app-api.git\n\nh2. Context\n' >"$t"
out="$("$S" "$t")"
check repo    '.repo == "seomoz/app-api"' "$out"

echo "bold heading, bare owner/repo"
printf '*Repository*\nseomoz/app-api\n\n*Context*\n' >"$t"
out="$("$S" "$t")"
check repo    '.repo == "seomoz/app-api"' "$out"

echo "epic lists several — primary (first) wins"
printf '## Repository\n- `seomoz/app-api` — https://github.com/seomoz/app-api — API side\n- `seomoz/app-pro-ui` — https://github.com/seomoz/app-pro-ui — UI side\n## Goal\n' >"$t"
out="$("$S" "$t")"
check repo    '.repo == "seomoz/app-api"' "$out"
check others  '.alsoListed == ["seomoz/app-pro-ui"]' "$out"

echo "checkout lives under a different directory name — found by origin"
printf '## Repository\n`seomoz/nexus` — https://github.com/seomoz/nexus\n' >"$t"
out="$("$S" "$t")"; code=$?
expect_exit exit 0 "$code"
check path    ".path == \"$SOURCE_ROOT/github.com/seomoz/nexus-alt\"" "$out"
check status  '.status == "OK"' "$out"

echo "a repository URL outside the Repository section is ignored"
printf '## Context\nSee https://github.com/seomoz/app-api/pull/9 for prior art.\n' >"$t"
out="$("$S" "$t" --cwd "$outside" || true)"
check status  '.status == "NOT_FOUND"' "$out"

echo "None — ticket changes no code"
printf '## Repository\nNone — this ticket does not change code\n## Context\n' >"$t"
out="$("$S" "$t" --cwd "$SOURCE_ROOT/github.com/seomoz/app-api" || true)"; code=$("$S" "$t" >/dev/null 2>&1; echo $?)
expect_exit exit 1 "$code"
check status  '.status == "NONE"' "$out"

echo "no section, --cwd inside a checkout → falls back to that checkout"
printf '## Context\nno repo here\n' >"$t"
out="$("$S" "$t" --cwd "$SOURCE_ROOT/github.com/herdrdev/herdr")"; code=$?
expect_exit exit 0 "$code"
check repo    '.repo == "herdrdev/herdr"' "$out"
check source  '.source == "cwd"' "$out"
check path    ".path == \"$SOURCE_ROOT/github.com/herdrdev/herdr\"" "$out"

echo "no section, --cwd outside any checkout → NOT_FOUND"
out="$("$S" "$t" --cwd "$outside" || true)"; code=$("$S" "$t" --cwd "$outside" >/dev/null 2>&1; echo $?)
expect_exit exit 1 "$code"
check status  '.status == "NOT_FOUND"' "$out"

echo "named but not cloned → NOT_CLONED with a clone hint"
printf '## Repository\n`seomoz/nowhere` — https://github.com/seomoz/nowhere\n' >"$t"
out="$("$S" "$t" || true)"; code=$("$S" "$t" >/dev/null 2>&1; echo $?)
expect_exit exit 1 "$code"
check status  '.status == "NOT_CLONED"' "$out"
check hint    '.reason | test("git clone git@github.com:seomoz/nowhere.git")' "$out"
check path    ".expectedPath == \"$SOURCE_ROOT/github.com/seomoz/nowhere\"" "$out"

echo "--repo overrides the ticket text"
out="$("$S" "$t" --repo herdrdev/herdr)"
check repo    '.repo == "herdrdev/herdr" and .source == "arg"' "$out"

echo "stdin works"
out="$(printf '## Repository\n`seomoz/app-api`\n' | "$S" -)"
check repo    '.repo == "seomoz/app-api"' "$out"

[[ $fail -eq 0 ]] && echo "all passed" || { echo "FAILURES"; exit 1; }
