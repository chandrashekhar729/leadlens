---
name: quick-review
description: Fast pre-merge review of changed files. Project guidelines, UI/UX and accessibility, and a defensive security pass. Use when asked to review a change, check a PR before merge, or sanity-check work in progress.
argument-hint: "[base-ref] [--fast]"
arguments: base
context: fork
effort: medium
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh *) Bash(git diff *) Bash(git log *) Bash(git status *) Read Grep Glob
---

# Quick review

Review only what changed. Do not read or comment on untouched files.

## 1. Run the checks

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh --base ${base:-HEAD}
```

If `$base` is empty, omit `--base` so uncommitted changes are reviewed. Add `--fast` if the caller asked for a fast pass. A `timed_out: true` result is reported as "check did not finish", never as a pass. A `skipped: true` result means the tool is not installed in this project; say so.

## 2. Read the diff

```
git diff <base or nothing> -- <changed files from the JSON>
```

## 3. Apply the checklists

- `${CLAUDE_PLUGIN_ROOT}/references/ui-guidelines.md`
- `${CLAUDE_PLUGIN_ROOT}/references/security-review.md`
- The project's own `CLAUDE.md` and any `.claude/rules/*.md`, if present. Project rules win over the checklists above when they conflict.

## 4. Report

```
Quick review: <n> files, <duration>s

🔴 Blocking (<n>)
<file>:<line>  <what>  →  <the fix>

🟡 Should fix (<n>)
...

🔵 Worth considering (<n>)
...

✅ Clean
<which checklist areas came back with nothing>

Checks
prettier ✅ · eslint ❌ 3 · typecheck ✅ · tests ⏱ did not finish · patterns 🟡 2
```

## Standing rules

- Blocking means it breaks users, leaks data, or fails a stated project rule. Style preference is never blocking.
- Every finding carries file and line. No finding without a location.
- A pattern-scan hit is a lead, not a verdict. Confirm it in the diff before reporting it, and drop it if it is a false positive.
- Suggest the fix in one line. Do not rewrite the file.
- Say what you did not check and why.
