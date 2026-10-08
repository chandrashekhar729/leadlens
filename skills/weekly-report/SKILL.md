---
name: weekly-report
description: Generate a weekly engineering report for the team from GitHub activity. Delivered work, PRs, reviews, blockers and TL action items. Use when asked for a weekly team report, sprint summary, or what the team shipped this week.
argument-hint: "[since YYYY-MM-DD] [until YYYY-MM-DD]"
arguments: since until
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh *) Bash(date *) Bash(git merge-base *) Bash(git rev-list *) Read Write
---

# Weekly Team Report

## 1. Resolve the range

Use `$since` and `$until` if given. Otherwise use the previous full week, Monday to Sunday, relative to today (run `date` to get today). State the resolved range in one line before continuing.

## 2. Collect

Run exactly:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh --since <SINCE> --until <UNTIL> --out .claude/reports/data/weekly-<SINCE>.json
```

If it exits non-zero, show the error, give the one-line fix (`gh auth login`, install `jq`, or add `members` and `repos` to `.claude/team-report.json`) and stop. Do not write a report from partial or guessed data.

Read the JSON file it wrote. If it is large, read it in sections.

## 3. Analyse

Read `${CLAUDE_PLUGIN_ROOT}/references/analysis-rules.md` and apply it to the collected JSON.

## 3b. Review health (optional, aggregate only)

Only when the current directory is a git checkout of one of the report's repos: find the first commit on or after SINCE with `git rev-list -1 --before=<SINCE> HEAD`, then run once:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh --base <that commit> --fast
```

Report counts and themes only, under **Review health** in the Team view. Do not review individual PRs here and do not attribute findings to people. A recurring category is a team gap to raise as a convention to agree on, not as someone's mistake. Skip this step silently if the directory is not a matching checkout.

## 4. Write

Read `${CLAUDE_PLUGIN_ROOT}/references/report-format.md` and produce the report in that exact shape. Save it to `.claude/reports/weekly/<ISO-year>-W<week-number>.md`, then print the **TL Summary** and **TL Action Items** sections in the conversation with the saved path.

## Standing rules

These apply to every turn of this task, not only the first:

- Never rank people by commit count.
- Every claim about delivered work carries a PR, issue or commit reference.
- Where evidence is missing, write "Not enough GitHub evidence" instead of inferring.
- Keep facts and interpretation in separate sections.
- Report on delivery, blockers and support needed, not on activity levels.
- Do not modify application code or any file outside `.claude/reports/`.
