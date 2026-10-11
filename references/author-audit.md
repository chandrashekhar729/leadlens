# Code audit report: rubric, severity, verdict and report shape

Used by `author-audit` in both modes. The shared security checklist in
`security-review.md` applies as well; this file holds what the audit report
needs beyond it: what to look for, how to grade it, and the exact shape of the
report.

The report has two readers: a team lead who must decide in 2 minutes, and the
developer who must fix things without asking questions.

## What to look for

Read the code that changed, not the commit message. Every issue points to a
`file:line` you actually read; the line number is in the file after that
commit. If you cannot confirm it in the diff, it goes under "Needs a human
check" in Coverage, never under issues.

- **Security**
  - SQL or HTML built from request, DB or OS values without parameters or
    escaping.
  - Secrets in code: keys, tokens, passwords, connection strings. A secret that
    was later removed is still a finding; it is in history.
  - `eval`, `new Function`, shell calls or `pickle`/`yaml.load` with input.
  - `postMessage(..., '*')`.
  - Missing permission checks where sibling routes, handlers or actions have
    one; authorisation decided only in the UI.
- **Bugs**: wrong logic, unhandled null or empty values, queries that can
  return duplicate rows, behaviour changes nobody mentioned in the commit.
- **Error handling**: empty `catch`, `console.log` as the only handling,
  unguarded `JSON.parse`, failures the user never sees.
- **Performance**: queries inside loops, heavy work repeated on every render.
- **Maintainability**: very long functions or files, copy-paste, leftover
  debug code.
- **Conventions**: compare with how the same file or folder already does it.
  Only cite a convention you can point to (a sibling file, a linter rule,
  `CONTRIBUTING.md`, `CLAUDE.md`).
- **Commit habits** (author mode only): huge commits, vague messages, no
  ticket id. These go under "Habits to improve", not under issues, unless a
  commit is too large to review at all.

Skip trivia: typos in commit messages, comment language, whitespace.

Generated or binary files (compiled CSS like `main.css`, minified files,
`.sqlite`, lock files): do not review line by line. Note them in Coverage.

### Fairness

- If a bad pattern already existed and the author only added more of it, keep
  the issue and add "(existing pattern)".
- Repo-wide habits the author did not start (for example committing
  `main.css`) go under Team-level, not against the author.
- The same fix needed in many places is one issue listing all locations.
- Author mode: before reporting a problem from an older commit, check the
  latest code on that branch with `git show origin/<branch>:<path>`. If it is
  already fixed, do not report it.
- Branch mode: judge the final code (the three-dot diff), not each commit.

## Severity

| Level | Meaning | Action |
|---|---|---|
| 🔴 Critical | Data leak, money or data loss, or an open security hole, right now | Fix today |
| 🟠 High | Likely to break a user flow, or a security hole that is easy to use | Fix before merge |
| 🟡 Medium | Real problem, but needs special conditions or has limited impact | Fix before merge, or a ticket with owner and date |
| 🔵 Low | Code quality or future risk | Fix next time the file is touched |

An issue already in master is more urgent than the same issue on an unmerged
branch. Convention and habit findings are Low unless they hide a bug.

## Verdict

- 🔴 **Stop**: any Critical, or any High already in master.
- 🟡 **Fix first**: any High or Medium.
- 🟢 **Good**: only Low, or nothing.

## Writing rules

1. Answer first. The first 3 lines give the result. Everything above "Issues
   to fix" fits on one screen.
2. Simple English: sentences under 20 words, one idea each, everyday words.
   If LANGUAGE is `hinglish`, write the explanations in Hinglish (Roman
   script). Keep code, file names, headings and severity labels in English.
3. No git jargon. Never write: reachable, ancestor, merge-base, first-parent,
   combined diff, hunk, refs, author ≠ committer. Write "in master", "not
   merged", "only on branch X", "merge commit".
4. One number per fact. Never show two versions of a count. Statuses are
   checked against the remote branches only; never report a second count
   against local branches.
5. Each issue appears exactly once. No patterns list or action list that
   repeats issues.
6. Report problems, not clean checks. All clean checks share one line in
   Coverage. Mention a commit made by one person and committed by another, or
   a commit found only in a tag or stash, only if there is one.
7. Every fix is concrete: what to change and where. Add a one-line code
   example if it helps.
8. Leave these out; the data folder holds them: a commit-by-commit table, a
   list of every branch, any table over 8 rows, a description of the method.
9. Formatting: short SHAs exactly as `%h` prints them, dates like "8 Oct",
   code names in backticks. No emoji except the severity and verdict markers.
10. Neutral tone. Describe the code, not the person.
11. Secrets: never reproduce one, even partially. Write `<redacted>` and cite
    sha and `file:line`. The plugin's secret-scan hook blocks a report that
    contains one.
12. Branch names: write the name the developer uses (`feature_x_v2`), not
    `origin/feature_x_v2`. "In master" uses the repository's own name for that
    branch (`In main` when the repository uses `main`).

