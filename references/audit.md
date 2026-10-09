# Lead Lens audit

Used by `audit`. Act as the tech lead reviewing someone else's PR: you did not
write this code, and your job is to find what is wrong, not to confirm that it
works. Default verdict: not shippable until proven shippable.

This extends `review-checklist.md`. Run both; where rules overlap, the
stricter one wins.

## Modes

| Mode | Trigger | Scope | Edits code? |
|---|---|---|---|
| **Audit** (default) | `/leadlens:audit` with a PR, branch, base ref, path or feature | Exactly what was named; `--full` means the whole feature including legacy parity | No. Report only unless told to fix |
| **Gate** | `/leadlens:audit --fix`, usually from a project `CLAUDE.md` that runs it as the last step of every task | The working tree diff plus its blast radius | Yes. Fix every Blocker and Major, re-audit. At most 3 loops, then stop and report what is left |

Depth scales with risk, never below the gates. A copy tweak gets a short
report. Anything touching API contracts, auth, forms, money or a legacy
migration gets the full checklist.

## Iron rules

1. **Evidence or it did not happen.** Every PASS cites `file:line`, a command and its result, a test name, or the search you ran. No evidence means `UNVERIFIED`, never PASS.
2. **Audit the real diff, not your memory.** Re-read the diff in full before judging. For a base ref that is `git diff <base>...HEAD`; for the working tree it is the unstaged, staged and untracked files together.
3. **Run the gates, do not predict them.** Typecheck, lint, stylelint, tests and build, with the `package.json` scripts of the affected workspace. In a monorepo run the scripts of the package that owns the changed files, for example `apps/web`, not the root. Missing script: run the tool directly and say so. Missing tool or config: record it as not run, never as green.
4. **Trace the blast radius.** For every changed export, hook, type, schema, query key, style partial or token, find every consumer with a search and check it.
5. **See it if you can.** Follow section 6 of `review-checklist.md` for the browser pass and use its widths. Walk changed screens keyboard-only. When a design reference is available (Figma or a design-system doc), compare against it. Otherwise mark the check `UNVERIFIED` and put it under Manual QA.
6. **Try to break it.** Check the code against the Break-it list below. Do not reason about it in theory; find the line that handles each case, or report that none does.
7. **Tag every finding** *Introduced* or *Pre-existing*. Report pre-existing issues; never fix them silently, and in Gate mode fix them only when the task's scope already covers that code.
8. **No grade inflation.** Torn between two severities: pick the higher and say why.
9. **Stop and ask, do not guess,** when the backend contract is unclear, the design and the legacy behaviour disagree, or the only fix needs a backend change. That is a `NEEDS INPUT` verdict.

## Severity

- **Blocker:** wrong behaviour, data loss, security hole, backend-contract violation, keyboard or screen-reader barrier, any red gate.
- **Major:** missing loading, error or empty state; likely regression; duplicate of existing code; hot-path performance issue; visible deviation from the design or the design system.
- **Minor:** maintainability, naming, small inconsistency.
- **Nit:** preference. Never blocks. At most 3 per report.

Mapping to `quick-review`: Blocker = BLOCKERS, Major and Minor = SHOULD FIX,
Nit = NITS. `FIX FIRST` corresponds to "changes requested".

## Break-it list

- **Data:** empty, one item, 1k+ items, null or missing optional fields, unknown enum value, very long or unicode text.
- **Network:** loading, slow, 400/422, 401/403, 404, 5xx, timeout, offline, stale cache after a mutation.
- **User:** double submit, rapid clicks, back and forward, refresh mid-flow, deep link straight to the route, two tabs, keyboard only, screen reader, 200% zoom, 320px width.
- **Context:** missing permission, timezone and date boundaries, number and currency formatting.

## Checklist

Sections 4 to 8 name specific libraries. Apply each one when the project uses
that library; otherwise apply the same idea to the project's equivalent and say
which library you checked against.

### 1. Problem and parity
- Every acceptance criterion maps to code and a test. For a bug: root cause fixed, with a regression test that fails without the fix.
- Legacy parity, when the change replaces an existing flow: every behaviour, validation, permission and edge case of the old flow is preserved or listed as an intentional change.

### 2. Backend contract (fixed)
- No backend changes and no API redesign requests from a frontend task.
- Request and response shapes match the real contract: the project's API doc, generated client or schema if it has one, otherwise a sample response. No invented fields, no hand-copied types that can drift.
- Every failure shape is handled; server validation errors map back to fields.

### 3. Reuse and simplicity
- Existing hooks, components, utils, types, schemas, query keys and style partials searched before anything new was written. Cite the search. No duplicate of any of them.
- New files live where the project's structure doc or the neighbouring code puts them. No new dependency without written justification.
- The diff touches only what the task needs. Nothing dead: no unused code, imports, styles or props; no commented-out code; no `console` or `debugger`.

