# LeadLens

LeadLens is a Claude Code plugin for Team Leads and PMs: a TL's lens for reviewing code, architecture and implementation. It turns GitHub activity into weekly and monthly engineering reports, reviews a change before merge, audits one change with real gates and a ship verdict, writes a short code audit of one author's commits or one branch, and blocks hardcoded secrets before they are written.

Every claim in a report carries a PR, issue or commit reference. Nothing runs on its own: the reports and audits are user-invoked, and Claude never generates one unless you ask.

MIT. Source at https://github.com/chandrashekhar729/leadlens.

## Key features

- **Weekly and monthly reports**: delivered work, PRs, reviews, blockers and TL action items from GitHub, for the whole team or one person. Delivery over activity; nobody is ranked by commit count.
- **Quick review**: a fast pass over the changed files against project guidelines, styling tokens, UI/UX, accessibility and defensive security checklists, plus prettier, eslint, typecheck and tests. Changed screens are opened in the browser when a browser tool is available.
- **Lead Lens audit**: an evidence-based audit of one change that runs the real gates (typecheck, lint, stylelint, tests, build), traces the blast radius of every changed export and reports SHIP, SHIP WITH NOTES, FIX FIRST or NEEDS INPUT. Anything unchecked is UNVERIFIED, never a pass. `--fix` fixes Blockers and Majors and re-audits, at most three loops.
- **Author audit**: a one-screen code audit from git alone. One person's commits across every remote branch, or one branch against the branch it will merge into, with issues ranked Critical to Low, `file:line` and a concrete fix. Plain English or Hinglish.
- **Secrets hook**: every `Edit` and `Write` is scanned and blocked when the new text contains a hardcoded credential, a cloud or payment key, or a private key block. Everything else is reported by review, never blocked.

## Quick start

In the Claude Code terminal:

```
/plugin marketplace add chandrashekhar729/leadlens
/plugin install leadlens@leadlens
```

