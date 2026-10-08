#!/usr/bin/env bash
# Collect raw GitHub activity for a date range as one JSON blob. No judgement here;
# the skills do the analysis.
set -euo pipefail

SINCE=""; UNTIL=""; MEMBERS=""; REPOS=""; OUT=""
CONFIG="${CLAUDE_PROJECT_DIR:-.}/.claude/team-report.json"

usage() {
  cat >&2 <<'USAGE'
Usage: collect-github-activity.sh --since YYYY-MM-DD --until YYYY-MM-DD
                                  [--members a,b] [--repos org/x,org/y] [--out path.json]
Dates are inclusive. Defaults for members and repos come from .claude/team-report.json.
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)   SINCE="$2";   shift 2 ;;
    --until)   UNTIL="$2";   shift 2 ;;
    --members) MEMBERS="$2"; shift 2 ;;
    --repos)   REPOS="$2";   shift 2 ;;
    --out)     OUT="$2";     shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$SINCE" && -n "$UNTIL" ]] || usage
[[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad --since: $SINCE" >&2; exit 1; }
[[ "$UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad --until: $UNTIL" >&2; exit 1; }
[[ "$SINCE" < "$UNTIL" || "$SINCE" == "$UNTIL" ]] || { echo "--since is after --until" >&2; exit 1; }

for dep in gh jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "missing dependency: $dep" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated. Run: gh auth login" >&2; exit 1; }

# ---- resolve config ------------------------------------------------------
if [[ -z "$MEMBERS" && -f "$CONFIG" ]]; then MEMBERS=$(jq -r '(.members // []) | join(",")' "$CONFIG"); fi
if [[ -z "$REPOS"   && -f "$CONFIG" ]]; then REPOS=$(jq -r '(.repos // []) | join(",")' "$CONFIG"); fi
if [[ -z "$REPOS" ]]; then
  REPOS=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi
[[ -n "$REPOS" ]] || { echo "no repository resolved; pass --repos or add repos to $CONFIG" >&2; exit 1; }
IFS=',' read -r -a REPO_LIST <<< "$REPOS"

# No members configured: derive them from who committed in the range.
if [[ -z "$MEMBERS" ]]; then
  derived=""
  for repo in "${REPO_LIST[@]}"; do
    logins=$(gh api -X GET "repos/${repo}/commits" \
              -f since="${SINCE}T00:00:00Z" -f until="${UNTIL}T23:59:59Z" -f per_page=100 \
              --paginate --jq '.[] | .author.login // empty' 2>/dev/null | sort -u | paste -sd, - || true)
    derived="${derived}${derived:+,}${logins}"
  done
  MEMBERS=$(tr ',' '\n' <<< "$derived" | sed '/^$/d' | sort -u | paste -sd, -)
fi
[[ -n "$MEMBERS" ]] || { echo "no team members resolved; pass --members or add members to $CONFIG" >&2; exit 1; }
IFS=',' read -r -a MEMBER_LIST <<< "$MEMBERS"

# ---- collect -------------------------------------------------------------
repo_payloads="[]"
for repo in "${REPO_LIST[@]}"; do
  echo "collecting ${repo} (${SINCE}..${UNTIL})" >&2

  prs=$(gh pr list --repo "$repo" --state all --limit 300 \
          --search "updated:${SINCE}..${UNTIL}" \
          --json number,title,author,state,isDraft,createdAt,updatedAt,closedAt,mergedAt,url,additions,deletions,changedFiles,labels,reviews,comments,files \
        2>/dev/null || echo '[]')
  # Trim review/comment/file bodies to what the analysis needs.
  prs=$(jq -c '[.[] | {
      number, title, state, isDraft, createdAt, updatedAt, closedAt, mergedAt, url,
      additions, deletions, changedFiles,
      author: (.author.login // null),
      labels: [.labels[]?.name],
      files: [.files[]?.path],
      reviews: [.reviews[]? | {author: (.author.login // null), state, submittedAt}],
      comment_count: (.comments | length),
      commenters: ([.comments[]?.author.login] | unique)
    }]' <<< "$prs")

  issues=$(gh issue list --repo "$repo" --state all --limit 300 \
             --search "updated:${SINCE}..${UNTIL}" \
             --json number,title,author,assignees,state,createdAt,closedAt,url,labels \
           2>/dev/null || echo '[]')
  issues=$(jq -c '[.[] | {number, title, state, createdAt, closedAt, url,
      author: (.author.login // null), assignees: [.assignees[]?.login], labels: [.labels[]?.name]}]' <<< "$issues")

  commits="{}"; reviews="{}"
  for m in "${MEMBER_LIST[@]}"; do
    [[ -n "$m" ]] || continue
    c=$(gh api -X GET "repos/${repo}/commits" \
          -f since="${SINCE}T00:00:00Z" -f until="${UNTIL}T23:59:59Z" -f author="$m" -f per_page=100 --paginate \
          --jq '.[] | {sha: .sha[0:7], message: (.commit.message | split("\n")[0]), date: .commit.author.date, url: .html_url}' \
        2>/dev/null | jq -cs '.' || echo '[]')
    commits=$(jq -c --arg m "$m" --argjson c "${c:-[]}" '. + {($m): $c}' <<< "$commits")

    r=$(gh api -X GET search/issues \
          -f q="repo:${repo} type:pr reviewed-by:${m} updated:${SINCE}..${UNTIL}" -f per_page=100 \
          --jq '[.items[] | {number: .number, title: .title, url: .html_url, author: .user.login}]' \
        2>/dev/null || echo '[]')
    reviews=$(jq -c --arg m "$m" --argjson r "${r:-[]}" '. + {($m): $r}' <<< "$reviews")
  done

  repo_payloads=$(jq -c --arg repo "$repo" \
    --argjson prs "$prs" --argjson issues "$issues" --argjson commits "$commits" --argjson reviews "$reviews" \
    '. + [{repo: $repo, pull_requests: $prs, issues: $issues, commits: $commits, reviews: $reviews}]' <<< "$repo_payloads")
done

payload=$(jq -n \
  --arg since "$SINCE" --arg until "$UNTIL" \
  --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson members "$(printf '%s' "$MEMBERS" | jq -R 'split(",") | map(select(length > 0))')" \
  --argjson repos "$repo_payloads" \
  '{generated_at: $generated, range: {since: $since, until: $until}, members: $members, repos: $repos}')

if [[ -n "$OUT" ]]; then
  mkdir -p "$(dirname "$OUT")"
  printf '%s\n' "$payload" > "$OUT"
  echo "wrote $OUT" >&2
else
  printf '%s\n' "$payload"
fi
