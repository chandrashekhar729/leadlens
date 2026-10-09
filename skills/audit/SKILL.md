---
name: audit
description: Lead Lens evidence-based audit of ONE change (a PR, branch, base ref, path or feature) with real gates (typecheck, lint, stylelint, tests, build), a blast-radius trace, a break-it pass and a ship verdict (SHIP, SHIP WITH NOTES, FIX FIRST, NEEDS INPUT). Report only by default; --fix turns it into the gate that fixes Blockers and Majors and re-audits. Use when asked to "audit", "Lead Lens" or "is this shippable" for a change, or as the last step of a task when the project's CLAUDE.md says so. Not for one person's commits across branches (that is author-audit) and heavier than quick-review.
argument-hint: "[pr-number|branch|base-ref|path|feature] [--fix] [--full] [--fast]"
effort: high
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh *) Bash(git diff *) Bash(git log *) Bash(git status *) Bash(git ls-files *) Bash(gh pr *) Bash(npm *) Bash(pnpm *) Bash(yarn *) Bash(npx *) Bash(curl *) Bash(kill *) Bash(python3 -m http.server *) Read Edit Write Grep Glob mcp__claude-in-chrome mcp__plugin_playwright_playwright
---

# Lead Lens audit

Read `${CLAUDE_PLUGIN_ROOT}/references/audit.md` first and keep it open: it
holds the iron rules, the severity scale, the break-it list, the checklist,
the verdict rules and the report shape. This file only says how to drive it.

## 1. Resolve scope and mode

`$ARGUMENTS` holds space-separated tokens.

- `--fix` selects **Gate mode**: fix every Blocker and Major you find, re-run
  the gates, re-audit, at most 3 loops. Without it you are in **Audit mode**:
  report only, change no file.
- `--full` widens an Audit to the whole feature the change belongs to,
  including legacy parity. `--fast` passes through to the checks script and
  skips typecheck, tests and build; say so in the Gates line, those gates are
  then `⚪ not run: --fast`.
- A number is a PR: `gh pr view <n> --json baseRefName,headRefName,files,url`
  gives the base and the files. The gates and the diff run on the checked-out
  tree, so compare `git rev-parse --abbrev-ref HEAD` with `headRefName`; if
  they differ, say so and stop with `NEEDS INPUT` asking for that branch to be
  checked out. Never check it out yourself. A ref that `git rev-parse
  --verify` accepts is the base. A path narrows the audit to that path. Anything else is a feature
  name: find the files with Grep and Glob and list them before you start.
- No target: audit the working tree (unstaged, staged and untracked) against
  `HEAD`. This is what a project `CLAUDE.md` gate normally wants.

State the resolved scope and mode in one line before doing anything else.

## 2. Run the gates

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh [--base <base>] [--fast] --build
```

Omit `--base` for the working tree so untracked files are included. The JSON
lists every check with `exit_code`, `timed_out`, `skipped` and `output`.
`timed_out` or `skipped` is `⚪ not run` with the reason from `output`, never
green. In a monorepo the root scripts may not cover the changed package: when
the changed files sit under a workspace with its own `package.json`, also run
that workspace's `typecheck`, `lint`, `test` and `build` scripts there and
report both.

Then read the diff in full, including untracked files, as iron rule 2 says.
Do not judge from the file list or from memory of writing the code.

## 3. Audit

Work through `audit.md` in order: blast radius, break-it list, the twelve
checklist sections, then the browser pass as `review-checklist.md` section 6
describes. Read the project's own rules first, as section 1 of
`${CLAUDE_PLUGIN_ROOT}/references/review-checklist.md` describes; they win
over the plugin's checklists.

Every PASS gets its evidence in the Verified section at the moment you check
it, not reconstructed at the end. Anything you could not check goes to
UNVERIFIED with what would be needed. A pattern-scan hit is a lead: confirm it
in the diff or drop it.

## 4. Gate mode loop

Only with `--fix`. For each loop:

1. Fix every Blocker and Major that is *Introduced* by this change, smallest
   change that resolves it, following the project's conventions. A
   *Pre-existing* finding is fixed only when the task's scope already covers
   that code; otherwise it stays in Findings.
2. Re-run step 2 and re-audit the files you touched.
3. Stop when no Blocker or Major remains, or after the third loop.

Never change the backend contract, add a dependency or widen the diff to fix a
finding; that is a `NEEDS INPUT` verdict instead.

## 5. Report

Print the report in exactly the shape given in `audit.md`, in the
conversation. Do not write it to a file unless asked. In Gate mode the task is
not done until the verdict is `SHIP` or `SHIP WITH NOTES`; if it is still
`FIX FIRST` after three loops, say so plainly and list what is left.

## Standing rules

- Audit mode changes nothing outside the session scratchpad. Gate mode
  changes only application code the task already touches and never files under
  `.claude/reports/`.
- Never reproduce a credential, token or key in the report, even partially:
  write `<redacted>` and cite `file:line`.
- Describe risks in plain words. No exploit code or proof-of-concept attacks.
- Stop any dev server this audit started before reporting.
- Judge the code, not the author.
