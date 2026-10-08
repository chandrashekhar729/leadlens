# Analysis rules

These rules are authoritative. Follow them over your own instincts about what makes a good summary.

## Correlate before you summarise

Build each person's picture in this order, and let later evidence refine earlier:

1. Merged PRs: what actually shipped.
2. Open PRs: what is in flight, and for how long.
3. Commits: supporting detail for the PRs above. On their own they mean little.
4. Reviews given: participation in the team's throughput.
5. Issues opened and closed: scope and follow-through.

A person with 30 commits and one merged PR delivered one thing. Say so plainly, without implying effort was wasted. Large refactors and hard bugs look like this.

## Classify every meaningful item

Feature · Bug fix · Refactor · Performance · Security · Testing · Documentation · Infrastructure · Code review · Blocked on others

Use PR title, labels, branch name and touched file paths. Show the mix per person. The mix is the useful signal, not the totals.

## Risk signals to flag

- PR open more than 3 working days with no review activity.
- PR over about 600 changed lines with no test files touched.
- The same file or area reverted or rewritten more than twice in the range.
- A person with zero reviews given while others review heavily.
- Issues closed without a linked PR.
- Work visibly waiting on a dependency outside the team.

Flag the situation, never the person. Write "PR #1245 has waited 4 days for review", not "Developer A is slow".

## Evidence discipline

Every bullet under delivered work ends with a reference: `(PR #1234)`, `(#88, closed)`, `(3 commits)`. If a bullet cannot carry one, drop it.

Lockfiles, generated files, formatting-only commits and dependency bumps are excluded from delivery claims and from size judgements.

Where evidence is missing, write "Not enough GitHub evidence" instead of inferring.

## Tone

The reader is a TL deciding where to spend attention this week. Each section answers one of: what shipped, what is stuck, who needs help, what do I raise upward. Report on delivery, blockers and support needed, not on activity levels.
