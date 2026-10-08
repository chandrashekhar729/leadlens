# Review checklist

Shared by `quick-review`, `weekly-report` and `monthly-report`. Work through the
sections in order. In a **report** the findings are aggregate and never
attributed to a person; in a **quick review** every finding carries `file:line`.

## 1. Establish the rules before judging

Read whatever the project already states about how code should look, and treat
those as the source of truth over your own preferences:

- `CLAUDE.md`, `.claude/rules/*.md`, `CONTRIBUTING.md`, `README.md`, `docs/`
  (style guides, design system notes, component conventions, commit/PR rules)
- Config: `.eslintrc*`, `.stylelintrc*`, `.prettierrc*`, `.editorconfig`,
  `tsconfig.json`, `tailwind.config.*`, theme or token files
- Existing sibling files near the diff — follow local patterns
- The plugin checklists `${CLAUDE_PLUGIN_ROOT}/references/ui-guidelines.md`
  and `${CLAUDE_PLUGIN_ROOT}/references/security-review.md`. Project rules win
  over these when they conflict.

Summarize the rules you found in two or three lines. If the project has no
written guidelines, say so explicitly and fall back to framework conventions.

## 2. Styling audit (SCSS / CSS variables / tokens)

Detect the styling approach in use (SCSS, CSS custom properties, CSS modules,
Tailwind, styled-components), then check the diff for:

- **Hardcoded values that have a token.** Raw hex, rgb, px spacing, font sizes,
  z-index, breakpoints, shadows, radii, transition durations where a variable,
  `$map` or `var(--token)` already exists. Name the token that should replace it.
- **Invented tokens** — new variables added when an equivalent one exists.
- **Scope and layering** — variables defined at the right level (theme vs
  component), light/dark or theme overrides honored, no leaking globals.
- **SCSS hygiene** — nesting deeper than 3 levels, `@extend` misuse, duplicated
  blocks that should be a mixin, unused variables/imports, `@import` where the
  project has moved to `@use`/`@forward`.
- **Specificity and overrides** — `!important`, ID selectors, inline styles,
  element selectors used to beat the design system.
- **Naming** — BEM or whichever convention the project uses, applied consistently.
- **Dead CSS** — classes added but never referenced, or markup classes with no
  rule behind them.

## 3. Code and architecture

Layering and responsibility boundaries, duplicated logic, state management,
error and loading states, prop/API contracts, naming, dead code, test coverage
for new branches of logic.

## 4. Defensive security

Unsanitized rendering (`dangerouslySetInnerHTML`, `v-html`, `innerHTML`),
unvalidated input, missing authorization checks on new endpoints, secrets or
tokens in source or committed env files, unsafe URL/redirect handling,
dependency additions with known advisories, PII in logs.

## 5. Accessibility

Semantic elements over click-handling divs, labels tied to inputs, alt text,
heading order, visible focus, keyboard reachability of every interactive
element, ARIA used only where needed and correctly, contrast against the
tokens in use, respect for `prefers-reduced-motion`, forms announcing errors.

## 6. Browser verification — best effort, never blocking

This section is conditional. Work through the gates in order and stop at the
first one that fails, recording why.

**Gate 1 — is it worth it?** Does the diff touch anything rendered: components,
templates, pages/routes, styles, client-side state, or assets? If it's
server-only, migrations, CI config or docs, skip the whole section and record
"browser checks not applicable — no front-end changes".

**Gate 2 — can the app run?** Find a URL to open, trying these in order and
stopping at the first that works:

1. A configured URL: `baseUrl` in `.claude/team-report.json`, or a local URL
   the project's `CLAUDE.md` or README names. Probe it once with curl; if it
   answers, use it and start nothing. This covers apps already served by
   Apache or nginx on this machine.
2. The dev command in `package.json` (`dev`, `start`, `serve`). Start it in
   the background, give it a reasonable window to bind a port, then probe the
   URL once; do not poll in a sleep loop.
3. For plain HTML and CSS with no dev command, serve the project folder with
   a static server on a free port, for example `python3 -m http.server`, and
   open the changed pages by path.

If none works, can't install deps, needs secrets or a database you don't
have, or the port is taken, record "browser checks skipped — <reason, with the
error line>" and continue with static findings only.

**Gate 3 — is there a browser?** If no browser tooling is available in this
session, record "browser checks skipped — no browser tooling" and continue.

If all three gates pass, open each affected route — the routes the diff most
directly touches, at most four — and do as much of the following as the setup
allows, skipping individual checks that aren't possible and noting which ones
you skipped. Prefer a batch browser call where one exists so each route costs
few steps.

- Screenshots at 1440 / 768 / 390 widths. The Chrome extension's window
  resize may be ignored by the window manager; check the screenshot's
  reported width, and if it did not change use Playwright's `browser_resize`
  or note "responsive widths not verified".
- For a CSS or HTML only diff, also screenshot the same route on the base
  branch and compare side by side; a styling regression is rarely visible in
  one screenshot alone.
- Console errors and warnings; failed network requests.
- The primary interaction the diff touches — submit, open, toggle, paginate.
- Tab through: everything interactive reachable, focus visible, no trap, focus
  restored when a modal closes.
- Empty, loading and error states the diff introduces.
- Theme toggle, if one exists — confirm tokens resolve in both.
- An axe scan, if available.

If end-to-end tests already cover the touched areas, run those instead of
hand-driving the UI and report pass/fail.

Stop any dev server this review started before reporting.

Report only what you observed. A check you couldn't run is "not verified" —
never a pass. Nothing in this section produces a blocker on its own: a failed
browser check is a finding, an unavailable browser is a note.

**Report mode.** When this checklist runs inside a weekly or monthly report,
check gate 3 before gate 2: never start a dev server when no browser tool is
available, which is the case in the scheduled CI run. The browser pass is then
observation only: load each route, take the three screenshots,
collect console and network errors, run axe if available. Skip hand-driving
interactions and the tab-through unless end-to-end tests already cover them. A
range of commits has no single primary interaction, and the report runs in the
main turn, so the step budget also has to cover the collector and the write.
Screenshots and logs go to the session scratchpad, never into the repo.
