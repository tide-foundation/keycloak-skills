# Diff — adversarial-5 prediction vs actual (regression rerun)

## Headline

| | Value |
| --- | --- |
| Skill prediction (`prediction.json`) | Access+ID: trap **1**, claim **absent** both surfaces. Scope literal `"openid profile organization email"`; multiset `{openid:1, profile:1, organization:1, email:1}`; `organization` count = **1**. |
| Actual on the wire | Access+ID: claim absent both surfaces. Scope literal `"openid profile email organization"` (order varies; multiset and count match). |
| Fixture verdict | **PASS — verdict-flip from pre-org-docs FAIL-SKILL-GAP.** The new `organizations.md` §3.1 + SKILL.md invariant 13(a) directly told the predictor that unqualified `scope=organization` + multi-membership → claim absent. The pre-edit predictor went the opposite way (predicted claim present with both aliases). |

## Harness note

Fresh-context Agent spawned at parent level against the post-edit skill text. Forbidden file list excluded siblings (1, 2, 3, 4, 6) — adv-4 and adv-6 carry organisation-claim data that would invalidate fresh-context. Excluded own `actual-token.json`, `actual-id-token.json`, mint-2 variants, `log*.txt`, `setup.md`, `surprises.md`, `prediction.before-org-docs.json`, `diff.before-org-docs.md`.

## Regression check

Pre-edit verdict: **FAIL-SKILL-GAP** (predictor committed `["acme", "zeta"]` set with order-hedge on both surfaces; actual was absent). Post-edit verdict: **PASS**. The flip is driven by:

- `organizations.md` §3.1 (the static-path multi-membership rule): "The mapper writes the organization claim only when the user has exactly one organisation membership. For zero-membership or multi-membership, the mapper writes null and invariant 11 (NON_NULL) drops the claim."
- SKILL.md invariant 13(a): the same rule at SKILL-level.
- The predictor cited both passages by file + line in its `reasoning.organization_claim` field.

## Per-dimension scoring

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Access-token `organization` | absent (trap 1) | absent | ✓ |
| ID-token `organization` | absent (trap 1) | absent | ✓ |
| Scope multiset | `{openid:1, profile:1, organization:1, email:1}` | matches | ✓ |
| `organization_in_scope_count` | 1 | 1 | ✓ |
| Scope literal order | `"openid profile organization email"` (best-guess; pre-hedged as not-pinned) | `"openid profile email organization"` | ✗ on literal, but legitimate invariant-10 hedge per the same shape as adv-2 |

All committed-with-certainty dimensions match. The literal-string order is the standard invariant-10-shape hedge.

## Where the docs held

The predictor specifically called out using `organizations.md` §3.1 to rule out trap shapes 2-9 and to commit to trap 1. It also correctly applied the side-finding scope condition: `organizations.md` §3.1's single-membership duplicate-`organization` observation is gated on N=1, and the predictor noted adv5-multimember is N=2, so the duplicate does not apply here. That's a precise application of the documented condition.

## Methodological caveat

Same as adv-4: `organizations.md` §3.1 contains the empirical anchor that "tests/token-construction/adversarial-5 → multi-member → claim absent" via §6's cross-fixture summary. A predictor reading the docs sees the answer for this exact fixture. For *this* verification round, the rerun confirms the docs are precise enough; for future blind-regression value, a new fixture with different alias / org topology would be needed.

## Recommendation

None for the target skill — the verdict-flip confirms the highest-impact part of the docs edit works. This was the biggest pre-edit gap (predicted present, actual absent — a flip-of-presence, not a flip-of-shape) and it's now closed by a single sentence in `organizations.md` §3.1.
