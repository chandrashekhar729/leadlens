# LeadLens

A TL's lens for reviewing code, architecture and implementation. A Claude Code plugin for Team Leads and PMs. It turns GitHub activity into weekly and monthly engineering reports, adds a fast pre-merge review skill, and blocks hardcoded secrets before they are written.

| Command | What it does |
|---|---|
| `/leadlens:weekly-report [owner/repo] [github-login] [since] [until]` | Weekly report: delivered work, PRs, reviews, blockers, TL action items. Defaults to the last 7 days. Give a repo to run from anywhere without a config file, and a GitHub login for a one-person report. Review health follows the same checklist as `quick-review`, aggregate only. |
| `/leadlens:monthly-report [owner/repo] [github-login] [YYYY-MM]` | Monthly report: delivery themes, trend versus the previous month, recurring blockers, coaching signals. Add a GitHub login for a one-person report, useful for one-on-one prep. Review health follows the same checklist as `quick-review`, aggregate only. |
| `/leadlens:quick-review [base-ref] [--fast]` | Review of changed files against project guidelines, styling tokens, UI/UX, accessibility and defensive security checklists, plus prettier, eslint, typecheck and tests. Changed screens are also verified in the browser when the diff touches front-end files and a dev server and browser tool are available. |

The hook runs on every `Edit` and `Write` and blocks the write when the new text contains a hardcoded credential, a cloud or payment key, or a private key block. Everything else (XSS, a11y, debug statements) is reported by `quick-review`, never blocked.

## Principles

- Delivery over activity. The reports never rank people by commit count. Commits are correlated with PRs, reviews and issues.
- Evidence on every claim. Each delivered item carries a PR, issue or commit reference. Missing evidence is stated as "Not enough GitHub evidence".
- Situations, not people. Risk flags name the PR and the wait, not the developer.
- Nothing runs on its own. All three skills are user-invoked. Claude never generates a report unless you ask.

## Install

Requires `gh` (authenticated with `gh auth login`) and `jq`. `quick-review` uses the project's own prettier, eslint, tsc and test script when present. Browser verification in `quick-review` is best effort and needs a browser MCP tool (Claude in Chrome or Playwright); it is skipped otherwise.

From a GitHub marketplace repo:

```
/plugin marketplace add <owner>/leadlens
/plugin install leadlens@leadlens
```

From a local checkout:

```
claude plugin marketplace add /path/to/leadlens
claude plugin install leadlens@leadlens
```

Restart Claude Code or run `/reload-plugins`. A plugin installed from a local path is read from that folder, so edits take effect at the next session start or `/reload-plugins`. For a plugin installed from GitHub, run `claude plugin update leadlens@leadlens` to pick up a new version.

## Configure your team

Copy `templates/team-report.json` to `.claude/team-report.json` in the project you run reports from:

```json
{
  "members": ["github-login-1", "github-login-2"],
  "repos": ["your-org/your-repo"]
}
```

Members are GitHub logins. Without this file the collector uses the current repo and everyone who committed in the range.

Reports are written to `.claude/reports/weekly/`, `.claude/reports/monthly/` and raw data to `.claude/reports/data/`. Add `.claude/reports/` to the project's `.gitignore`.

## Schedule it

Copy `templates/weekly-report.yml` to `.github/workflows/` in the reported repo. It runs Monday 09:15 IST, installs the plugin, collects the previous Monday to Sunday, and publishes the report as a job summary and artifact. Set the `ANTHROPIC_API_KEY` secret and a `LEADLENS_MARKETPLACE` variable pointing at your marketplace repo.

## Layout

```
leadlens/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   ├── weekly-report/SKILL.md
│   ├── monthly-report/SKILL.md
│   └── quick-review/SKILL.md
├── references/
│   ├── analysis-rules.md
│   ├── report-format.md
│   ├── review-checklist.md
│   ├── ui-guidelines.md
│   └── security-review.md
├── scripts/
│   ├── collect-github-activity.sh
│   ├── quick-checks.sh
│   └── scan-patterns.sh
├── hooks/hooks.json
└── templates/
    ├── team-report.json
    └── weekly-report.yml
```

## Privacy

The collector only reads from GitHub through your own `gh` login. Reports are written locally under `.claude/reports/`. The hook reads the tool input on stdin and makes no network calls.
