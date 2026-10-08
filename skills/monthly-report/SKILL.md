---
name: monthly-report
description: Generate a monthly engineering report for the team. Delivery themes, per-person trends, recurring blockers and coaching signals, built from GitHub activity. Use when asked for a monthly report, month-end summary, or one-on-one prep.
argument-hint: "[owner/repo] [github-login] [YYYY-MM]"
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh *) Bash(date *) Bash(git rev-list *) Bash(git diff *) Bash(npm *) Bash(pnpm *) Bash(yarn *) Bash(curl *) Bash(kill *) Read Write Grep Glob mcp__claude-in-chrome mcp__plugin_playwright_playwright
---

# Monthly Team Report

## 1. Parse arguments and resolve the range

`$ARGUMENTS` holds zero or more space-separated tokens, in any order:

- A token containing `/` is a repository, `owner/repo`. A GitHub URL is the same thing: strip the host and the `.git`. Several repo tokens are allowed.
- A token matching `YYYY-MM` is the month.
- Any other token is a GitHub login: this is a **person report** for that one member. Strip a leading `@` if present.

With no month, use the previous complete calendar month (run `date` to get today). Derive the first and last calendar day. Also derive the same range for the month before it; you need both for trend. State both ranges, and the person if any, in one line.

## 2. Collect

Run the collector twice, current month then previous month:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh --since <FIRST> --until <LAST> --out .claude/reports/data/monthly-<YYYY-MM>.json
```

If a repo was given add `--repos <owner/repo>` to both runs. For a person report add `--members <login>` to both runs and name the data files `monthly-<YYYY-MM>-<login>.json`. The login must be the GitHub username as listed in `members` of `.claude/team-report.json`. If the collector returns no activity for it, say so and stop; do not fall back to the whole team.

On a non-zero exit, show the error, give the one-line fix, and stop. Do not write a report from partial data. Read the JSON files in sections if they are large.

## 3. Analyse

Apply `${CLAUDE_PLUGIN_ROOT}/references/analysis-rules.md` first, then add the monthly layer:

- **Delivery themes**: group the month's merged PRs into 3-6 themes. A theme is a product or system outcome, not a list of tickets.
- **Trend**: compare against the previous month on merged PRs, review participation, average PR open time, and bug-fix share. Report direction and magnitude, and say plainly when a change is too small to mean anything.
- **Recurring blockers**: anything that blocked work in three or more weeks. These are the TL's to escalate, not the developer's.
- **Coaching signals**: per person, one strength with evidence and one area to grow with evidence. If the evidence is not there, say so rather than filling the slot.
- **Review load balance**: who is carrying review work and whether it is concentrated on one person.

## 3b. Review health (team report only, aggregate only)

Skip this step silently, including the browser pass, when this is a person
report or when the current directory is not a git checkout of one of the
report's repos.

Otherwise find the base commit with `git rev-list -1 --before=<FIRST> HEAD`
and run once:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh --base <that commit> --fast
```

Then read `${CLAUDE_PLUGIN_ROOT}/references/review-checklist.md` and apply all
six sections, in report mode, to `git diff <base>...HEAD`: project rules,
styling tokens, code and architecture, defensive security, accessibility, and
the gated browser verification of changed screens. A month's diff can be
large: if more than 40 files changed, review the 40 with the highest churn and
say so under Evidence gaps.

Report counts and themes only, one line per dimension plus the `Browser
checks` line, under **Review health** in the Team view. Do not attribute
findings to people. A category that recurs across the month is a convention
for the team to agree on, and a candidate coaching signal only when the
evidence is there. A finding feeds Review health and TL action items, never a
merge decision.

## 4. Write

Follow `${CLAUDE_PLUGIN_ROOT}/references/report-format.md` with the title "Monthly Engineering Report", then append the monthly sections above. Save to `.claude/reports/monthly/<YYYY-MM>.md` and print the TL Summary, Trend and TL Action Items in the conversation with the saved path.

**Person report**: keep the TL Summary, that developer's section, their Trend and Coaching signals, and TL Action Items. Drop Team view, Review load balance and any team-wide theme the person did not contribute to. Save to `.claude/reports/monthly/<YYYY-MM>-<login>.md`.

## Standing rules

Everything in the weekly report's standing rules applies here too. Additionally:

- Coaching signals are observations for a conversation, never a verdict.
- In a person report, do not compare the person with teammates or mention other members' work.
- A month is a short window. Do not describe a trend from two data points as a pattern.
- A dev server started for Review health may write its own caches; screenshots and logs go to the session scratchpad, never the repo. Stop that server before writing the report.
- Do not modify application code or any file outside `.claude/reports/`.
