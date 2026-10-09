#!/usr/bin/env bash
# Inventory of every commit by one author across ALL refs (local branches, remote
# branches, tags, stash), never limited to the checked-out branch. Writes JSON plus
# one diff file per commit so the audit can read them by path. No checkout, no
# branch switch: everything is read with git log / git show on the object store.
#
#   collect-author-commits.sh --author <name|email> [--author <alias>]... \
#       [--since YYYY-MM-DD | --days N] [--default <branch>] [--repo <path|url>] \
#       [--stale-days 90] [--out <dir>]
#
# --days N (or Nd) is shorthand for --since <N days before today, at midnight>; the resolved date is
# recorded in inventory.json as "since" and the count as "window_days".
#
# A URL repo is mirror-cloned under <out>/mirror and read from there.
set -uo pipefail

AUTHORS=(); SINCE=""; DAYS=""; DEFAULT=""; REPO=""; STALE_DAYS=90; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) AUTHORS+=("$2"); shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --default) DEFAULT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ ${#AUTHORS[@]} -gt 0 ]] || { echo "usage: --author <name|email> [--author <alias>]... [--since YYYY-MM-DD | --days N] [--default <branch>] [--repo <path|url>] [--out <dir>]" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }
if [[ -n "$DAYS" ]]; then
  DAYS="${DAYS%d}"   # accept 7 or 7d
  [[ "$DAYS" =~ ^[0-9]+$ && "$DAYS" -gt 0 ]] || { echo "--days must be a positive whole number, got: $DAYS" >&2; exit 1; }
  [[ -z "$SINCE" ]] || { echo "give either --since or --days, not both" >&2; exit 1; }
  SINCE=$(date -d "$DAYS days ago" +%F 2>/dev/null || date -v-"${DAYS}"d +%F 2>/dev/null) \
    || { echo "could not compute the date $DAYS days ago with this system's date command" >&2; exit 1; }
fi
if [[ -n "$SINCE" && ! "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "--since must be YYYY-MM-DD, got: $SINCE" >&2; exit 1
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR="$(pwd)"
SLUG=$(printf '%s' "${AUTHORS[0]}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//')
[[ -n "$OUT" ]] || OUT=".claude/reports/data/audit-${SLUG}"
mkdir -p "$OUT/diffs" || exit 1
OUT="$(cd "$OUT" && pwd)"
COMMANDS=()
rec() { COMMANDS+=("$*"); }

# --- locate the repository -----------------------------------------------------
if [[ -z "$REPO" ]]; then
  REPO="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
fi
if [[ "$REPO" =~ ^(https?://|git@|ssh://|git://) ]]; then
  if [[ -d "$OUT/mirror" ]]; then
    rec "git --git-dir=$OUT/mirror remote update --prune"
    git --git-dir="$OUT/mirror" remote update --prune >/dev/null 2>&1
  else
    rec "git clone --mirror $REPO $OUT/mirror"
    git clone --mirror "$REPO" "$OUT/mirror" >/dev/null 2>&1 || { echo "clone failed: $REPO" >&2; exit 1; }
  fi
  REPO="$OUT/mirror"
fi
cd "$REPO" 2>/dev/null || { echo "not a directory: $REPO" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $REPO" >&2; exit 1; }
BARE=$(git rev-parse --is-bare-repository)
SHALLOW=$(git rev-parse --is-shallow-repository)

# --- fetch everything -------------------------------------------------------------
FETCHED=true; FETCH_ERROR=""
if [[ "$BARE" != "true" ]] && git remote | grep -q .; then
  rec "git fetch --all --prune --tags"
  if ! FETCH_ERROR=$(git fetch --all --prune --tags 2>&1 >/dev/null); then FETCHED=false; else FETCH_ERROR=""; fi
fi

# --- default branch ---------------------------------------------------------------
if [[ -z "$DEFAULT" ]]; then
  if [[ "$BARE" == "true" ]]; then
    DEFAULT=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)
  else
    DEFAULT=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  fi
fi
DEFAULT_REF=""
for cand in "$DEFAULT" "origin/$DEFAULT" origin/main origin/master origin/develop main master develop; do
  [[ -n "$cand" ]] && git rev-parse -q --verify "refs/remotes/$cand" >/dev/null 2>&1 && { DEFAULT_REF="refs/remotes/$cand"; break; }
  [[ -n "$cand" ]] && git rev-parse -q --verify "refs/heads/$cand" >/dev/null 2>&1 && { DEFAULT_REF="refs/heads/$cand"; break; }
done
DEFAULT_NAME="${DEFAULT_REF#refs/remotes/}"; DEFAULT_NAME="${DEFAULT_NAME#refs/heads/}"

# --- branches ----------------------------------------------------------------------
rec "git for-each-ref --format='%(refname:short)|%(committerdate:iso8601-strict)' refs/heads refs/remotes"
NOW=$(date +%s)
BRANCHES_ND=$(mktemp)
git for-each-ref --format='%(refname)|%(refname:short)|%(committerdate:iso8601-strict)|%(committerdate:unix)' refs/heads refs/remotes \
| while IFS='|' read -r full short date unix; do
    [[ "$short" == */HEAD ]] && continue
    merged=false
    [[ -n "$DEFAULT_REF" ]] && git merge-base --is-ancestor "$full" "$DEFAULT_REF" 2>/dev/null && merged=true
    stale=false; (( NOW - unix > STALE_DAYS * 86400 )) && stale=true
    remote=false; [[ "$full" == refs/remotes/* ]] && remote=true
    jq -nc --arg n "$short" --arg d "$date" --argjson r "$remote" --argjson m "$merged" --argjson s "$stale" \
      '{name:$n, remote:$r, last_commit:$d, merged_into_default:$m, stale:$s}'
  done > "$BRANCHES_ND"

# --- commits by author, then by committer ------------------------------------------
AUTHOR_ARGS=(); COMMITTER_ARGS=()
for a in "${AUTHORS[@]}"; do AUTHOR_ARGS+=("--author=$a"); COMMITTER_ARGS+=("--committer=$a"); done
SINCE_ARGS=(); SINCE_SHOW=""   # bare date would mean "that day, at the current time", so anchor to midnight
[[ -n "$SINCE" ]] && { SINCE_ARGS=("--since=$SINCE 00:00:00"); SINCE_SHOW="--since='$SINCE 00:00:00'"; }
FMT='%H|%h|%an|%ae|%cn|%ce|%aI|%s'
rec "git log --all -i --fixed-strings ${AUTHOR_ARGS[*]} $SINCE_SHOW --pretty=format:'$FMT'"
rec "git log --all -i --fixed-strings ${COMMITTER_ARGS[*]} $SINCE_SHOW --pretty=format:'$FMT'"
BY_AUTHOR=$(git log --all -i --fixed-strings "${AUTHOR_ARGS[@]}" "${SINCE_ARGS[@]}" --pretty=format:'%H')
BY_COMMITTER=$(git log --all -i --fixed-strings "${COMMITTER_ARGS[@]}" "${SINCE_ARGS[@]}" --pretty=format:'%H')
ALL_SHAS=$(printf '%s\n%s\n' "$BY_AUTHOR" "$BY_COMMITTER" | grep -v '^$' | sort -u)

rec "git branch -a --contains <sha> --format='%(refname:short)'"
rec "git merge-base --is-ancestor <sha> $DEFAULT_NAME"
rec "git show --format= --numstat <sha>  /  git show <sha> > diffs/<sha>.diff"
COMMITS_ND=$(mktemp); UNREADABLE_ND=$(mktemp)
for sha in $ALL_SHAS; do
  meta=$(git log -1 --pretty=format:"$FMT" "$sha" 2>/dev/null) || { jq -nc --arg s "$sha" '{sha:$s, reason:"git log -1 failed"}' >> "$UNREADABLE_ND"; continue; }
  IFS='|' read -r full short an ae cn ce date subject <<< "$meta"
  matched="author"
  if grep -qx "$sha" <<< "$BY_COMMITTER"; then
    grep -qx "$sha" <<< "$BY_AUTHOR" && matched="both" || matched="committer"
  fi
  branches=$(git branch -a --contains "$sha" --format='%(refname:short)' 2>/dev/null | grep -v '/HEAD$' | jq -R . | jq -sc .)
  merged=false; [[ -n "$DEFAULT_REF" ]] && git merge-base --is-ancestor "$sha" "$DEFAULT_REF" 2>/dev/null && merged=true
  parents=$(git rev-list --parents -n1 "$sha" | wc -w); is_merge=false; (( parents > 2 )) && is_merge=true
  numstat=$(git show --format= --numstat "$sha" 2>/dev/null) || numstat=""
  diff_file="$OUT/diffs/$short.diff"; diff_error=""
  if ! git show "$sha" > "$diff_file" 2>/dev/null; then diff_error="git show failed"; rm -f "$diff_file"; fi
  hits="[]"
  [[ -z "$diff_error" ]] && hits=$(bash "$HERE/scan-patterns.sh" --diff < "$diff_file" | jq -c '.findings')
  jq -nc --arg sha "$full" --arg short "$short" --arg an "$an" --arg ae "$ae" --arg cn "$cn" --arg ce "$ce" \
    --arg date "$date" --arg subject "$subject" --arg matched "$matched" --argjson branches "$branches" \
    --argjson merged "$merged" --argjson is_merge "$is_merge" --arg numstat "$numstat" \
    --arg diff "$diff_file" --arg diff_error "$diff_error" --argjson hits "$hits" '
    ($numstat | split("\n") | map(select(length>0) | split("\t"))) as $rows |
    {sha:$sha, short:$short, date:$date, subject:$subject,
     author_name:$an, author_email:$ae, committer_name:$cn, committer_email:$ce,
     author_ne_committer: (($an|ascii_downcase) != ($cn|ascii_downcase) or ($ae|ascii_downcase) != ($ce|ascii_downcase)),
     matched_by:$matched, is_merge:$is_merge,
     branches:$branches, ref_only:(if ($branches|length)==0 then "tag/stash only" else null end),
     merged_into_default:$merged,
     files_changed:($rows|length),
     insertions:($rows|map(.[0]|tonumber? // 0)|add // 0),
     deletions:($rows|map(.[1]|tonumber? // 0)|add // 0),
     files:($rows|map(.[2])),
     diff_path:(if $diff_error=="" then $diff else null end),
     diff_error:(if $diff_error=="" then null else $diff_error end),
     pattern_hits:$hits}' >> "$COMMITS_ND"
done

# --- assemble -----------------------------------------------------------------------
jq -n --arg repo "$REPO" --arg start "$START_DIR" --arg default "$DEFAULT_NAME" --arg since "$SINCE" --arg days "$DAYS" \
  --argjson fetched "$FETCHED" --arg fetch_error "$FETCH_ERROR" --argjson shallow "$SHALLOW" --argjson bare "$BARE" \
  --argjson stale "$STALE_DAYS" --arg out "$OUT" \
  --argjson authors "$(printf '%s\n' "${AUTHORS[@]}" | jq -R . | jq -s .)" \
  --argjson commands "$(printf '%s\n' "${COMMANDS[@]}" | jq -R . | jq -s .)" \
  --slurpfile branches "$BRANCHES_ND" --slurpfile commits "$COMMITS_ND" --slurpfile unreadable "$UNREADABLE_ND" '
  ($commits | sort_by(.date) | reverse) as $c |
  {repo:$repo, run_from:$start, authors:$authors, since:(if $since=="" then "all" else $since end),
   window_days:(if $days=="" then null else ($days|tonumber) end),
   default_branch:(if $default=="" then null else $default end),
   fetched:$fetched, fetch_error:(if $fetch_error=="" then null else $fetch_error end),
   shallow:$shallow, bare_mirror:$bare, stale_days:$stale, out_dir:$out,
   summary:{
     unique_commits:($c|length),
     merged_into_default:($c|map(select(.merged_into_default))|length),
     unmerged:($c|map(select(.merged_into_default|not))|length),
     author_ne_committer:($c|map(select(.author_ne_committer))|length),
     files_touched:($c|map(.files[])|unique|length),
     branches_total:($branches|length),
     branches_with_author_commits:($branches|map(select(.name as $n | any($c[]; .branches|index($n))))|length),
     pattern_hits:($c|map(.pattern_hits|length)|add // 0),
     unreadable:($unreadable|length)},
   branches:($branches|map(. as $b | .commits_by_author = ($c|map(select(.branches|index($b.name)))|length))
             | sort_by(.commits_by_author) | reverse),
   commits:$c, unreadable:$unreadable, commands:$commands}' > "$OUT/inventory.json"
rm -f "$BRANCHES_ND" "$COMMITS_ND" "$UNREADABLE_ND"
echo "$OUT/inventory.json"
