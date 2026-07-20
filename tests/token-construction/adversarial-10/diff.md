# Diff — adversarial-10 prediction vs actual

## Headline

| | Value |
| --- | --- |
| Skill prediction (fresh-context agent, `prediction.json`) | `outcome=token_minted`, `adv10_marker="present"`, `sub=PRESENT`, `scope_claim_multiset={email, adv10-scope, profile}` |
| Actual on the wire (`actual-token-2.json`) | token minted; `adv10_marker="present"`, `sub` present, `scope="email adv10-scope profile"` |
| Fixture verdict | **PASS (with source-escape)** — all three commitments exact, but the deciding fact was NOT derivable from skill text; the predictor reached it via the SKILL.md L8 WebFetch directive. Same shape as adversarial-7's pre-edit run. |

## Harness note

Fresh-context agent spawned at parent level; chained-flow rules applied
(subject token a permitted input; `skills/keycloak-token-fixture-build/`
and all of `adversarial-9/` on the deny list). The agent's write of
`prediction.json` was the first commitment of the prediction. Second
two-leg fixture under harness invariant 9; ordering compliance recorded
in `setup.md` / `surprises.md`.

## Dim 1 — `adv10_marker`

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `adv10_marker` | `"present"` | `"present"` | ✓ |

## Dim 2 — `sub`

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `sub` | PRESENT | present (equals subject token's `sub`) | ✓ |

## Dim 3 — `scope_claim_multiset`

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `scope_claim_multiset` | `{email, adv10-scope, profile}` | `"email adv10-scope profile"` | ✓ |

## Dim 4 — collateral claims

| Claim | Actual | Skill-derivable from realm-config? | Notes |
| --- | --- | --- | --- |
| `aud` | `"account"` | ✓ | role mappers ran (mapper set NOT shrunk); account roles only |
| `realm_access` / `resource_access.account` | present | ✓ | same |
| `email`, `email_verified` | present | ✓ | email scope survived (nothing filtered) |
| `jti` prefix | `onrtte:` | ✗ (not in the skill's prefix table) | consistent with adversarial-9 |
| `sid` | present, equals subject `sid` | partially | consistent with TRANSIENT-only nulling |

## Where the skill held / where it failed

The seam was designed (and the trap menu built) around the premise that
the exchange `scope` param populates `restrictedScopes` and can shrink
the mapper set — the reading the target skill's own text invites. **The
premise is false on stock 26.5.5.** Builder and predictor independently
established, from source, that `StandardTokenExchangeProvider` passes
`context.getRestrictedScopes()` (L233) whose only production writer is
the `DownscopeAssertionGrantEnforcerExecutor` client-policy executor
(verified present at 26.5.5, `setRestrictedScopes` call confirmed).
With `clientPolicies.policies: []` — visible in the public
`realm-config.json` — `restrictedScopes` is null, the `isAllowed`
filter is inert (scope-resolution.md's null guard, correctly
documented), and the exchange `scope` param is add-only. The actual
token kept the marker, `sub`, and the full scope set: trap row 1's
values, via a mechanism no trap row's persona describes.

The skill *text* held only where it was already precise: the
scope-resolution pseudocode's null-guard on `restrictedScopes`
(L54-56), invariant 1 (`sub` via SubMapper in `basic`), invariant 2
(scope-claim composition), invariant 11. It failed on provenance: both
`mapper-set-assembly.md` L98-100 ("`restrictedScopes` (token exchange)
… Token exchange can therefore see a strictly smaller mapper set") and
`inputs-and-outputs.md` L72 ("`restrictedScopes` (DCSC ctor arg) |
token exchange") assert or imply that token exchange per se populates
the filter. A text-only reader following those passages lands on trap
rows 2, 3, or 5 and mispredicts. The predictor avoided them only by
escaping to upstream source — and said so explicitly in its report.

## Recommendation: skill changes from this fixture

None mandated by the PASS verdict. But this is the second consecutive
fixture whose fresh predictor named specific target-skill passages as
misleading on exchange provenance, and here the misleading reading was
load-bearing (it flips all three commitments). Candidate edit for the
human, per the adversarial-7 precedent (pre-edit source-escape →
post-edit "skill text alone sufficient"):

- `mapper-set-assembly.md` L98-100 and `inputs-and-outputs.md` L72:
  state that `restrictedScopes` is null on the standard token-exchange
  path unless a `DownscopeAssertionGrantEnforcerExecutor` client policy
  is configured; the exchange `scope` parameter is validated
  (`isValidScope`) and included as-is (add-only), never intersected
  with the subject token's `scope`.
- Together with adversarial-9's candidates (post-mapper.md L42-46
  audience trigger; `onrtte:` jti row), this makes one coherent
  "exchange provenance" edit batch.

If the batch is applied, re-run fresh predictors on adversarial-1..10
per harness.md's regression protocol. Expected post-edit signal: adv-9
and adv-10 predictors commit without source-escape.