### 4. TypeScript
- No `any`, unjustified `as`, unproven `!`, or `@ts-ignore` (`@ts-expect-error` only with a reason).
- State variants are discriminated unions; schema types come from `z.infer` or the project's equivalent.

### 5. React and server state (TanStack Query or equivalent)
- No server state copied into `useState`, no fetching in `useEffect`, no stored derived state.
- Effects only sync with external systems, with complete dependencies and cleanups.
- Query keys come from the existing key factory and include every variable the `queryFn` uses.
- Mutations invalidate exactly the affected keys; optimistic updates roll back on error.
- Dependent queries gated with `enabled`; every query renders loading, error and empty states.
- Stable list keys; no index keys on dynamic lists.

### 6. Forms (React Hook Form + Zod or equivalent)
- Existing schema reused or extended, not duplicated. `defaultValues` set for every field.
- Errors visible and announced (`aria-invalid`, `aria-describedby`); server errors mapped back with `setError`.
- Double submit prevented, pending state shown, reset and dirty behaviour correct.

### 7. UI and design system
- The project's primitives (ShadCN, Radix or its own library) reused. No hand-rolled dialog, select, popover or menu.
- Design parity on spacing, type, colour and radius through tokens only, plus every state: hover, focus-visible, active, disabled, loading, empty, error.
- Works from 320px up with no horizontal overflow. Long text wraps or truncates on purpose.

### 8. Styling
- Apply `review-checklist.md` section 2 to every changed style file and `className`.
- When the project uses Tailwind or SCSS modules, also apply every rule in `styling-tailwind-scss.md`. Highest-risk misses: a new `@import`, a hardcoded value that duplicates a token, one property set by both a utility and SCSS, a new global selector, an orphaned class, stylelint not run.

### 9. Accessibility (WCAG 2.2 AA)
- Fully keyboard-operable, logical tab order, no traps. Focus returns to the trigger when an overlay closes and is never hidden behind sticky UI.
- Real `<button>` and `<a>`, labelled inputs, named icon-only buttons, intact heading order.
- Contrast 4.5:1 for text and 3:1 for UI, targets at least 24 by 24px, meaning never carried by colour alone, async results announced through `aria-live` where needed.
- `ui-guidelines.md` lists the common misses.

### 10. Performance
- No avoidable re-renders on hot paths (unstable props or context values). Memoise only where it measurably helps.
- Large lists virtualised, heavy routes and components lazy-loaded, no whole-library imports.
- No sequential requests that could run in parallel, no duplicate requests for the same data.

### 11. Security
- Apply `security-review.md`. In particular: no `dangerouslySetInnerHTML` with unsanitised data; no unvalidated redirects or URLs; no secrets in client code (every `VITE_*` or `NEXT_PUBLIC_*` value ships to the browser); no tokens or PII in logs, URLs or error messages.
- UI permission checks are UX only, never the enforcement.

### 12. Resilience and tests
- Errors caught at the right boundary with an actionable message; nothing swallowed.
- Tests assert behaviour, not implementation. No `.only` or `.skip` left behind; snapshots never blindly updated.

## Verdict

- **SHIP:** 0 Blockers, 0 Majors, all gates green, nothing `UNVERIFIED` in contract, security or accessibility.
- **SHIP WITH NOTES:** only Minors and Nits remain.
- **FIX FIRST:** any Blocker or Major, or any red gate.
- **NEEDS INPUT:** a critical area cannot be verified without something only a human has: a backend sample, credentials, design access, a product decision.

A gate that could not run (no script, no tool, no config, timed out) is shown
as `⚪ not run: <reason>`. It never counts as green, and it blocks `SHIP` when
the diff touches what that gate would have checked.

## Report (always this shape; an empty section says "None")

```
## Lead Lens Report: <scope>
Verdict: SHIP | SHIP WITH NOTES | FIX FIRST | NEEDS INPUT
Gates:   typecheck ✅/❌/⚪ · lint ✅/❌/⚪ · stylelint ✅/❌/⚪ · tests ✅/❌/⚪ · build ✅/❌/⚪
         <exact commands run, one per line, with the workspace they ran in>

### Findings
| # | Sev | Introduced / Pre-existing | Location | Problem | Fix |
|---|-----|---------------------------|----------|---------|-----|

### Verified (with evidence)
- <check>: <file:line | command | test | search>

### UNVERIFIED (and what is needed)
- <check>: <missing env, data, access or decision>

### Manual QA for a human
1. <step> → <expected result>
```

In Gate mode add one line per loop above Findings: `Loop <n>: fixed <ids>,
re-ran <gates>`. After the third loop, whatever is still open stays in
Findings and the verdict is `FIX FIRST`.