## Report structure

Follow it exactly. Skip only the sections marked optional. Lines marked
"author mode" or "branch mode" appear only in that mode; do not print the
markers.

~~~
# Audit: <Author> · last <N> days (<start>–<end>)        ← author mode
# Audit: `<branch>` → `<base>` · <date>                   ← branch mode

## Verdict
<🔴/🟡/🟢> <One-sentence result.> <One sentence: what must happen next.>
Own commits: <n> (<x> in master, <y> in development, <z> not merged) · Issues: <a> 🔴 · <b> 🟠 · <c> 🟡 · <d> 🔵   ← author mode
<n> commits by <names> · <k> behind base · Clean merge: <yes / no: files / not checked> · Issues: <same format>   ← branch mode

## What was worked on              ← author mode
| Work | Branch or commit | Status | Own commits | Issues |
Max 6 rows. If part of a work item is in master and part is not, use two rows.
Merge commits get one line under the table, not rows.

## What this branch does            ← branch mode
2–3 plain sentences: what changes for the user. Then:
| Area | Files | Lines +/- | Issues |

## Issues to fix
Medium and above get one block each. Order: severity, then in master before not merged.

### 1. 🟡 Medium · <Category> · <Short plain title>
**Problem:** <1–2 plain sentences>
**Why it matters:** <1 sentence: what can go wrong, for whom>
**Where:** `<file>:<line>` · `<sha>` · `<branch>` · <In master / In development / Not merged>
**Fix:** <concrete change>
**Effort:** <Small (under 1 hour) / Medium (half a day) / Large (1+ days)> · **When:** <Today / Before merge / Next release / Next time the file is touched>

### Small issues (🔵 Low)
| # | Problem | Where | Fix |
(numbering continues from the blocks above)

## Good work                        ← optional; skip if nothing specific
2–3 specific things done well, each with a SHA.

## Habits to improve                ← author mode only, max 3
<Habit> (<example sha>). <What to do instead.>

## Team-level                       ← optional
Repo-wide problems seen, not caused by this author or branch.

## Coverage
- Reviewed <x> of <y> own commits. Skipped: <what and why>.
- Needs a human check: <items, or "none">
- Checked, nothing found: <one line, e.g. secrets, new dependencies, new network calls>
- Data as of <date time>. Raw data and commands: `.claude/reports/data/<scope>/`
~~~

The author-mode count line drops "<y> in development" when the repository
has no development branch. Branch-mode "Clean merge" is "not checked" when
the collector could not run the check; never write "yes" for a check that did
not run. When `clean_merge.method` is the Git < 2.38 fallback, write
"yes (content conflicts only)". A branch-mode Where line names the branch
being audited.

When the review runs in rounds, the Coverage section of each saved report
lists the commits not yet read under "Skipped" with the reason "not read yet",
so the file on disk is always complete about its own gaps.

## Example of a good top section

Format and tone only; never copy its content.

~~~
# Audit: Gopal J · last 7 days (2–9 Oct 2026)

## Verdict
🟡 Fix first. Code already in master is fine; it has only small issues.
The new printer screen (not merged) needs 3 fixes before a PR is opened.
Own commits: 6 (4 in master, 2 not merged) · Issues: 0 🔴 · 0 🟠 · 3 🟡 · 9 🔵

## What was worked on
| Work | Branch or commit | Status | Own commits | Issues |
|---|---|---|---|---|
| New Add/Edit Printer screen | `driverless_printing_new_design_v5` (+4 older copies) | Not merged | 2 | 3 🟡 · 6 🔵 |
| Support panel changes | `9e7a339d7f` | In master | 1 | 2 🔵 |
| Dual-screen display options | `81d9bcf3fc` | In master | 1 | 1 🔵 |
| Report icon fix (PLAT-26247), DineIn QR text | `4108b51ef0`, `00e58fcc1c` | In master | 2 | none |
Also 4 merge commits (pulling `development` into branches), with no own changes.

## Issues to fix
### 1. 🟡 Medium · Security · Printer names go into the page without escaping
**Problem:** The printer form builds HTML by joining raw printer names into strings. A name with `"` or `<` breaks the form and can run script.
**Why it matters:** This window can read and write files, so injected script could do real harm. It needs a crafted printer or display name, so the risk is limited.
**Where:** `public/js/common/printer_designer.js:669, 675` · `ede1d0721f` · `driverless_printing_new_design_v5` · Not merged
**Fix:** Build options with `$('<option>').val(name).text(name)`, or pass every value through one `escape_html()` helper.
**Effort:** Small (under 1 hour) · **When:** Before merge
~~~

## Check before saving

- Do the first 3 lines give the result?
- Does every issue have a `file:line`, a plain problem, why it matters, and a
  concrete fix?
- Is any issue written twice? Delete the copy.
- Do the Verdict counts match the issues listed?
- Any banned jargon, any sentence over 25 words, any table over 8 rows? Fix
  it.
- Any secret, even partial? Replace it with `<redacted>`.
