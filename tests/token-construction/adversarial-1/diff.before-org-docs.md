# Diff — adversarial-1 prediction vs actual (re-run 2026-05-07)

## Headline

| | Value |
| --- | --- |
| Skill prediction (`predicted_collision_claim`) | `UNVERIFIABLE` (skill declines to commit) |
| Actual on the wire (`actual-token.json`) | `"value-from-zulu"` |
| Fixture verdict | **fail-by-design** — skill correctly hedges per invariant 10; commit-or-fail bar of `prediction-target.md` is failed AS DESIGNED |
| vs. prior fresh round | **unchanged** (was `fail-by-design`, still `fail-by-design`) |

## Harness note

Re-run on 2026-05-07 against the current `keycloak-token-construction/SKILL.md` and references. Fresh-context predictor spawned at the parent level; previous `prediction.json` and `diff.md` were moved out of the fixture directory before spawn so the agent could not read them. Predictor's first write to `prediction.json` is the prediction commitment.

## Dim 1 — shape

| Dimension | Skill | Actual | Match? |
| --- | --- | --- | --- |
| Type | scalar string (one of two values) | scalar string | ✓ |
| Present? | yes (gate passes, no null-source) | yes (`"value-from-zulu"`) | ✓ |
| Element-of-set | `{"value-from-alpha", "value-from-zulu"}` | `"value-from-zulu"` | ✓ |

## Dim 2 — exact value

| Dimension | Skill | Actual | Match? |
| --- | --- | --- | --- |
| Exact value | undecidable | `"value-from-zulu"` | ✗ — skill cannot commit |

The miss is the structural failure mode the fixture is designed to surface. Two `oidc-hardcoded-claim-mapper` mappers on different scopes write the same path with no `priority` set on either; per invariant 10 the discriminant is HashSet iteration on `Set<ProtocolMapperModel>` (not contract-derivable). The fresh predictor cited invariant 10 plus `references/mapper-set-assembly.md`'s "Tie-breaking is non-deterministic" section and refused to commit.

## What the predictor ruled out (with citation)

- **`absent`**: both mappers pass `access.token.claim=true`, HardcodedClaim writes a non-null constant, so `JsonInclude.NON_NULL` (invariant 11) cannot drop the claim. ✓ — actual is present.
- **Array form**: `oidc-hardcoded-claim-mapper` with `jsonType.label="String"` and no `multivalued` config writes a scalar; second writer overwrites first per `post-mapper.md` "Collision handling" (no merge). ✓ — actual is scalar.

## Verdict

**fail-by-design** — same as prior run. The skill correctly identifies invariant 10 as the gating constraint. Committing here would require a rule sourced from outside the documented Keycloak contract (e.g., empirical observation of HashSet iteration on this specific JVM/JDK). The skill's prescribed action ("require distinct priorities or flag as unverifiable") is the right operator-facing recommendation.

## Skill-edit recommendation from this re-run

None blocking. The fresh predictor's actionable feedback was a minor reinforcement — the HardcodedClaim "scalar overwrite vs merge" semantics had to be inferred from `jsonType.label=String` + absence of merge rules in `post-mapper.md`, rather than read directly. A one-line note under HardcodedClaim ("scalar overwrite at the configured `claim.name`; multivalued config wraps to a list") would make the array-shape rule-out citable rather than inferred. Optional — does not affect this fixture's verdict.

## Comparison to prior round

The prior `diff.md` (preserved at `/tmp/adv-prev-2026-05-07/adv1-diff.md`) reached the same verdict via the same invariant 10 path. No regression; no fix. The skill text on invariant 10 still produces the correct hedge.
