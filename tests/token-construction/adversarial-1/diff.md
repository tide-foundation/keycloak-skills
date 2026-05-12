# Diff — adversarial-1 prediction vs actual (regression rerun)

## Headline

| | Value |
| --- | --- |
| Skill prediction (`prediction.json`) | `collision_claim`: **UNVERIFIABLE** — mapper-sort tie on equal priority + same-path collision; invariant 10 + post-mapper.md L185-206 designate this as non-committable from the documented contract. |
| Actual on the wire | `value-from-zulu` (JVM HashSet bucket order) |
| Fixture verdict | **FAIL-BY-DESIGN — no regression** from the pre-org-docs baseline. The docs edit (new `references/organizations.md`, extension to invariant 10's wording, new invariant 13) does not affect this fixture's seam. Invariant 10 still mandates the hedge; the predictor still applied it correctly. |

## Harness note

This rerun used a fresh-context Agent spawned at the parent level, against the post-edit skill text. Forbidden file list explicitly excluded sibling adversarial fixtures (2-6) and this fixture's own `actual-token.json`, `setup.md`, `surprises.md`, `log.txt`, `prediction.before-org-docs.json`, `diff.before-org-docs.md`. The pre-edit prediction and diff are preserved at `prediction.before-org-docs.json` + `diff.before-org-docs.md` for reference.

## Regression check

Pre-edit (`diff.before-org-docs.md`) verdict: FAIL-BY-DESIGN. Post-edit verdict: **FAIL-BY-DESIGN**. Same shape, same citation invariant. The extension to invariant 10's wording in SKILL.md (mentioning intra-mapper Set iteration via `organizations.md` §5) does not narrow the original mapper-sort-tie hedge — it widens invariant 10's applicability to a sibling case. The predictor's reasoning chain is unchanged.

## Verdict rationale

Adv-1's seam (two HardcodedClaim mappers, same priority, same path) is squarely in invariant 10's documented mandate to flag as unverifiable. The actual outcome `value-from-zulu` is reachable only by reading the JVM HashSet bucket iteration, which is outside the contract the skill commits to. A predictor that committed to alpha or zulu would be overfitting to a specific JVM/Keycloak patch version; the documented contract requires the hedge. This is the canonical `fail-by-design` example in the verdict rubric.

## Recommendation

None. This fixture continues to serve as the canonical regression test for invariant 10's mapper-sort-tie hedge. Any future skill edit that weakens or removes invariant 10 (or removes the "require distinct priorities or flag the case as unverifiable" clause) should flip this fixture to fail-skill-gap.
