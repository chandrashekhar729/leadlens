---
name: monthly-report
description: Generate a monthly engineering report for the team. Delivery themes, per-person trends, recurring blockers and coaching signals, built from GitHub activity. Use when asked for a monthly report, month-end summary, or one-on-one prep.
argument-hint: "[YYYY-MM]"
arguments: month
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh *) Bash(date *) Read Write
---

# Monthly Team Report

## 1. Resolve the range

Use `$month` (YYYY-MM) if given, otherwise the previous complete calendar month (run `date` to get today). Derive the first and last calendar day. Also derive the same range for the month before it; you need both for trend. State both ranges in one line.

## 2. Collect

Run the collector twice, current month then previous month:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-github-activity.sh --since <FIRST> --until <LAST> --out .claude/reports/data/monthly-<YYYY-MM>.json
```

On a non-zero exit, show the error, give the one-line fix, and stop. Do not write a report from partial data. Read the JSON files in sections if they are large.

## 3. Analyse

Apply `${CLAUDE_PLUGIN_ROOT}/references/analysis-rules.md` first, then add the monthly layer:

- **Delivery themes**: group the month's merged PRs into 3-6 themes. A theme is a product or system outcome, not a list of tickets.
- **Trend**: compare against the previous month on merged PRs, review participation, average PR open time, and bug-fix share. Report direction and magnitude, and say plainly when a change is too small to mean anything.
- **Recurring blockers**: anything that blocked work in three or more weeks. These are the TL's to escalate, not the developer's.
- **Coaching signals**: per person, one strength with evidence and one area to grow with evidence. If the evidence is not there, say so rather than filling the slot.
- **Review load balance**: who is carrying review work and whether it is concentrated on one person.

## 4. Write

Follow `${CLAUDE_PLUGIN_ROOT}/references/report-format.md` with the title "Monthly Engineering Report", then append the monthly sections above. Save to `.claude/reports/monthly/<YYYY-MM>.md` and print the TL Summary, Trend and TL Action Items in the conversation with the saved path.

## Standing rules

Everything in the weekly report's standing rules applies here too. Additionally:

- Coaching signals are observations for a conversation, never a verdict.
- A month is a short window. Do not describe a trend from two data points as a pattern.
- Do not modify application code or any file outside `.claude/reports/`.
