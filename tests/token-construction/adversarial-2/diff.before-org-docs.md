# Diff — adversarial-2 prediction vs actual (re-run 2026-05-07)

## Headline

| | Value |
| --- | --- |
| Skill prediction (fresh-context agent, `prediction.json`) | Set: `{openid, profile, email, adv2-scope-attr-true, adv2-client, adv2-scope-attr-unset}` with `openid` first; inter-scope order hedged per invariant 10 |
| Actual on the wire (`actual-token.json`) | `"openid adv2-scope-attr-true adv2-client email adv2-scope-attr-unset profile"` |
| Fixture verdict | **PASS** — set membership exact, `openid` position exact, order legitimately hedged with skill citation |
| vs. prior fresh round | **unchanged** (was `pass`, still `pass`) |

## Harness note

Re-run on 2026-05-07 against the current `keycloak-token-construction/SKILL.md` and references. Fresh-context predictor spawned at the parent level; prior `prediction.json` and `diff.md` moved out of the fixture directory before spawn. The agent's first write to `prediction.json` is the prediction commitment.

## Dim 1 — set membership (11/11)

| Name | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `openid` | in | in | ✓ |
| `profile` | in | in | ✓ |
| `email` | in | in | ✓ |
| `basic` | out (`include.in.token.scope=false`) | out | ✓ |
| `acr` | out (`include.in.token.scope=false`) | out | ✓ |
| `roles` | out (`include.in.token.scope=false`) | out | ✓ |
| `web-origins` | out (`include.in.token.scope=false`) | out | ✓ |
| `adv2-scope-attr-unset` | **in** (default-true on missing attr — invariant 2) | **in** | ✓ |
| `adv2-scope-attr-true` | in | in | ✓ |
| `adv2-scope-attr-false` | out | out | ✓ |
| `adv2-client` | **in** (standalone scope, not the ClientModel — DCSC.L200 only filters `instanceof ClientModel`) | **in** | ✓ |

11/11. The two adversarial cases (`adv2-scope-attr-unset` default-true; `adv2-client` standalone-scope vs. ClientModel-self) both landed.

## Dim 2 — `openid` position

| Predicted | Actual | Match? |
| --- | --- | --- |
| First (per `attachOIDCScope` prepend) | First | ✓ |

## Dim 3 — inter-scope order (the hedge dimension)

Predicted example permutation: `openid profile email adv2-scope-attr-true adv2-client adv2-scope-attr-unset`. Actual: `openid adv2-scope-attr-true adv2-client email adv2-scope-attr-unset profile`. The non-`openid` portion permutes differently between prediction and actual.

The agent did not commit on this dimension — explicitly cited SKILL.md invariant 10 (HashSet iteration on `Set<...>`) and `references/scope-resolution.md`'s `getScopeString` (DCSC.L188-212) lacking an order contract for the non-`openid` tokens. Per `prediction-target.md` line 19 ("A response that nails (1) and (2) but legitimately hedges (3) with a skill citation is a structurally complete pass"), the hedge is well-cited. ✓

## Verdict

**PASS** — same as prior run. Invariants 2, 6, 10, and 11 all carry correctly:
- Invariant 2 governs set membership and the default-true edge case.
- Invariant 6 keeps `fullScopeAllowed` out of scope-claim derivation.
- Invariant 10 anchors the legitimate hedge on inter-scope order.
- Invariant 11 explains the absence of `realm_access`/`resource_access` (collateral, not in target).

## Skill-edit recommendations from this re-run

The fresh predictor surfaced two small actionable observations:

1. Invariant 10 explicitly addresses the *mapper* set's HashSet iteration but does not extend the same warning to `getScopeString`'s iteration of `allowedClientScopes`. The agent applied invariant 10 by analogy. A one-line note in `references/scope-resolution.md` stating that `getScopeString` has no order contract for the non-`openid` portion would make the hedge derivable directly rather than by analogy.
2. The DCSC.L200 filter is described as "filters out the client itself," but the filter is `instanceof ClientModel`, not by name. When a `ClientScopeModel` is *named* identically to the client (the precise probe here), nothing in `scope-resolution.md` flags that they are distinct objects with different filter behavior. The agent had to derive this from the realm-config structure. An explicit note ("a ClientScopeModel sharing the client's `clientId` is not a ClientModel and survives DCSC.L200") would make this case fully citable.

Both are *strict-improvement* signals — neither would change a verdict, both would tighten a derivation. No regression in the current run.

## Comparison to prior round

Prior `diff.md` (preserved at `/tmp/adv-prev-2026-05-07/adv2-diff.md`) reached the same verdict via the same set commitment and the same invariant 10 hedge. No regression. No fix.
