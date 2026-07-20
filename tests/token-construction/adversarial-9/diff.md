# Diff — adversarial-9 prediction vs actual

## Headline

| | Value |
| --- | --- |
| Skill prediction (fresh-context agent, `prediction.json`) | `outcome=token_minted`, `aud_set={adv9-target-a}`, `resource_access_keys={adv9-target-a}` (trap row 5) |
| Actual on the wire (`actual-token-2.json`) | token minted; `aud="adv9-target-a"` (single string), `resource_access` keys `{adv9-target-a}` |
| Fixture verdict | **PASS** — both set commitments exact, committed with accurate skill citations; the intersect + `resource_access` prune (invariant 8) is now positively covered by a fresh predictor. |

## Harness note

This prediction was produced by a fresh-context Agent spawned at the
parent level, with no access to `actual-token-2*.json`,
`response-2-*.json`, `log*.txt`, `setup.md`, or `surprises.md`, and
with the chained-flow deny-list extension
(`skills/keycloak-token-fixture-build/` excluded — it carries
builder-side analysis of this seam). The subject token
(`subject-token.json`, embedded in `request-2.json`) was a permitted
input per harness.md §chained-flow addendum. The agent's tool call to
write `prediction.json` was the first time the prediction was
committed to the file. First two-leg fixture run under SKILL.md
harness invariant 9; ordering compliance confirmed in `setup.md` /
`surprises.md`.

## Dim 1 — `aud_set`

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `aud_set` | `{adv9-target-a}` | `{adv9-target-a}` (wire: single JSON string; string-vs-array explicitly unscored per prediction-target.md) | ✓ |

Predictor's chain: pre-restrict `aud` = `{adv9-target-a, adv9-target-b,
account}` from `AudienceResolveProtocolMapper` over the user's client
roles under `fullScopeAllowed=true` (SKILL.md invariant 6,
post-mapper.md L130-146), then `restrictRequestedAudience` intersects
with the requested set `{adv9-target-a}` (SKILL.md invariant 8,
post-mapper.md L10-47). Citations check out against the passages named.

## Dim 2 — `resource_access_keys`

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `resource_access_keys` | `{adv9-target-a}` | `{adv9-target-a}` | ✓ |

Predictor explicitly ruled out trap row 2 (aud pruned, `resource_access`
untouched) via the `removeIf(∉ audienceToSet)` line in post-mapper.md's
pseudocode, and trap row 3 (`account` exempt) by noting the intersect
carries no built-in-client exemption. Both rulings correct.

## Dim 3 — collateral claims (sanity check on the foundation)

| Claim | Actual | Skill-derivable from realm-config? | Notes |
| --- | --- | --- | --- |
| `azp` | `adv9-client` | ✓ | base-claims (`issuedFor`) |
| `scope` | `email profile` | ✓ | invariant 2; `roles`/`web-origins` have `include.in.token.scope=false` yet their mappers still ran — predictor invoked scope-resolution.md L121-128 correctly to keep the role mappers in play |
| `jti` prefix | `onrtte:` | ✗ (not in the skill's prefix table) | not a scored commitment; post-mapper.md's table lists only `trrtcc:`/`onrtcc:`/`oftcc:` — a known doc gap, see below |
| `sid` | present, equals subject-token `sid` | partially | skill hedges ("trigger logic differs per call site — a verifier must inspect each", post-mapper.md L117-128); actual is consistent with the TRANSIENT-only nulling |

## Where the skill held / where it failed

The skill held on everything scored. Invariant 8's mechanics
(intersect on `aud`, key-prune on `resource_access`, no exemptions,
order-independent post-loop) were sufficient for a fresh agent to
commit exactly, and the scope-resolution passages carried the
predictor past the `restrictedScopes` question (same client, no scope
param on either leg → identity filter).

One nuance the parent must record honestly: the seam was designed so
that a reader taking post-mapper.md L42-43 ("token exchange with a
`requested_token_type` that triggers audience narrowing") literally as
a **necessary** condition would land on trap row 1 — `request-2.json`
deliberately omits `requested_token_type`. The predictor did not take
that reading. It flagged the passage as ambiguous ("never enumerates
which values trigger narrowing nor the default when the parameter is
absent") and recovered via the L46-47 catch-all bullet plus the RFC
8693 default (`requested_token_type` defaults to access-token). So the
wording survived this fixture not because it is right — parent-side
source verification (2026-07-20, `StandardTokenExchangeProvider` at
26.5.5) confirms the trigger is the `audience` parameter, at L245-246
`params.getAudience() != null` guards the `REQUESTED_AUDIENCE_CLIENTS`
write — but because a careful reader can route around it. A less
careful reader remains exposed.

## Recommendation: skill changes from this fixture

None mandated. The skill's text was sufficient for a fresh-context
agent to commit correctly. This fixture is a positive regression test —
any future skill edit that weakens invariant 8's intersect-plus-prune
description should flip it to fail.

Two optional clarity edits are on the table for the human, supported by
the predictor's own feedback plus parent-side source verification, but
NOT authorized by this verdict (per verdict-rubric.md, PASS ⇒ no edit
required):

1. post-mapper.md L42-46 "When fires" — replace the
   `requested_token_type` attribution with the `audience` parameter
   (`StandardTokenExchangeProvider` L245-246), and note that
   `checkRequestedAudiences` (L277, L328-337) 400s when a requested
   audience is missing from the final token, making the empty-`aud`
   edge unreachable in a 200 on this path.
2. post-mapper.md jti-prefix table — add the `onrtte:` row for
   exchange-minted tokens (empirically anchored by this fixture's
   `actual-token-2-a/b.json`).

If either edit is made, re-run fresh predictors on adversarial-1..9
per harness.md's regression protocol.
