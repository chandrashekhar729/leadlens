#!/usr/bin/env bash
# Raw data for the author-audit skill, in one of two modes, read from remote refs
# only. Nothing is checked out, switched, reset or stashed: every commit is read
# from the object store with git log / git show.
#
#   author mode:  collect-audit-commits.sh --author <name|email> [--author <alias>]... \
#                     [--days N|Nd (default 7) | --since YYYY-MM-DD]
#   branch mode:  collect-audit-commits.sh --branch <name> [--base <branch>]
#   both:         [--repo <path|url>] [--master <branch>] [--dev <branch>] [--out <dir>]
#
# Writes <out>/inventory.json, commits.csv, commands.txt and diffs/, and prints the
# path of inventory.json. Default <out> is .claude/reports/data/<scope>/ where
# <scope> is "<author-slug>-<N>d" or "branch-<branch-slug>".
#
# Status of a commit, checked in this order against the remote refs:
#   "In <master>" (origin/master or origin/main), "In <development>" (origin/development
#   or origin/develop, when it exists), else "Not merged".
# A URL repo is mirror-cloned under <out>/mirror; its branches are then read from
# refs/heads with no "origin/" prefix.
set -uo pipefail

MODE=""; AUTHORS=(); DAYS=""; SINCE=""; BRANCH=""; BASE=""; REPO=""; MASTER=""; DEV=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) AUTHORS+=("$2"); MODE="${MODE:-author}"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --branch) BRANCH="${2#origin/}"; MODE="${MODE:-branch}"; shift 2 ;;
    --base) BASE="${2#origin/}"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --master) MASTER="${2#origin/}"; shift 2 ;;
    --dev) DEV="${2#origin/}"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