In the VS Code extension, where `/plugin` does not exist, open this link (GitHub shows it as plain text, so copy it into the browser's address bar). It opens the Claude Code panel on LeadLens, adds the marketplace if needed and asks for a scope:

```
vscode://anthropic.claude-code/install-plugin?plugin=leadlens&marketplace=chandrashekhar729/leadlens
```

Or type `/plugins` in the prompt box, add `chandrashekhar729/leadlens` in the Marketplaces tab, then install LeadLens from the Plugins tab. From any shell, `claude plugin marketplace add chandrashekhar729/leadlens` and `claude plugin install leadlens@leadlens` do the same without a dialog.

From a local checkout:

```
claude plugin marketplace add /path/to/leadlens
claude plugin install leadlens@leadlens
```

Restart Claude Code or run `/reload-plugins`. Then, in the project you report on, copy `templates/team-report.json` to `.claude/team-report.json`:

```json
{
  "members": ["github-login-1", "github-login-2"],
  "repos": ["your-org/your-repo"],
  "baseUrl": "http://localhost:8080"
}
```

Members are GitHub logins. Without this file the collector uses the current repo and everyone who committed in the range. `baseUrl` is optional: the local URL where the app is already served, for example by Apache. Browser verification opens it instead of starting a dev server. Add `.claude/reports/` to the project's `.gitignore`; that is where every report and its raw data goes.

## Updating

Claude Code does not update plugins on its own. A new LeadLens version becomes visible when the version in the repo changes, and you pick it up with:

```
/plugin marketplace update leadlens
```

or `claude plugin update leadlens@leadlens` from a shell, then restart Claude Code. To update automatically at session start, open `/plugin`, pick the LeadLens marketplace under Marketplaces and choose Enable auto-update. A plugin installed from a local path is read from that folder, so edits take effect at the next session start or `/reload-plugins`.

## Commands

| Command | What it does |
|---|---|
| `/leadlens:weekly-report [owner/repo] [github-login] [since] [until]` | Weekly report: delivered work, PRs, reviews, blockers, TL action items. Defaults to the last 7 days. Give a repo to run from anywhere without a config file, and a GitHub login for a one-person report. |
| `/leadlens:monthly-report [owner/repo] [github-login] [YYYY-MM]` | Monthly report: delivery themes, trend versus the previous month, recurring blockers, coaching signals. Add a GitHub login for a one-person report, useful for one-on-one prep. |
| `/leadlens:quick-review [base-ref] [--fast]` | Fast review of changed files against the guideline, UI/UX, accessibility and security checklists, plus the project's own prettier, eslint, typecheck and tests. |
| `/leadlens:audit [pr\|branch\|base-ref\|path\|feature] [--fix] [--full] [--fast]` | Lead Lens: evidence-based audit of one change with a ship verdict. Report only by default; `--fix` fixes and re-audits. |
| `/leadlens:author-audit <author> [alias ...] [7d\|15d\|30d\|Nd \| since YYYY-MM-DD]` | Code audit of one person's commits in the last N days (default 7) on every remote branch, with the branch each commit was really made on and whether it is in master, development or not merged. |
| `/leadlens:author-audit --branch <name> [--base branch]` | Code audit of one branch against the branch it will merge into, all authors, with the behind-count and a clean-merge check. |

Both `author-audit` modes take `[--lang hinglish]` and `[--repo path|url]`. Review health in both reports follows the same checklist as `quick-review`, aggregate only.

`quick-review` and `audit` can also be invoked by Claude when a request or a project `CLAUDE.md` asks for them; that is how the Lead Lens gate runs as the last step of a task (see below).

## How it works

### Reports

Commits are correlated with PRs, reviews and issues; each delivered item carries a reference, and missing evidence is stated as "Not enough GitHub evidence". Risk flags name the PR and the wait, not the developer. Reports go to `.claude/reports/weekly/` and `.claude/reports/monthly/`.

### Author audit

`author-audit` answers "what did this person commit, anywhere in this repository, and is it safe?" and, with `--branch`, "is this branch ready to merge?". It is written for two readers: a team lead who decides in two minutes, and a developer who fixes things without asking questions. The first three lines give the verdict (Stop, Fix first, Good), the counts and what must happen next; then one block per issue with the problem, why it matters, `file:line`, sha, branch, merge status, a concrete fix and an effort estimate.

Author mode takes one or more aliases (name, login, email), a window as a day count or a start date, and optionally a repository path or URL; a URL is mirror-cloned under `.claude/reports/data/` so the checkout you are in is never touched. The collector fetches all refs, matches by author and by committer on every remote branch, gives each commit one status (in master, in development, not merged), and finds the branches a commit was really made on, never the ones that only received it through a merge. Branches that are copies of each other (`kb_` prefixes, `_v2` suffixes) are reported as one work item.

Branch mode takes a branch name and, optionally, the branch it will merge into (default `development` if it exists, else master). It judges the final code of the branch, lists the commits by author, says how far the branch is behind its base, and whether it merges cleanly.

In both modes the review reads diffs, not messages; merge commits are read only for their conflict fixes; generated and lock files are skipped and said so; secrets are cited by location and never reproduced; anything unread is named in the report's Coverage section. Reports go to `.claude/reports/<scope>.md` (for example `gopal-7d.md` or `branch-feature_x.md`) and the raw data, diffs and exact commands to `.claude/reports/data/<scope>/`.

### Lead Lens audit

`audit` answers "is this change shippable, and what is the evidence?". Point it at a PR number, a branch, a base ref, a path or a feature name, or at nothing to audit the working tree. It runs the project's own gates through `scripts/quick-checks.sh --build`, re-reads the diff including untracked files, searches for every consumer of what changed, and works through the rubric in `references/audit.md`: parity, backend contract, reuse, TypeScript, server state, forms, design system, styling, accessibility, performance, security, tests. Library-specific sections apply when the project uses that library. Findings carry a severity, an *Introduced* or *Pre-existing* tag, `file:line` and a one-line fix. A gate that did not run is shown as not run and blocks SHIP for the files it would have covered.

With `--fix` it becomes a gate: it fixes the Blockers and Majors it introduced, re-runs the gates and re-audits, up to three loops, then reports whatever is left. To make that the last step of every task in a project, paste `templates/CLAUDE.md.snippet` into that project's `CLAUDE.md` and adjust the Stack line. `references/styling-tailwind-scss.md` holds the Tailwind and SCSS module rules both `audit` and `quick-review` apply when a project uses them.

### Browser verification

`quick-review` and the Review health step of both reports open the changed screens when the diff touches anything rendered, including CSS and HTML only changes. It uses the Claude in Chrome extension or the Playwright MCP server, whichever is available, and finds a URL in this order: `baseUrl` from the config, the `dev` script in `package.json`, or a static server for plain HTML and CSS. With no browser tool the step is skipped and the report says so. The Chrome extension's window resize can be ignored by the window manager; then responsive widths are reported as not verified.

### Secrets hook

A `PreToolUse` hook on `Edit|Write` runs `scripts/scan-patterns.sh --hook`. It reads the tool input on stdin, makes no network calls, and blocks the write only for credentials, cloud or payment keys and private key blocks. XSS, accessibility and debug statements are reported by `quick-review`, never blocked.

## Schedule it

Copy `templates/weekly-report.yml` to `.github/workflows/` in the reported repo. It runs Monday 09:15 IST, installs the plugin, collects the previous Monday to Sunday, and publishes the report as a job summary and artifact. Set the `ANTHROPIC_API_KEY` secret and a `LEADLENS_MARKETPLACE` variable pointing at your marketplace repo. For a monthly run, copy it again with cron `0 4 1 * *` and the `/leadlens:monthly-report` command.

## Privacy

- The GitHub collector only reads through your own `gh` login.
- The author-audit collector uses plain `git` and only fetches; it never checks out, resets or pushes. A repository URL is mirror-cloned under `.claude/reports/data/`, never into your checkout.
- Reports and raw data are written locally under `.claude/reports/`.
- The hook reads the tool input on stdin and makes no network calls. Secrets found by review are cited by location and never reproduced.

## Requirements

- Claude Code with plugin support
- `gh`, authenticated with `gh auth login`, and `jq` for the reports
- `git` and `jq` only for `author-audit` (Git 2.38+ gives an exact clean-merge check; older Git gets an approximate one)
- The project's own prettier, eslint, tsc and test script, when present, for `quick-review` and `audit`
- A browser MCP tool (Claude in Chrome or Playwright) for browser verification; skipped otherwise

## Layout

```
leadlens/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   ├── weekly-report/SKILL.md
│   ├── monthly-report/SKILL.md
│   ├── quick-review/SKILL.md
│   ├── audit/SKILL.md
│   └── author-audit/SKILL.md
├── references/
│   ├── analysis-rules.md
│   ├── audit.md
│   ├── author-audit.md
│   ├── report-format.md
│   ├── review-checklist.md
│   ├── security-review.md
│   ├── styling-tailwind-scss.md
│   └── ui-guidelines.md
├── scripts/
│   ├── collect-audit-commits.sh
│   ├── collect-github-activity.sh
│   ├── quick-checks.sh
│   └── scan-patterns.sh
├── hooks/hooks.json
└── templates/
    ├── CLAUDE.md.snippet
    ├── team-report.json
    └── weekly-report.yml
```

## Development

```
claude plugin validate .   # marketplace manifest
```

Skills live in `skills/<name>/SKILL.md`, the rules they apply in `references/`, and the collectors and gates in `scripts/`.

## Uninstall

Run `/plugin uninstall leadlens`. Reports under `.claude/reports/` in your projects stay until you delete them.

## License

MIT. Not affiliated with Anthropic.
