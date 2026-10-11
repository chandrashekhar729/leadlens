---
name: author-audit
description: Code audit report of git work in the current repository, in one of two modes. Author mode reviews one person's commits in the last N days on every remote branch, finds the branch each commit was really made on and whether it is in master. Branch mode reviews one branch against the branch it will merge into, all authors, with behind-count and a clean-merge check. Both read every own commit and write a short plain-English report (Hinglish on request) with a verdict, severity-ranked issues with file:line and a concrete fix, for a TL to decide in two minutes and a developer to act on. Use when asked to audit someone's commits, review everything a person pushed, or audit a branch before merge from git alone. Not the Lead Lens gate (that is audit): no typecheck, tests or build run here.
argument-hint: "<author> [alias ...] [7d|15d|30d|Nd | since YYYY-MM-DD]  |  --branch <name> [--base <branch>]   then [--lang hinglish] [--repo path|url] [--master branch] [--dev branch]"
disable-model-invocation: true
effort: high
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-audit-commits.sh *) Bash(jq *) Bash(git show *) Bash(git log *) Bash(git diff *) Bash(git branch *) Bash(date *) Read Write Edit Grep Glob
---

# Code audit report

Audit git work in this repository and write a short, clear report. Two modes:

- **author**: one person's commits in the last N days, on any remote branch.
- **branch**: one branch compared with the branch it will merge into, all
  authors.

Nothing here is limited to the current branch, and nothing checks out or
switches branches: every commit is read from the object store with
`git show`.

## 1. Parse arguments

`$ARGUMENTS` holds space-separated tokens; a quoted string is one token.

- `--branch <name>` selects branch mode. Everything else is author mode.
- `--base`, `--repo`, `--master`, `--dev`, `--lang`, `--days` take the next
  token. A bare `hinglish` token also sets LANGUAGE. LANGUAGE defaults to
  simple English.
- Author mode only:
  - A token matching `<N>d` (`7d`, `15d`, `30d`, any positive whole number) is
    DAYS. `since YYYY-MM-DD` (two tokens) or a bare `YYYY-MM-DD` is SINCE. Both
    given: stop and ask which one is meant. Neither: DAYS is 7.
  - Every other token is an author alias: a name, a login or an email. The
    first one names the report. None given: ask for it and stop.
- Branch mode only: `--base` names the branch it will merge into. Without it
  the collector picks `development` (or `develop`) if it exists, else master.
  A `days` or `since` token in branch mode is an error; say so and stop.

State the resolved inputs in one line: mode, aliases or branch and base,
window, language, repo.

## 2. Collect

Run once:

```
author:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-audit-commits.sh --author "<alias>" [--author "<alias>"]... [--days <DAYS> | --since <SINCE>] [--repo <repo>] [--master <b>] [--dev <b>]
branch:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-audit-commits.sh --branch <name> [--base <branch>] [--repo <repo>] [--master <b>] [--dev <b>]
```

Pass DAYS as given (`7d` and `7` both work); the script computes the date.
It fetches all refs with `--prune --tags`, works from remote branches only,
gives every commit one status in this order (In master, In development when
that branch exists, Not merged), writes one diff per commit, the conflict
fixes of each merge commit, and in branch mode the three-dot diff, the
behind/ahead counts and a clean-merge check. In author mode it also finds the
**home branches** of each commit: the branches where the commit was really
made, not the ones that only received it by merging another branch. It saves
everything under `.claude/reports/data/<scope>/` (`inventory.json`,
`commits.csv`, `commands.txt`, `diffs/`) and prints the path of
`inventory.json`.

If it exits non-zero, show the error and stop. Do not audit from partial data.

Read `inventory.json` with `jq`, not whole: first `del(.commits, .commands)`,
then commits in slices of about 20 with
`.commits[0:20] | map(del(.files))`. Carry these into the report's Coverage
section when present:

