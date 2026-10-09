---
name: author-audit
description: Full-repository audit of every commit by one author across ALL branches, local and remote, never only the checked-out one. Branch coverage, de-duplicated commit inventory, diff-level security and code-standards review, consolidated Markdown report. Use when asked to audit someone's commits, review everything a person pushed, or check an author's work across branches.
argument-hint: "<author-or-email> [alias|email ...] [7d|15d|30d|Nd | since YYYY-MM-DD] [--repo path|url] [--default branch] [--stale-days N]"
disable-model-invocation: true
effort: high
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-author-commits.sh *) Bash(jq *) Bash(git show *) Bash(git log *) Bash(git branch *) Bash(git diff *) Bash(git for-each-ref *) Bash(date *) Read Write Grep Glob
---

# Author Audit

Audit everything one person committed, on every branch of the repository.
Nothing here is limited to the current branch, and nothing checks out or
switches branches: every commit is read from the object store with
`git show`.

## 1. Parse arguments

`$ARGUMENTS` holds space-separated tokens; a quoted string is one token.

- `--repo <path|url>`, `--default <branch>`, `--stale-days <n>` take the next token.
- A token matching `<N>d` (`7d`, `15d`, `30d`, any positive whole number) or
  `--days <N>` is DAYS: the window is the last N days, counted from midnight N
  days ago. Pass the token to the collector as-is (`--days 7d` and `--days 7`
  both work); it computes the date, so do not compute it yourself.
- A token matching `YYYY-MM-DD` is SINCE. If both DAYS and SINCE are given,
  stop and ask which one is meant.
- Without either the window is all history.
- Every other token is an author alias: a name, a login or an email. The first
  one names the report. At least one is required; if none, ask for it and stop.

State the resolved inputs in one line: aliases, window (`last N days`, `since
YYYY-MM-DD` or `all history`), repo, default branch.

## 2. Collect

Run once, with one `--author` per alias:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-author-commits.sh --author "<alias>" [--author "<alias>"]... [--days <DAYS> | --since <SINCE>] [--repo <repo>] [--default <branch>] [--stale-days <n>]
```

It fetches all refs, lists every local and remote branch, finds the commits by
author and by committer across `--all` refs (case-insensitive, fixed-string
match on every alias), maps each commit to the branches that contain it, marks
which are merged into the default branch, writes one diff per commit, runs the
pattern scan on the added lines, and prints the path of `inventory.json`.

If it exits non-zero, show the error and stop. Do not audit from partial data.

Read `inventory.json` with `jq`, not whole: first everything except `commits`
and `branches`, then `branches`, then commits in slices of about 20 with
`.commits[0:20] | map(del(.files))`. Check these fields before going on and
carry each into the Appendix:

- `fetched: false` with `fetch_error`: remote refs may be out of date.
- `shallow: true`: history is truncated; older commits cannot be seen.
- `unreadable`: commits whose metadata or diff could not be read.
- `ref_only: "tag/stash only"`: a commit reachable from no branch.

## 3. Choose what to read

Every unique commit is in the inventory. Read the diff of every one of them
unless it is a merge commit with no conflict resolution, or touches only
lockfiles, generated, minified or vendored files, or is formatting-only. List
each such commit under "Not reviewed" with the reason; never drop it silently.

When more than about 40 commits remain, work in rounds of 15 to 20 diffs, in
this order: not merged into the default branch, then `pattern_hits` present,
then `author_ne_committer`, then largest `insertions + deletions`, then the
rest, newest first. Write the report after the inventory and again after every
round, with the unread commits listed under "Not scanned", so a report on disk
is always complete about its own gaps. Continue until nothing is left.

## 4. Review each diff

Read `${CLAUDE_PLUGIN_ROOT}/references/author-audit.md` once, before the first
diff, for the security rubric, the code-standards rubric, the severity scale
and the report template. Read the repository's own rules first as
`${CLAUDE_PLUGIN_ROOT}/references/review-checklist.md` section 1 describes:
linter and formatter config, `CONTRIBUTING.md`, `CLAUDE.md`. Those decide what
"standard" means here; do not assume a style guide.

Read each diff by its `diff_path`, in sections when it is long. Review the
code that changed, not the commit message. A `pattern_hits` entry is a lead:
confirm it in the diff or drop it. Record findings as you go, grouped by file
and by module, so the same problem in several commits becomes one pattern
entry with many citations.

Every finding carries the short sha, the branch or branches, `file:line`
where the line number is in the file after that commit, why it matters, and a
one-line fix. If the diff shows something that looks wrong but the evidence is
not in the diff itself, mark it "needs manual verification" instead of
asserting it.

## 5. Write

Produce the report in the exact shape given in `author-audit.md`, save it to
`.claude/reports/audit/<slug>-<window>.md` where `<window>` is `<N>d` for a
day count, the SINCE date, or `all`, and `<slug>` is the first alias in
lowercase with non-alphanumerics replaced by `-`, then print the
**Summary** and **Prioritised action list** sections in the conversation with
the saved path.

## Standing rules

These apply to every turn of this task, not only the first:

- Never limit the analysis to the current branch, and never `checkout`,
  `switch`, `reset` or `stash`. Reading is `git show` and `git log` only.
- Never reproduce a credential, token, key or password in the report or in the
  conversation, even partially. Write `<redacted>` and cite sha and
  `file:line`. The plugin's own secret-scan hook blocks a write that contains
  one, and the report must pass it.
- Report only what the diffs show. No speculative findings; anything
  uncertain is "needs manual verification".
- Every finding cites sha + file + line. A finding without a location is
  dropped.
- Describe risks in plain words. No exploit code or proof-of-concept attacks.
- This is one person's work: judge the code, not the person. Do not compare
  with teammates, mention other authors' commits, or count activity as merit.
- If a branch could not be fetched or a commit could not be read, the report
  says so in the Appendix. Nothing is skipped silently.
- Do not modify application code or any file outside `.claude/reports/`.