usage() { echo "usage: --author <name|email> [--author <alias>]... [--days N | --since YYYY-MM-DD]   or   --branch <name> [--base <branch>]   plus [--repo <path|url>] [--master <branch>] [--dev <branch>] [--out <dir>]" >&2; exit 1; }
[[ -n "$MODE" ]] || usage
[[ "$MODE" == "author" && -n "$BRANCH" ]] && { echo "give either --author or --branch, not both" >&2; exit 1; }
[[ "$MODE" == "branch" && ${#AUTHORS[@]} -gt 0 ]] && { echo "give either --author or --branch, not both" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

if [[ "$MODE" == "author" ]]; then
  [[ -n "$DAYS" && -n "$SINCE" ]] && { echo "give either --since or --days, not both" >&2; exit 1; }
  [[ -z "$DAYS" && -z "$SINCE" ]] && DAYS=7
  if [[ -n "$DAYS" ]]; then
    DAYS="${DAYS%d}"
    [[ "$DAYS" =~ ^[0-9]+$ && "$DAYS" -gt 0 ]] || { echo "--days must be a positive whole number, got: $DAYS" >&2; exit 1; }
    SINCE=$(date -d "$DAYS days ago" +%F 2>/dev/null || date -v-"${DAYS}"d +%F 2>/dev/null) \
      || { echo "could not compute the date $DAYS days ago with this system's date command" >&2; exit 1; }
  fi
  [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--since must be YYYY-MM-DD, got: $SINCE" >&2; exit 1; }
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR="$(pwd)"
TODAY=$(date +%F)
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._]\+/-/g; s/^-//; s/-$//'; }
if [[ "$MODE" == "author" ]]; then
  SCOPE="$(slug "${AUTHORS[0]}")-$([[ -n "$DAYS" ]] && echo "${DAYS}d" || echo "since-$SINCE")"
else
  SCOPE="branch-$(slug "$BRANCH")"
fi
[[ -n "$OUT" ]] || OUT=".claude/reports/data/$SCOPE"
mkdir -p "$OUT/diffs" || exit 1
OUT="$(cd "$OUT" && pwd)"
rm -f "$OUT"/diffs/*.diff
COMMANDS=()
rec() { COMMANDS+=("$*"); }

GIT_VERSION=$(git version | sed -E 's/^git version ([0-9]+\.[0-9]+).*/\1/')
git_at_least() { local maj min; IFS=. read -r maj min <<< "$GIT_VERSION"; (( maj > $1 || (maj == $1 && min >= $2) )); }

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

# --- which refs stand for "the remote" -----------------------------------------
if [[ "$BARE" == "true" ]]; then
  P=""; REF_DIR="refs/heads"; REF_SOURCE="mirror"; CONTAINS_FLAG=()
elif git remote get-url origin >/dev/null 2>&1; then
  P="origin/"; REF_DIR="refs/remotes/origin"; REF_SOURCE="origin"; CONTAINS_FLAG=(-r)
else
  P=""; REF_DIR="refs/heads"; REF_SOURCE="local"; CONTAINS_FLAG=()
fi

# --- fetch everything -------------------------------------------------------------
FETCHED=true; FETCH_ERROR=""
if [[ "$BARE" != "true" ]] && git remote | grep -q .; then
  rec "git fetch --all --prune --tags"
  if ! FETCH_ERROR=$(git fetch --all --prune --tags 2>&1 >/dev/null); then FETCHED=false; else FETCH_ERROR=""; fi
fi

# --- master and development ---------------------------------------------------------
ref_of() { git rev-parse -q --verify "$REF_DIR/$1^{commit}" >/dev/null 2>&1 && echo "$REF_DIR/$1"; }
MASTER_REF=""; MASTER_NAME=""
HEAD_TARGET=$(git symbolic-ref -q --short "$REF_DIR/HEAD" 2>/dev/null || git symbolic-ref -q --short HEAD 2>/dev/null || true)
for cand in "$MASTER" master main "${HEAD_TARGET#"$P"}"; do
  [[ -n "$cand" ]] || continue
  r=$(ref_of "$cand") && { MASTER_REF="$r"; MASTER_NAME="$cand"; break; }
done
[[ -n "$MASTER_REF" ]] || { echo "no master or main branch found under $REF_DIR; pass --master <branch>" >&2; exit 1; }
DEV_REF=""; DEV_NAME=""
for cand in "$DEV" development develop; do
  [[ -n "$cand" ]] || continue
  r=$(ref_of "$cand") && { DEV_REF="$r"; DEV_NAME="$cand"; break; }
done
[[ -n "$DEV" && -z "$DEV_REF" ]] && { echo "development branch not found: $REF_DIR/$DEV" >&2; exit 1; }
rec "git merge-base --is-ancestor <sha> $P$MASTER_NAME${DEV_NAME:+  /  git merge-base --is-ancestor <sha> $P$DEV_NAME}"
status_of() {
  if git merge-base --is-ancestor "$1" "$MASTER_REF" 2>/dev/null; then echo "In $MASTER_NAME"
  elif [[ -n "$DEV_REF" ]] && git merge-base --is-ancestor "$1" "$DEV_REF" 2>/dev/null; then echo "In $DEV_NAME"
  else echo "Not merged"; fi
}

# --- helpers shared by both modes ---------------------------------------------------
FMT='%H|%h|%an|%ae|%cn|%ce|%aI|%P|%s'
SKIP_RE='(^|/)(node_modules|dist|build|vendor)/|\.min\.(js|css)$|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$|composer\.lock$|Gemfile\.lock$|\.(png|jpg|jpeg|gif|webp|ico|woff2?|ttf|eot|pdf|sqlite|db)$'
if git_at_least 2 36; then MERGE_DIFF_MODE="remerge-diff"; else MERGE_DIFF_MODE="cc"; fi
# Writes the conflict-resolution diff of a merge commit; exit 0 when it holds any.
merge_diff() {
  if [[ "$MERGE_DIFF_MODE" == "remerge-diff" ]]; then
    git show --remerge-diff "$1" > "$2" 2>/dev/null && grep -q '^diff --git' "$2"
  else
    git show --cc "$1" > "$2" 2>/dev/null && grep -q '^@@@' "$2"
  fi
}
COMMITS_ND=$(mktemp); UNREADABLE_ND=$(mktemp); FP=$(mktemp)
# record_commit <sha> <matched_by>   -> one JSON line in COMMITS_ND
record_commit() {
  local sha=$1 matched=$2 meta full short an ae cn ce date parents subject
  meta=$(git log -1 --pretty=format:"$FMT" "$sha" 2>/dev/null) || { jq -nc --arg s "$sha" '{sha:$s, reason:"git log -1 failed"}' >> "$UNREADABLE_ND"; return; }
  IFS='|' read -r full short an ae cn ce date parents subject <<< "$meta"
  local nparents; nparents=$(wc -w <<< "$parents"); local is_merge=false; (( nparents > 1 )) && is_merge=true
  local status; status=$(status_of "$full")
  # Branches holding the commit: the ones that stand for the remote, and local-only ones.
  local allrefs contains local_only
  allrefs=$(git for-each-ref --format='%(refname)' --contains "$full" refs/heads refs/remotes 2>/dev/null | grep -v '/HEAD$')
  contains=$(grep "^$REF_DIR/" <<< "$allrefs" | sed "s|^$REF_DIR/||" | jq -R . | jq -sc .)
  if [[ "$REF_SOURCE" == "origin" ]]; then
    local_only=$(grep '^refs/heads/' <<< "$allrefs" | sed 's|^refs/heads/||' | jq -R . | jq -sc .)
  else local_only="[]"; fi
  local home="[]"
  [[ "$MODE" == "author" ]] && home=$(grep "^$full " "$FP" | cut -d' ' -f2- | sort -u | jq -R . | jq -sc .)
  local numstat; numstat=$(git show --format= --numstat "$full" 2>/dev/null) || numstat=""
  local diff_file="$OUT/diffs/$short.diff" diff_error="" conflict_fix=false hits="[]"
  if [[ "$is_merge" == "true" ]]; then
    diff_file="$OUT/diffs/$short.merge.diff"
    if merge_diff "$full" "$diff_file"; then conflict_fix=true; fi
    [[ -s "$diff_file" ]] || { diff_error="git show failed"; rm -f "$diff_file"; }
  else
    if git show "$full" > "$diff_file" 2>/dev/null; then
      hits=$(bash "$HERE/scan-patterns.sh" --diff < "$diff_file" | jq -c '.findings')
    else diff_error="git show failed"; rm -f "$diff_file"; fi
  fi
  jq -nc --arg sha "$full" --arg short "$short" --arg an "$an" --arg ae "$ae" --arg cn "$cn" --arg ce "$ce" \
    --arg date "$date" --arg subject "$subject" --arg matched "$matched" --arg status "$status" \
    --argjson contains "$contains" --argjson local_only "$local_only" --argjson home "$home" --argjson is_merge "$is_merge" --argjson conflict_fix "$conflict_fix" \
    --arg numstat "$numstat" --arg diff "$diff_file" --arg diff_error "$diff_error" --argjson hits "$hits" --arg skip "$SKIP_RE" '
    ($numstat | split("\n") | map(select(length>0) | split("\t"))) as $rows |
    ($rows | map(.[2])) as $files |
    {sha:$sha, short:$short, date:$date, subject:$subject,
     author_name:$an, author_email:$ae, committer_name:$cn, committer_email:$ce,
     author_ne_committer: (($an|ascii_downcase) != ($cn|ascii_downcase) or ($ae|ascii_downcase) != ($ce|ascii_downcase)),
     matched_by:$matched, is_merge:$is_merge, conflict_fix:$conflict_fix, status:$status,
     home_branches:$home, contained_in:$contains, local_branches_only:$local_only,
     ref_only:(if ($contains|length)>0 then null
               elif ($local_only|length)>0 then "local branch only, not pushed"
               else "tag/stash only" end),
     files_changed:($files|length),
     insertions:($rows|map(.[0]|tonumber? // 0)|add // 0),
     deletions:($rows|map(.[1]|tonumber? // 0)|add // 0),
     files:$files,
     review:(if $diff_error != "" then "skip: diff unreadable"
             elif $is_merge then (if $conflict_fix then "read: merge commit with conflict fixes" else "skip: merge commit, no conflict fixes" end)
             elif ($files|length)==0 then "skip: empty commit"
             elif ($files|all(test($skip))) then "skip: generated, lock or binary files only"
             else "read" end),
     diff_path:(if $diff_error=="" then $diff else null end),
     diff_error:(if $diff_error=="" then null else $diff_error end),
     pattern_hits:$hits}' >> "$COMMITS_ND"
}

# --- author mode ------------------------------------------------------------------------
if [[ "$MODE" == "author" ]]; then
  AUTHOR_ARGS=(); COMMITTER_ARGS=()
  for a in "${AUTHORS[@]}"; do AUTHOR_ARGS+=("--author=$a"); COMMITTER_ARGS+=("--committer=$a"); done
  SINCE_ARG="--since=$SINCE 00:00:00"
  rec "git log --all -i --fixed-strings ${AUTHOR_ARGS[*]} --since='$SINCE 00:00:00' --pretty=format:'$FMT'"
  rec "git log --all -i --fixed-strings ${COMMITTER_ARGS[*]} --since='$SINCE 00:00:00' --pretty=format:'$FMT'"
  BY_AUTHOR=$(git log --all -i --fixed-strings "${AUTHOR_ARGS[@]}" "$SINCE_ARG" --pretty=format:'%H')
  BY_COMMITTER=$(git log --all -i --fixed-strings "${COMMITTER_ARGS[@]}" "$SINCE_ARG" --pretty=format:'%H')
  ALL_SHAS=$(printf '%s\n%s\n' "$BY_AUTHOR" "$BY_COMMITTER" | grep -v '^$' | sort -u)

  # Home branches: a commit is at home on a branch when it sits on that branch's own
  # line (first parent), not when it arrived through a merge of another branch.
  rec "git rev-list --first-parent $P<branch> --since='$SINCE 00:00:00'   (once per branch under $REF_DIR)"
  while read -r ref; do
    [[ "$ref" == */HEAD ]] && continue
    name="${ref#"$REF_DIR/"}"
    git rev-list --first-parent "$ref" "$SINCE_ARG" 2>/dev/null | sed "s|\$| $name|" >> "$FP"
  done < <(git for-each-ref --format='%(refname)' "$REF_DIR")

  rec "git branch ${CONTAINS_FLAG[*]:-} --contains <sha>"
  rec "git show --format= --numstat <sha>  /  git show <sha> > diffs/<sha>.diff  /  git show --$MERGE_DIFF_MODE <merge sha> > diffs/<sha>.merge.diff"
  for sha in $ALL_SHAS; do
    matched="author"
    if grep -qx "$sha" <<< "$BY_COMMITTER"; then grep -qx "$sha" <<< "$BY_AUTHOR" && matched="both" || matched="committer"; fi
    record_commit "$sha" "$matched"
  done

  # One entry per home branch: own (non-merge) commits, tip status, last commit date.
  BRANCHES_ND=$(mktemp)
  for b in $(jq -r '.home_branches[]' "$COMMITS_ND" | sort -u); do
    tip=$(git rev-parse -q --verify "$REF_DIR/$b^{commit}" 2>/dev/null) || continue
    bstatus=$(status_of "$tip")
    last=$(git log -1 --pretty=%cI "$tip")
    jq -nc --arg n "$b" --arg s "$bstatus" --arg l "$last" '{name:$n, status:$s, last_commit:$l}' >> "$BRANCHES_ND"
  done
  BRANCHES_JSON=$(jq -sc --slurpfile c <(jq -s . "$COMMITS_ND") '
    $c[0] as $commits |
    map(. as $b
      | ($commits | map(select((.is_merge|not) and (.home_branches|index($b.name))))) as $own
      | ($commits | map(select(.is_merge and (.home_branches|index($b.name))))) as $merges
      | $b + {own_commits:($own|length), own_shas:($own|map(.short)), merge_commits:($merges|length)})
    | sort_by(.own_commits) | reverse' "$BRANCHES_ND")
  rm -f "$BRANCHES_ND"
  EXTRA=$(jq -nc --argjson authors "$(printf '%s\n' "${AUTHORS[@]}" | jq -R . | jq -s .)" --arg since "$SINCE" --arg days "$DAYS" --arg today "$TODAY" \
    --argjson branches "$BRANCHES_JSON" \
    '{authors:$authors, window:{start:$since, end:$today, days:(if $days=="" then null else ($days|tonumber) end)}, home_branches:$branches}')
fi

# --- branch mode --------------------------------------------------------------------------
if [[ "$MODE" == "branch" ]]; then
  BRANCH_REF=$(ref_of "$BRANCH") || { echo "branch not found after fetch: $REF_DIR/$BRANCH" >&2; exit 1; }
  if [[ -z "$BASE" ]]; then
    for cand in "$DEV_NAME" "$MASTER_NAME"; do [[ -n "$cand" ]] && { BASE="$cand"; break; }; done
  fi
  BASE_REF=$(ref_of "$BASE") || { echo "base branch not found: $REF_DIR/$BASE" >&2; exit 1; }
  [[ "$BASE" != "$BRANCH" ]] || { echo "branch and base are the same: $BRANCH" >&2; exit 1; }

  rec "git log --no-merges $P$BASE..$P$BRANCH --pretty=format:'$FMT'"
  rec "git log --merges $P$BASE..$P$BRANCH --pretty=format:'$FMT'"
  OWN=$(git log --no-merges "$BASE_REF..$BRANCH_REF" --pretty=format:'%H')
  MERGES=$(git log --merges "$BASE_REF..$BRANCH_REF" --pretty=format:'%H')
  rec "git branch ${CONTAINS_FLAG[*]:-} --contains <sha>"
  rec "git show --format= --numstat <sha>  /  git show <sha> > diffs/<sha>.diff  /  git show --$MERGE_DIFF_MODE <merge sha> > diffs/<sha>.merge.diff"
  for sha in $OWN $MERGES; do record_commit "$sha" "branch"; done

  rec "git diff $P$BASE...$P$BRANCH > diffs/branch.diff"
  git diff "$BASE_REF...$BRANCH_REF" > "$OUT/diffs/branch.diff" 2>/dev/null
  rec "git diff --numstat $P$BASE...$P$BRANCH"
  FILES_JSON=$(git diff --numstat "$BASE_REF...$BRANCH_REF" 2>/dev/null | jq -R 'split("\t") | {path:.[2], insertions:(.[0]|tonumber? // 0), deletions:(.[1]|tonumber? // 0)}' | jq -sc .)
  BRANCH_HITS=$(bash "$HERE/scan-patterns.sh" --diff < "$OUT/diffs/branch.diff" | jq -c '.findings')
  rec "git rev-list --left-right --count $P$BASE...$P$BRANCH"
  read -r BEHIND AHEAD < <(git rev-list --left-right --count "$BASE_REF...$BRANCH_REF")

  # Clean-merge check. Git 2.38+ has merge-tree --write-tree (exit 1 = conflicts and
  # the conflicted paths); older Git gets the three-argument merge-tree, where a
  # content conflict shows as a "changed in both" / "added in both" block with markers.
  CLEAN_CHECKED=true; CLEAN=true; CONFLICTS="[]"; CLEAN_METHOD=""
  if git_at_least 2 38; then
    CLEAN_METHOD="git merge-tree --write-tree --name-only"
    rec "git merge-tree --write-tree --name-only $P$BASE $P$BRANCH"
    mt=$(git merge-tree --write-tree --name-only "$BASE_REF" "$BRANCH_REF" 2>/dev/null); rc=$?
    if (( rc == 1 )); then CLEAN=false; CONFLICTS=$(sed -n '2,$p' <<< "$mt" | sed '/^$/d' | jq -R . | jq -sc 'unique')
    elif (( rc > 1 )); then CLEAN_CHECKED=false; fi
  else
    CLEAN_METHOD="git merge-tree <merge-base> base branch (Git < 2.38: content conflicts only)"
    rec "git merge-tree \$(git merge-base $P$BASE $P$BRANCH) $P$BASE $P$BRANCH"
    mb=$(git merge-base "$BASE_REF" "$BRANCH_REF" 2>/dev/null)
    if [[ -n "$mb" ]] && mt=$(git merge-tree "$mb" "$BASE_REF" "$BRANCH_REF" 2>/dev/null); then
      CONFLICTS=$(awk '
        /^(changed|added) in both/ {inblock=1; path=""; next}
        /^(changed in|added in|removed in|merged)/ {inblock=0}
        inblock && /^  our +[0-9]+ [0-9a-f]+ / {path=$4; for(i=5;i<=NF;i++) path=path" "$i}
        inblock && /^\+<<<<<<< / && path!="" {print path}' <<< "$mt" | sort -u | jq -R . | jq -sc .)
      [[ "$CONFLICTS" == "[]" ]] || CLEAN=false
    else CLEAN_CHECKED=false; fi
  fi
  EXTRA=$(jq -nc --arg branch "$BRANCH" --arg base "$BASE" --argjson ahead "$AHEAD" --argjson behind "$BEHIND" \
    --argjson checked "$CLEAN_CHECKED" --argjson clean "$CLEAN" --argjson conflicts "$CONFLICTS" --arg method "$CLEAN_METHOD" \
    --argjson files "$FILES_JSON" --argjson hits "$BRANCH_HITS" --arg diff "$OUT/diffs/branch.diff" \
    '{branch:$branch, base:$base, ahead:$ahead, behind:$behind,
      clean_merge:{checked:$checked, clean:(if $checked then $clean else null end), conflicts:$conflicts, method:$method},
      branch_diff:{path:$diff, files:$files, insertions:($files|map(.insertions)|add // 0), deletions:($files|map(.deletions)|add // 0), pattern_hits:$hits}}')
fi

# --- assemble ---------------------------------------------------------------------------------
jq -n --arg mode "$MODE" --arg scope "$SCOPE" --arg repo "$REPO" --arg start "$START_DIR" --arg out "$OUT" --arg today "$TODAY" \
  --arg master "$MASTER_NAME" --arg dev "$DEV_NAME" --arg prefix "$P" --arg ref_source "$REF_SOURCE" \
  --argjson fetched "$FETCHED" --arg fetch_error "$FETCH_ERROR" --argjson shallow "$SHALLOW" --argjson bare "$BARE" \
  --arg gitv "$GIT_VERSION" --arg mdm "$MERGE_DIFF_MODE" --argjson extra "$EXTRA" \
  --argjson commands "$(printf '%s\n' "${COMMANDS[@]}" | jq -R . | jq -s .)" \
  --slurpfile commits "$COMMITS_ND" --slurpfile unreadable "$UNREADABLE_ND" '
  ($commits | sort_by(.date) | reverse) as $c |
  ($c | map(select(.is_merge|not))) as $own |
  {mode:$mode, scope:$scope, report_path:(".claude/reports/" + $scope + ".md"), data_dir:$out,
   repo:$repo, run_from:$start, generated:$today, git_version:$gitv, merge_diff_mode:$mdm,
   master_branch:$master, development_branch:(if $dev=="" then null else $dev end),
   ref_prefix:$prefix, ref_source:$ref_source,
   fetched:$fetched, fetch_error:(if $fetch_error=="" then null else $fetch_error end), shallow:$shallow, bare_mirror:$bare}
  + $extra +
  {summary:{
     own_commits:($own|length),
     in_master:($own|map(select(.status=="In "+$master))|length),
     in_development:(if $dev=="" then null else ($own|map(select(.status=="In "+$dev))|length) end),
     not_merged:($own|map(select(.status=="Not merged"))|length),
     merge_commits:($c|map(select(.is_merge))|length),
     merge_commits_with_conflict_fixes:($c|map(select(.is_merge and .conflict_fix))|length),
     author_ne_committer:($own|map(select(.author_ne_committer))|length),
     ref_only:($c|map(select(.ref_only!=null))|length),
     to_read:($c|map(select(.review=="read" or (.review|startswith("read:"))))|length),
     files_touched:($own|map(.files[])|unique|length),
     pattern_hits:($c|map(.pattern_hits|length)|add // 0),
     unreadable:($unreadable|length),
     authors:($own|map(.author_name)|unique)},
   commits:$c, unreadable:$unreadable, commands:$commands}' > "$OUT/inventory.json" || { echo "could not assemble inventory.json" >&2; exit 1; }

# commits.csv: one row per commit, newest first. "review" says what the audit should do
# with it; the skill changes a cell only when it departs from that.
{
  printf 'sha,date,author,home_branches,status,merge,files,added,removed,review,message\n'
  jq -r '.commits[] | [.short, (.date|.[0:10]), .author_name, (.home_branches|join(";")), .status,
         (if .is_merge then "yes" else "no" end), .files_changed, .insertions, .deletions, .review, .subject] | @csv' "$OUT/inventory.json"
} > "$OUT/commits.csv"
printf '%s\n' "${COMMANDS[@]}" > "$OUT/commands.txt"
rm -f "$COMMITS_ND" "$UNREADABLE_ND" "$FP"
echo "$OUT/inventory.json"
