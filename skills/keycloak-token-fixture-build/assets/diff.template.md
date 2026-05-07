# Diff — adversarial-N prediction vs actual

## Headline

| | Value |
| --- | --- |
| Skill prediction (fresh-context agent, `prediction.json`) | [committed value or "UNVERIFIABLE" with citation] |
| Actual on the wire (`actual-token*.json`) | [exact actual value] |
| Fixture verdict | **[PASS / FAIL-BY-DESIGN / FAIL-SKILL-GAP / FAIL-FIXTURE-BUG]** — [one-line rationale] |

## Harness note

This prediction was produced by a fresh-context Agent spawned at the
parent level, with no access to `actual-token*.json`, `log*.txt`,
`setup.md`, or `surprises.md`. The agent's tool call to write
`prediction.json` was the first time the prediction was committed to
the file.

## Dim 1 — [primary commitment dimension]

[For each commitment in prediction-target.md, score it. Use a table
where useful.]

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| [field] | [value] | [value] | [✓ / ✗] |

[Reasoning analysis: where the predictor's chain of reasoning landed,
which skill passages it invoked, whether the citations were accurate.]

## Dim 2 — [secondary commitment dimension if applicable]

[Same shape as Dim 1.]

## Dim 3 — collateral claims (sanity check on the foundation)

[Not part of the prediction target, but score the predictor's wider
grasp of the skill on this fixture. Does the predictor correctly
anticipate the values of other claims in the token? Use a table.]

| Claim | Actual | Skill-derivable from realm-config? | Notes |
| --- | --- | --- | --- |
| [claim] | [value] | [✓ / ✗] | [which invariant governs this] |

## Where the skill held / where it failed

[Narrative paragraph or two. Which invariants in the target skill were
correctly applied? Which were misapplied or missing? If the verdict is
PASS or FAIL-BY-DESIGN, this section confirms the skill's text was
sufficient. If FAIL-SKILL-GAP, this section names the specific passage
that needs editing.]

## Recommendation: skill changes from this fixture

[For PASS: "None. The skill's text was sufficient for a fresh-context
agent to commit correctly. This fixture is a positive regression test —
any future skill edit that weakens [specific invariant] should flip
this fixture to fail."

For FAIL-BY-DESIGN: "None in the direction of making the skill
commit. Optionally add a one-liner [specific suggestion] under
[specific reference]."

For FAIL-SKILL-GAP: "Edit [specific reference] to [specific change].
The minimum change that makes a fresh predictor land correctly on this
fixture without breaking [list other fixtures] is: [specific text]."

For FAIL-FIXTURE-BUG: "Redesign the fixture. [Specific issue]. The
target skill is innocent of this verdict; do not edit it."]
