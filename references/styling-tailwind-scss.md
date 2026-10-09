# Styling rules: Tailwind and SCSS modules

Apply when the project uses Tailwind, SCSS modules, or both. Project rules
win over this file when they conflict; say which rule you applied.

Tailwind is the default. SCSS is a deliberate exception, never a habit.

Reach for an SCSS module only when Tailwind would be unreadable or
impossible: complex keyframes and animations, third-party or legacy markup the
project does not control, or legacy styles mid-migration with a ticket to
remove them. Everything else uses utilities, component variants (`cva`) and
`cn()`.

- **Scope:** a co-located `Component.module.scss`. No new global selectors; globals live only in the project's existing styles entry. Never add to legacy global SCSS. Move a component's styles out only when that component is already in the task's scope.
- **Module system:** `@use` and `@forward` only. `@import` is deprecated in Dart Sass: never add it, and convert it in files you touch.
- **Reuse first:** search the existing partials (tokens, mixins, functions, breakpoints) before writing one. One source per concern, never a copy.
- **Tokens:** colour, spacing, radius, shadow, z-index and type come from CSS variables (`var(--primary)`, `var(--radius)`) so theming and dark mode keep working. No hardcoded value that duplicates a token. Never copy theme colours into Sass variables: they are compile-time and ignore theme switches.
- **Tailwind boundary:** no Tailwind directives (`@apply`, `@theme`, `theme()`) inside `.scss`. Tailwind v4 is not designed to run through Sass, and mixing them splits the source of truth. Never style one property on one element from both a utility and SCSS.
- **Cascade layers (Tailwind v4):** utilities sit in `@layer utilities`, so plain SCSS beats them regardless of specificity. If a module's styles must stay overridable through `className`, wrap them in `@layer components { ... }`.
- **Breakpoints:** one shared SCSS breakpoint map mirroring Tailwind's; change both together. No ad-hoc media-query widths.
- **Radix and ShadCN state:** style through data attributes (`[data-state='open']`, `[data-disabled]`, `[data-side]`), not invented state classes.
- **Specificity:** nesting at most 3 levels, no ID selectors, no descendant selectors reaching into child components. `!important` and `:global` only with a comment saying why.
- **Accessibility:** never remove an outline without a visible `:focus-visible` replacement. Reduce or disable motion under `prefers-reduced-motion: reduce`.
- **Composition:** join module classes and utilities with `cn()`, never string concatenation. `tailwind-merge` cannot resolve SCSS-versus-utility conflicts, so do not create them.
- **Build hygiene:** Vite `additionalData` may inject only partials that emit no CSS (variables, mixins, functions); anything that outputs CSS is duplicated into every module. Delete orphaned classes when markup changes. Stylelint must pass.
- **Units:** `rem` for type and spacing; no unexplained magic numbers.
