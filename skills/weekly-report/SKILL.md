---
name: weekly-report
description: Generate a weekly engineering report for the team from GitHub activity. Delivered work, PRs, reviews, blockers and TL action items. Use when asked for a weekly team report, sprint summary, or what the team shipped this week.
argument-hint: "[owner/repo] [github-login] [since YYYY-MM-DD] [until YYYY-MM-DD]"
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh *) Bash(date *) Bash(git merge-base *) Bash(git rev-list *) Bash(git diff *) Bash(npm *) Bash(pnpm *) Bash(yarn *) Bash(curl *) Bash(kill *) Bash(python3 -m http.server *) Read Write Grep Glob mcp__claude-in-chrome mcp__plugin_playwright_playwright
---

# Weekly Team Report

## 1. Parse arguments

`$ARGUMENTS` holds zero or more space-separated tokens, in any order:

- A token containing `/` is a repository, `owner/repo`. A GitHub URL such as `https://github.com/owner/repo.git` is the same thing: strip the host and the `.git`. Several repo tokens are allowed.
- Tokens matching `YYYY-MM-DD` are dates. The first is SINCE, the second is UNTIL. If only one is given, treat it as SINCE and use SINCE plus six days as UNTIL.
- Any other token is a GitHub login: this is a **person report** for that one member. Strip a leading `@` if present.

With no dates, use the last 7 days: UNTIL is today and SINCE is six days earlier (run `date +%F` to get today). State the resolved range, the repo if given, and the person if any, in one line before continuing.

## 2. Collect

Run exactly:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh --since <SINCE> --until <UNTIL> --out .claude/reports/data/weekly-<SINCE>.json
```

If a repo was given add `--repos <owner/repo>` (comma-separated for several). Without it the collector uses `repos` from `.claude/team-report.json`, or the repo of the current directory.

For a person report add `--members <login>` and name the data file `weekly-<SINCE>-<login>.json`. The login must be the GitHub username as listed in `members` of `.claude/team-report.json`, not a display name. If the collector returns no activity for it, say so and stop; do not fall back to the whole team.

If it exits non-zero, show the error, give the one-line fix (`gh auth login`, install `jq`, or add `members` and `repos` to `.claude/team-report.json`) and stop. Do not write a report from partial or guessed data.

Read the JSON file it wrote. If it is large, read it in sections.

## 3. Analyse

Read `${CLAUDE_PLUGIN_ROOT}/references/analysis-rules.md` and apply it to the collected JSON.

## 3b. Review health (team report only, aggregate only)

Skip this step silently, including the browser pass, when this is a person
report or when the current directory is not a git checkout of one of the
report's repos.

Otherwise find the base commit with `git rev-list -1 --before=<SINCE> HEAD`
and run once:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh --base <that commit> --fast
```

Then read `${CLAUDE_PLUGIN_ROOT}/references/review-checklist.md` and apply all
six sections, in report mode, to `git diff <base>...HEAD`: project rules,
styling tokens, code and architecture, defensive security, accessibility, and
the gated browser verification of changed screens. If more than 40 files
changed, review the 40 with the highest churn and say so under Evidence gaps.

Report counts and themes only, one line per dimension plus the `Browser
checks` line, under **Review health** in the Team view. Do not review
individual PRs here and do not attribute findings to people. A recurring
category is a team gap to raise as a convention to agree on, not as someone's
mistake. A finding feeds Review health and TL action items, never a merge
decision.

## 4. Write

Read `${CLAUDE_PLUGIN_ROOT}/references/report-format.md` and produce the report in that exact shape. Save it to `.claude/reports/weekly/<ISO-year>-W<week-number>.md`, then print the **TL Summary** and **TL Action Items** sections in the conversation with the saved path.

**Person report**: keep the TL Summary, that one developer's section and TL Action Items. Drop the Team view and Review health. Save to `.claude/reports/weekly/<ISO-year>-W<week-number>-<login>.md` so the team report for the same week is not overwritten.

## Standing rules

These apply to every turn of this task, not only the first:

- Never rank people by commit count.
- In a person report, do not compare the person with teammates or mention other members' work. It is one-on-one prep, not a league table.
- Every claim about delivered work carries a PR, issue or commit reference.
- Where evidence is missing, write "Not enough GitHub evidence" instead of inferring.
- Keep facts and interpretation in separate sections.
- Report on delivery, blockers and support needed, not on activity levels.
- Do not modify application code or any file outside `.claude/reports/`. A dev server started for Review health may write its own caches; screenshots and logs go to the session scratchpad, never the repo. Stop that server before writing the report.
