# Author audit: rubric and report format

Used by `author-audit`. The shared rules in `security-review.md` apply as well;
this file adds what a full-history audit needs beyond a single pre-merge diff.

## Security rubric

Check every reviewed diff for at least:

- **Secrets**: API keys, tokens, passwords, private keys, connection strings, `.env` values in tracked files. A secret that was later removed is still a finding: it is in history.
- **Injection**: SQL/NoSQL, shell command, LDAP, template, path traversal, header injection. String concatenation or interpolation of user-controlled data into any of these.
- **AuthN/AuthZ**: missing checks where siblings have one, broken access control, IDOR, privilege escalation, authorisation decided only in the UI.
- **Input validation and output encoding**: XSS, CSRF, SSRF, open redirects, unvalidated file names or MIME types.
- **Crypto misuse**: MD5/SHA-1 for passwords, custom crypto, hardcoded IV or salt, `Math.random` or `random` for anything security-relevant, ECB mode.
- **Sensitive data**: PII, tokens or stack traces in logs, error messages or API responses.
- **Dependencies**: new or upgraded packages, unpinned or wildcard versions, packages with names close to well-known ones, lockfile drift. Known CVEs only when the diff gives a version you can name; otherwise "needs manual verification".
- **Insecure config**: debug mode on, permissive CORS, TLS verification off, `0.0.0.0` binds, world-writable permissions, default credentials.
- **Dangerous operations**: file upload without type and size limits, deserialisation of untrusted data, `eval`, `new Function`, `pickle.loads`, `yaml.load` without a safe loader.

## Code-standards rubric

- **Style conformance**: against the repository's own linter, formatter and editorconfig settings, read from the files. Name the config rule when one applies.
- **Naming and structure**: inconsistent naming, function or class size, cyclomatic complexity, duplication, dead code.
- **Error handling**: swallowed exceptions, generic catches, missing cleanup, errors turned into silent defaults.
- **Logging**: wrong levels, noisy logs, missing context where an operation can fail.
- **Tests**: changed code without tests, skipped or disabled tests, tests deleted in the same commit as the code they covered.
- **Documentation and contracts**: public API changes without docs, breaking changes without a migration note, backward compatibility.
- **Commit hygiene**: message quality, mixed-concern commits, commits too large to review, debug and commented-out code left behind, force-push artefacts (the same change in several shas).

## Severity

- **Critical**: exploitable now or secret exposed; fix before anything else.
- **High**: real security weakness or data exposure that needs one more condition to exploit; correctness bug on a main path.
- **Medium**: weakness in defence in depth, missing validation on an internal path, error handling that hides failures.
- **Low**: style, hygiene, documentation, minor duplication.

Code-standards findings are Medium at most unless they hide a correctness or security problem.

## Report format

Write the report exactly in this shape. Keep each table row to one line.

```markdown
# Author Audit: <display name> in <repo>

## 1. Summary

- Author aliases: <list>
- Repository: <path or URL>  ·  Default branch: <name>
- Window: <all history | since YYYY-MM-DD>  ·  Generated: <YYYY-MM-DD>
- Branches scanned: <n> (<local> local, <remote> remote)  ·  Branches with this author's commits: <n>
- Unique commits: <n>  ·  Merged into default: <n>  ·  Only on other branches: <n>  ·  Author ≠ committer: <n>
- Files touched: <n>
- Findings: Critical <n> · High <n> · Medium <n> · Low <n>
- Diffs reviewed: <n> of <n>  (see Appendix for the rest)

Two or three sentences a TL can act on: the most important risks and whether the work is mostly merged or stranded on branches.

## 2. Branch coverage

| Branch | Commits by author | Last commit | Merged into default | Stale (> <stale_days> days) |
|---|---|---|---|---|
| origin/feature-x | 12 | 2026-09-30 | no | no |

## 3. Commit inventory

One row per unique commit, newest first. Risk flag: 🔴 Critical/High finding · 🟡 Medium/Low · ⚪ none · ⏭ not reviewed · ⏳ not scanned.

| Sha | Date | Branch(es) | Message | Files | Risk |
|---|---|---|---|---|---|
| abc1234 | 2026-09-30 | origin/feature-x | Add export endpoint | 4 (+120/−8) | 🔴 |

Commits where author ≠ committer, or reachable only from a tag or stash, get a note under the table.

## 4. Security findings

Ordered by severity. Each:

### [Critical] <one-line title>
- Commit: `abc1234` on `origin/feature-x` (merged: no)
- Location: `path/file.ext:42`
- What: what the diff does
- Impact: what can go wrong, in plain words
- Fix: one concrete change

## 5. Code-standard findings

Grouped by rubric category. Each entry: `sha` · `file:line` · what · fix. Cite the repository config rule when one backs the finding.

## 6. Recurring patterns

Problems seen in more than one commit or branch, each with the list of citations and what convention would prevent it.

## 7. Prioritised action list

| # | Action | Fixes | Effort |
|---|---|---|---|
| 1 | Rotate and remove the key in `path:line` | Critical #1 | S |

Effort: S under an hour, M under a day, L more.

## 8. Appendix

- Commands used: the `commands` list from the inventory, verbatim.
- Fetch status, shallow clone, default branch resolution.
- Not reviewed: sha · reason (merge commit, lockfile only, generated, formatting-only).
- Not scanned: sha · reason (round not reached, diff unreadable, branch not fetched).
- Needs manual verification: items whose evidence is outside the diffs.
```
