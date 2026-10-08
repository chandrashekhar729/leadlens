# Report format

Follow this structure exactly. Omit a section only when the data is genuinely empty, and then write "None this period" rather than deleting the heading.

---

# Weekly Engineering Report
**Range:** <SINCE> – <UNTIL> · **Repos:** <list> · **Generated:** <date>

## TL Summary
- Overall: 🟢 on track / 🟡 some drag / 🔴 blocked, with one sentence of why.
- Shipped this period: 2-4 bullets, outcome-level.
- Needs your attention: 1-3 bullets, each with the specific thing to do.

---

## <Developer name> (@<github-handle>)

**Delivered**
- <Outcome> (PR #123, merged <date>)

**In progress**
- <Work> (PR #145, open <n> days)

**Review participation**
- Reviewed <n> PRs, <n> comments. Notable: <PR and why>.

**Work mix**
Feature <n> · Bug fix <n> · Refactor <n> · Testing <n> · Review <n>

**Blocked / waiting on**
- <What, and on whom or what>

**Flags**
- ⚠️ <Risk signal with its evidence>

---

## Team view

**Delivery themes**: 2-4 themes with the PRs under each.

**Review flow**: who reviewed whose work; call out concentration on one person.

**Recurring blockers**: anything that showed up more than once.

**Review health** (only when the review checklist ran): one line per dimension with counts and the top three files, then the browser line. Never attributed to a person.
- Guidelines: <n> findings · <files>
- Styling tokens: <n> · <files>
- Code and architecture: <n> · <files>
- Security: <n> · <files>
- Accessibility: <n> · <files>
- Browser checks: <routes verified | not applicable | skipped: reason>
- Recurred across PRs: <categories>

**Evidence gaps**: what the report could not establish from GitHub.

---

## TL Action Items
1. <Action>: <why now>
2. ...

Keep this list to five items or fewer. If everything is an action item, nothing is.