- `fetched: false` with `fetch_error`: remote refs may be out of date.
- `shallow: true`: history is truncated; older commits cannot be seen.
- `unreadable`: commits whose metadata or diff could not be read.
- `ref_only` on a commit: "local branch only, not pushed" (name the local
  branch from `local_branches_only`) or "tag/stash only".
- `author_ne_committer` on a commit: made by one person, committed by another.
- Branch mode `clean_merge.checked: false`: write "Clean merge: not checked".

## 3. Shape the work

Author mode: group the `home_branches` entries into work items. Branches are
one work item if they share most of their `own_shas`, or if their names differ
only by a prefix or suffix (`kb_`, `_v2`, `_d`, `_m`, `_updated_two`). Name
each work item in plain words from the commit messages and ticket ids. A
commit whose only home branch is master or development is its own row. Merge
commits are not own work: they get one line under the table.

Branch mode: group `branch_diff.files` into 3 to 6 areas (a folder, a screen,
a module) for the "What this branch does" table.

## 4. Review

Read `${CLAUDE_PLUGIN_ROOT}/references/author-audit.md` once, before the
first diff: it holds what to look for, the severity scale, the verdict rules,
the writing rules and the report shape. Read the repository's own rules first
as `${CLAUDE_PLUGIN_ROOT}/references/review-checklist.md` section 1
describes: linter and formatter config, `CONTRIBUTING.md`, `CLAUDE.md`. Those
decide what "convention" means here; cite only a convention you can point to.

Each commit carries a `review` value. Read every commit marked `read` or
`read: ...` by its `diff_path`, in sections when it is long. A merge commit's
file holds only its conflict fixes; review those and nothing else. Commits
marked `skip: ...` are not read; the reason goes into Coverage. If you depart
from a `review` value (you could not read a commit, or you read one marked
skip), change that cell in `commits.csv` with Edit so the data folder matches
the report.

Author mode: review the code in each commit. Before reporting a problem from
an older commit, run `git show <ref_prefix><home branch>:<path>` (the
`ref_prefix` from the inventory, usually `origin/`) and check the latest code;
if it is already fixed, drop it. When the inventory's `repo` is not the
working directory (a `--repo` path or URL), skip this check, keep the issue,
and add "latest code not checked, audited from a mirror" to Coverage.

Branch mode: judge the final code in `diffs/branch.diff`, not each commit.
Use the per-commit diffs only to find the sha for the Where line.

A `pattern_hits` entry is a lead: confirm it in the diff or drop it. Record
findings as you go with sha, branch, status and `file:line`, grouped by file,
so the same problem in several places becomes one issue with all locations.

When more than about 40 commits are marked for reading, work in rounds of 15
to 20, in this order: Not merged first, then `pattern_hits` present, then
largest `insertions + deletions`, then the rest, newest first. Write the
report after every round with the unread commits listed in Coverage as
"not read yet", and continue until nothing is left.

## 5. Write, check, save

Write the report in the exact shape given in `author-audit.md`, in the
LANGUAGE asked for. Run its "Check before saving" list and fix what it finds.
Save at the `report_path` the inventory gives (`.claude/reports/<scope>.md`),
then print the Verdict section in the conversation with the saved path.

## Standing rules

These apply to every turn of this task, not only the first:

- Never limit the analysis to the current branch, and never `checkout`,
  `switch`, `reset` or `stash`. Reading is `git show`, `git log` and
  `git diff` only.
- Never reproduce a credential, token, key or password in the report or in the
  conversation, even partially. Write `<redacted>` and cite sha and
  `file:line`. The plugin's own secret-scan hook blocks a write that contains
  one, and the report must pass it.
- Report only what the diffs show. Anything uncertain goes under "Needs a
  human check", never under issues.
- Every issue cites sha, branch and `file:line`. An issue without a location
  is dropped.
- Describe risks in plain words. No exploit code or proof-of-concept attacks.
- Judge the code, not the person. Author mode never compares with teammates
  or counts activity as merit.
- Nothing is skipped silently: every unread, unreadable or unfetched item is
  named in Coverage.
- Do not modify application code or any file outside `.claude/reports/`.
