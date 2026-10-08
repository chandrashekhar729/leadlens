#!/usr/bin/env bash
# Fast pattern scan for secrets, XSS, a11y and quality smells. No network, no build.
# Modes:
#   --hook            PreToolUse hook: read tool JSON on stdin, scan the content about
#                     to be written (Write.content / Edit.new_string), exit 2 on a secret.
#   --files a b c     scan the given files, print JSON findings to stdout.
#   --diff            read a unified diff on stdin, scan only the added lines, print JSON
#                     findings with the file and its line number after the change.
set -uo pipefail

MODE="files"; FILES=()
case "${1:-}" in
  --hook)  MODE="hook"; shift ;;
  --files) shift; FILES=("$@") ;;
  --diff)  MODE="diff"; shift ;;
  *) echo "usage: scan-patterns.sh --hook | --files <paths...> | --diff" >&2; exit 1 ;;
esac

# critical|category|label|regex   (PCRE, used with grep -P)
RULES=(
'yes|secret|Hardcoded credential|(?i)(api[_-]?key|secret|password|passwd|token|private[_-]?key)["'"'"']?\s*[:=]\s*["'"'"'][A-Za-z0-9/_+=.-]{16,}["'"'"']'
'yes|secret|Stripe-style live key|\bsk_live_[A-Za-z0-9]{10,}'
'yes|secret|AWS access key|\bAKIA[0-9A-Z]{16}\b'
'yes|secret|GitHub token|\bgh[pousr]_[A-Za-z0-9]{30,}'
'yes|secret|Private key block|-----BEGIN [A-Z ]*PRIVATE KEY-----'
'no|xss|Raw HTML injection|dangerouslySetInnerHTML|\.innerHTML\s*='
'no|xss|Dynamic code execution|\beval\(|new Function\('
'no|security|Disabled TLS verification|rejectUnauthorized\s*:\s*false|verify\s*=\s*False'
'no|security|target=_blank without rel|target=["'"'"']_blank["'"'"'](?![^>]*\brel=)'
'no|a11y|Image without alt|<img(?![^>]*\balt=)'
'no|a11y|Click handler on non-interactive element|<(div|span)\b[^>]*\bonClick'
'no|a11y|Positive tabIndex|tabIndex=\{?["'"'"']?[1-9]'
'no|quality|Debug statement left behind|console\.(log|debug)\(|^\s*debugger;?'
'no|quality|Suppressed type or lint error|@ts-ignore|@ts-nocheck|eslint-disable(?!-next-line\s+\S+\s+--)'
)

SKIP='(^|/)(node_modules|dist|build|coverage|\.next|\.git)/|\.min\.|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|\.snap$|\.(png|jpg|jpeg|gif|webp|svg|ico|woff2?|ttf|pdf)$'
GREP="grep -nP"

if [[ "$MODE" == "hook" ]]; then
  command -v jq >/dev/null 2>&1 || exit 0          # no jq: stay out of the way
  input=$(cat)
  f=$(jq -r '.tool_input.file_path // empty' <<< "$input")
  [[ -n "$f" ]] || exit 0
  [[ "$f" =~ $SKIP ]] && exit 0
  # Scan only the text being written, not the whole file: Write.content or Edit.new_string.
  text=$(jq -r '.tool_input.content // .tool_input.new_string // empty' <<< "$input")
  [[ -n "$text" ]] || exit 0
  for rule in "${RULES[@]}"; do
    IFS='|' read -r crit cat label regex <<< "$rule"
    [[ "$crit" == "yes" ]] || continue
    hits=$($GREP -e "$regex" <<< "$text" 2>/dev/null | head -3 || true)
    [[ -n "$hits" ]] || continue
    {
      echo "Blocked: ${label} about to be written to ${f}"
      sed 's/^/  /' <<< "$hits"
      echo "  Move the value to an environment variable or a secrets manager, then write the file again."
    } >&2
    exit 2
  done
  exit 0
fi

if [[ "$MODE" == "diff" ]]; then
  # Added lines as "file<TAB>new-line-number<TAB>text", tracking hunk headers.
  tsv=$(mktemp); txt=$(mktemp)
  awk '
    /^diff --git/ { file=""; inhunk=0; next }
    /^\+\+\+ /   { file=substr($0,5); sub(/^b\//,"",file); if (file=="/dev/null") file=""; next }
    /^@@/        { s=$0; sub(/^@@ -[0-9,]+ \+/,"",s); sub(/[ ,].*/,"",s); ln=s+0; inhunk=1; next }
    inhunk && /^\+/ { if (file!="") print file "\t" ln "\t" substr($0,2); ln++; next }
    inhunk && /^ /   { ln++; next }
  ' > "$tsv"
  cut -f3- "$tsv" > "$txt"
  findings="[]"; critical=0
  for rule in "${RULES[@]}"; do
    IFS='|' read -r crit cat label regex <<< "$rule"
    rows=$($GREP -e "$regex" "$txt" 2>/dev/null | cut -d: -f1 | head -20 || true)
    [[ -n "$rows" ]] || continue
    for r in $rows; do
      IFS=$'\t' read -r f ln _ < <(sed -n "${r}p" "$tsv")
      [[ "$f" =~ $SKIP ]] && continue
      [[ "$crit" == "yes" ]] && critical=1
      findings=$(jq -c --arg f "$f" --arg ln "$ln" --arg c "$cat" --arg l "$label" --arg crit "$crit" \
        '. + [{file:$f, line:($ln|tonumber? // null), category:$c, label:$l, critical:($crit=="yes")}]' <<< "$findings")
    done
  done
  rm -f "$tsv" "$txt"
  jq -n --argjson f "$findings" --argjson c "$critical" \
    '{critical_found: ($c==1), count: ($f|length), findings: $f}'
  exit 0
fi

findings="[]"; critical=0
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ $SKIP ]] && continue
  for rule in "${RULES[@]}"; do
    IFS='|' read -r crit cat label regex <<< "$rule"
    hits=$($GREP -e "$regex" "$f" 2>/dev/null | head -5 || true)
    [[ -n "$hits" ]] || continue
    [[ "$crit" == "yes" ]] && critical=1
    while IFS= read -r line; do
      ln="${line%%:*}"
      findings=$(jq -c --arg f "$f" --arg ln "$ln" --arg c "$cat" --arg l "$label" --arg crit "$crit" \
        '. + [{file:$f, line:($ln|tonumber? // null), category:$c, label:$l, critical:($crit=="yes")}]' <<< "$findings")
    done <<< "$hits"
  done
done
jq -n --argjson f "$findings" --argjson c "$critical" \
  '{critical_found: ($c==1), count: ($f|length), findings: $f}'
