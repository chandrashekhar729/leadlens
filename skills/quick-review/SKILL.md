---
name: quick-review
description: Fast pre-merge review of a branch or PR — project guidelines, styling tokens, UI/UX, accessibility, defensive security, plus best-effort browser verification of changed screens. Use when asked to review a change, check a PR before merge, or sanity-check work in progress. For a full evidence-based audit with gates, a blast-radius trace and a ship verdict, use audit instead.
argument-hint: "[base-ref] [--fast]"
arguments: base
context: fork
effort: medium
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh *) Bash(git diff *) Bash(git log *) Bash(git status *) Bash(npm *) Bash(pnpm *) Bash(yarn *) Bash(curl *) Bash(kill *) Bash(python3 -m http.server *) Read Grep Glob mcp__claude-in-chrome mcp__plugin_playwright_playwright
---

# Quick Review

Review the current diff the way a tech lead would before approving a merge.
Review only what changed; do not read or comment on untouched files.
Report findings; do not fix anything unless asked. This is the fast pass; a
request for an "audit", a "Lead Lens" or a ship verdict is the `audit` skill.

## 0. Run the checks

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/quick-checks.sh --base ${base:-HEAD}
```

If `$base` is empty, omit `--base` so uncommitted changes are reviewed. Add
`--fast` if the caller asked for a fast pass. A `timed_out: true` result is
reported as "check did not finish", never as a pass. A `skipped: true` result
means the tool is not installed in this project; say so.

Then read the diff:

```
git diff <base or nothing> -- <changed files from the JSON>
```

A pattern-scan hit is a lead, not a verdict. Confirm it in the diff before
reporting it, and drop it if it is a false positive.

## 1–6. Apply the shared checklist

Read `${CLAUDE_PLUGIN_ROOT}/references/review-checklist.md` and work through
its six sections in order on the diff: project rules, styling tokens, code and
architecture, defensive security, accessibility, then the gated browser
verification. In this skill you are in quick-review mode: every finding
carries `file:line`, and the browser pass includes the primary interaction and
the tab-through. Nothing in the browser section produces a blocker on its own.

## 7. Output

```
VERDICT: approve | approve with comments | changes requested

Guidelines applied: <sources, or "none found">
Browser checks: <routes verified | not applicable | skipped: reason>
Checks: prettier ✅ · eslint ❌ 3 · typecheck ✅ · tests ⏱ did not finish · patterns 🟡 2

BLOCKERS

path/file.tsx:42 — what's wrong, why it matters, what to do instead

SHOULD FIX

...

NITS

...

Verified working

<interactions and screens that behaved correctly>

Not checked

<what you did not check and why>
```

Order findings by severity, not by file. Every item gets `file:line`, a
concrete fix and an *Introduced* or *Pre-existing* tag; no finding without a
location. "Verified working" lists only what you observed or ran, with the
evidence; a check you did not run belongs under "Not checked". Cite the guideline or token name
when one backs the finding. Suggest the fix in one line; do not rewrite the
file. Blocking means it breaks users, leaks data, or fails a stated project
rule; style preference is never blocking. Keep the whole report under roughly
400 lines; if there are more nits than that, group them.
