# Verdict rubric

Every fixture's `diff.md` ends with a verdict. There are four possible
shapes. Only one of them warrants a SKILL.md edit; the others have
different actions.

## `pass`

The predictor committed to the correct answer with skill citations, OR
the predictor legitimately hedged on a dimension that `prediction-target.md`
explicitly admits as a hedge-with-citation.

**Action**: do nothing to the target skill. The fixture becomes a
regression test — re-run its predictor whenever the target skill is
edited.

**Examples**:
- adversarial-2: predictor nailed all 11 set-membership commitments,
  nailed `openid` position, hedged on inter-scope order with a clean
  invariant-10 citation. `prediction-target.md` explicitly admits the
  hedge as structurally complete.
- adversarial-3: predictor committed exactly to `(absent, trrtcc)` and
  `(present, onrtro)`. Both pairs derived from invariant 12 + the
  grant-defaults table.

## `fail-by-design`

The predictor refused to commit to a single answer because the skill
itself documents the answer as non-derivable from the documented
contract. The fixture exposed a real limit of what the skill can know.

**Action**: do nothing to the target skill in the direction of "make it
commit." The hedge is correct. Optionally add a one-liner to the skill
documenting the diagnostic for the operator (e.g., "if you see this
configuration shape, set explicit priorities to make the outcome
contract-derivable").

**Example**: adversarial-1. Two equal-priority mappers writing the same
claim. Predictor cited invariant 10 ("mapper sort ties are not
deterministic") and refused to choose between `value-from-alpha` and
`value-from-zulu`. The actual outcome was `value-from-zulu`, but it
came from JVM `HashSet` iteration order, not the documented contract.
A skill that committed to one specific value would be over-fitting to a
particular JVM/Keycloak version.

**Distinguishing `fail-by-design` from `fail-skill-gap`**: ask whether
a different JVM, JDK, or Keycloak patch version (within the pinned
major.minor) could plausibly produce a different observable. If yes,
the answer isn't part of the documented contract and the skill is
right to hedge. If no, the answer is contract-derivable and a
non-commitment is a skill gap.

## `fail-skill-gap`

The predictor committed but committed wrong, OR the predictor hedged
when the skill's documented contract should have been sufficient to
commit.

**Action**: edit the target skill. The diff.md should specify *which*
passage in SKILL.md or references/ misled the predictor (or which
missing passage left it without an anchor). The edit should be the
minimum that makes a fresh predictor land correctly on this fixture
without breaking the predictions for any other fixture.

**Example pattern** (hypothetical): a fixture probes invariant 5
(userinfo fallback to `id.token.claim`). Predictor commits to "claim
appears in userinfo" because they read the invariant as "userinfo
toggle defaults to true on missing." Actual: claim absent. The
invariant's wording was ambiguous — it should be edited to say "the
fallback chain is: `userinfo.token.claim` → `id.token.claim` → off."

**Verdict-flipping is a positive signal**, not a negative one — the
fixture caught a real problem before the operator did. Track these in
git as "fixture caught skill bug" commits.

## `fail-fixture-bug`

The fixture itself is broken — non-deterministic across mints, the trap
menu is incomplete, or the seam tests something other than what
`prediction-target.md` claims.

**Action**: redesign the fixture. The target skill is innocent of this
verdict; do not edit it.

**Common fixture bugs**:
- Determinism check failed: two mints produce different values for the
  field under test, but the strip set already excludes it. Solution:
  the field is not deterministic on this realm config; redesign the
  seam.
- Trap menu missing the actual outcome: pre-mint enumeration of
  plausible outputs didn't include the value the actual token produced.
  Solution: add the missed trap to `prediction-target.md`, re-spawn the
  predictor (its prediction is still valid; only the trap menu was
  incomplete).
- Seam tests the wrong invariant: the realm config exercises a
  different code path than the invariant claims. Solution: redesign the
  realm config or change which invariant the fixture is targeting.

## Decision tree

```
Predictor committed?
├── Yes
│   ├── Committed value matches actual? ────────── PASS
│   ├── Committed value differs from actual?
│   │   ├── Trap menu enumerated this case? ─────── FAIL-SKILL-GAP
│   │   └── Trap menu missed this case? ─────────── FAIL-FIXTURE-BUG
│   └── Determinism check failed for the field? ── FAIL-FIXTURE-BUG
└── No (hedged or "UNVERIFIABLE")
    ├── prediction-target.md admits this hedge? ── PASS
    ├── Skill's own invariants mandate the hedge?  FAIL-BY-DESIGN
    └── Otherwise (skill should have committed) ── FAIL-SKILL-GAP
```

## Reporting the verdict

`diff.md`'s "Headline" section should include the verdict explicitly,
with a one-line rationale. Example formats:

- `Fixture verdict: PASS — set membership exact, openid position exact, order legitimately hedged with skill citation per prediction-target.md's scoring rubric.`
- `Fixture verdict: FAIL-BY-DESIGN — predictor correctly hedged on invariant 10's HashSet iteration. Actual outcome (zulu) came from a JVM-implementation detail outside the documented contract.`
- `Fixture verdict: FAIL-SKILL-GAP — predictor committed to X but actual was Y. Skill passage [reference] is missing the [specific rule] that would have led to the correct commitment. Recommended edit: ...`
- `Fixture verdict: FAIL-FIXTURE-BUG — the determinism check showed the [field] varied across mints. Seam needs redesign.`

After writing the verdict, the human (you, applying this skill) decides
whether to act on it — edit the target skill (`fail-skill-gap`),
redesign the fixture (`fail-fixture-bug`), or do nothing (`pass`,
`fail-by-design`).
