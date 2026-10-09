#!/usr/bin/env bash
# Scoped checks on changed files, as JSON. --build also runs the build script; --fast skips typecheck, tests and build.
set -uo pipefail

BASE=""; FAST=0; BUILD=0
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --fast) FAST=1; shift ;;
    --build) BUILD=1; shift ;;
    *) echo "usage: quick-checks.sh [--base <ref>] [--fast] [--build]" >&2; exit 1 ;;
  esac
done
cd "$ROOT" || exit 1
command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

if [[ -n "$BASE" ]]; then
  mapfile -t ALL < <(git diff --name-only --diff-filter=ACMR "$BASE"...HEAD 2>/dev/null || git diff --name-only --diff-filter=ACMR "$BASE")
else
  mapfile -t ALL < <({ git diff --name-only --diff-filter=ACMR; git diff --cached --name-only --diff-filter=ACMR; git ls-files --others --exclude-standard; } | sort -u)
fi
CHANGED=()
for f in "${ALL[@]}"; do [[ "$f" =~ \.(ts|tsx|js|jsx|mjs|cjs|vue|svelte|css|scss|html|py|php)$ ]] && [[ -f "$f" ]] && CHANGED+=("$f"); done

if [[ ${#CHANGED[@]} -eq 0 ]]; then
  jq -n '{changed_files: [], checks: [], note: "no reviewable changes"}'; exit 0
fi

PM=npm; [[ -f pnpm-lock.yaml ]] && PM=pnpm; [[ -f yarn.lock ]] && PM=yarn
run() { # name timeout_s command...
  local name="$1" t="$2"; shift 2
  local out status start end
  start=$(date +%s)
  out=$(timeout "$t" "$@" 2>&1); status=$?
  end=$(date +%s)
  # A tool that is not installed is "skipped", never a failed check: exit 127 from the shell,
  # or npx --no-install refusing to run because the package is missing.
  local skipped=false
  if [[ $status -eq 127 ]] || grep -qE 'npx canceled due to missing packages|could not determine executable to run' <<< "$out"; then
    skipped=true
  fi
  jq -n --arg n "$name" --arg o "${out:0:4000}" --argjson s "$status" --argjson d "$((end-start))" --argjson k "$skipped" \
    '{check:$n, exit_code:$s, duration_s:$d, timed_out:($s==124), skipped:$k, output:$o}'
}
results="[]"
add() { results=$(jq -c --argjson r "$1" '. + [$r]' <<< "$results"); }

add "$(run patterns 10 bash "$HERE/scan-patterns.sh" --files "${CHANGED[@]}")"
if [[ -f package.json ]] && command -v npx >/dev/null 2>&1; then
  WEB=(); SCRIPT=(); STYLE=()
  for f in "${CHANGED[@]}"; do
    [[ "$f" =~ \.(ts|tsx|js|jsx|mjs|cjs|vue|svelte|css|scss|html)$ ]] && WEB+=("$f")
    [[ "$f" =~ \.(ts|tsx|js|jsx|mjs|cjs|vue|svelte)$ ]] && SCRIPT+=("$f")
    [[ "$f" =~ \.(css|scss)$ ]] && STYLE+=("$f")
  done
  [[ ${#WEB[@]} -gt 0 ]] && add "$(run prettier 30 npx --no-install prettier --check "${WEB[@]}")"
  [[ ${#SCRIPT[@]} -gt 0 ]] && add "$(run eslint 60 npx --no-install eslint --max-warnings 0 "${SCRIPT[@]}")"
  if [[ ${#STYLE[@]} -gt 0 ]]; then
    if ls .stylelintrc* stylelint.config.* >/dev/null 2>&1; then
      add "$(run stylelint 60 npx --no-install stylelint "${STYLE[@]}")"
    else
      add "$(jq -n '{check:"stylelint", exit_code:null, duration_s:0, timed_out:false, skipped:true, output:"no stylelint config in this project; style files were not linted"}')"
    fi
  fi
  if (( ! FAST )); then
    [[ -f tsconfig.json ]] && add "$(run typecheck 180 npx --no-install tsc --noEmit)"
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      add "$(run tests 300 "$PM" test)"
    fi
  fi
  if (( BUILD && ! FAST )); then
    if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
      add "$(run build 600 "$PM" run build)"
    else
      add "$(jq -n '{check:"build", exit_code:null, duration_s:0, timed_out:false, skipped:true, output:"no build script in package.json"}')"
    fi
  fi
fi

jq -n --argjson c "$(printf '%s\n' "${CHANGED[@]}" | jq -R . | jq -s .)" --argjson r "$results" \
  '{changed_files:$c, checks:$r}'
