# Diff — adversarial-3 fresh-context prediction vs actual (re-run 2026-05-07)

This file scores `prediction-fresh.json` (a fresh-context agent's prediction, written with no access to `actual-token-*.json`, logs, setup, surprises, or any prior prediction) against the actual minted tokens.

## Headline

| | client_credentials | password (ROPC) |
| --- | --- | --- |
| Predicted `(sid, jti-prefix)` | `(absent, trrtcc)` | `(present, onrtro)` |
| Actual `(sid, jti-prefix)` | `(absent, trrtcc:105e3caa-…)` | `(present `47kTGgur5MzdlPXrEmc5vbyE`, onrtro:55848206-…)` |
| Per-token verdict | **PASS** (exact) | **PASS** (exact) |
| Overall verdict | **PASS** — both commitments landed exactly |
| vs. prior fresh round | **unchanged** (was `pass`, still `pass`) |

## Harness note

Re-run on 2026-05-07 against the current `keycloak-token-construction/SKILL.md` and references. Fresh-context predictor spawned at the parent level; prior `prediction.json`, `prediction-fresh.json`, `diff.md`, and `diff-fresh.md` were moved out of the fixture directory before spawn. The agent's first write to `prediction-fresh.json` is the prediction commitment.

## Dim 1 — `client_credentials` token

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `sid` presence | absent | absent (no `sid` key in payload) | ✓ |
| `jti` prefix (six chars) | `trrtcc` | `trrtcc` | ✓ |
| Decomposition `tr/on/of` | `tr` (TRANSIENT) | `tr` | ✓ |
| Decomposition `rt/ft` | `rt` (refresh-token-context default) | `rt` | ✓ |
| Decomposition grant family | `cc` (client_credentials) | `cc` | ✓ |

Reasoning chain the agent produced:
1. `realm-config.json` for `adv3-client` (L693-697) does not contain `client_credentials.use_refresh_token` in its `attributes` map.
2. Per `references/post-mapper.md` defaults table, this means the `OIDCConfigAttributes.USE_REFRESH_TOKEN_FOR_CLIENT_CREDENTIALS_GRANT` attribute defaults to `"false"`, so `useRefreshToken() = false`.
3. Both transient-nulling conditions hold (useRefreshToken=false ∧ encoded session type TRANSIENT) → `accessToken.setSessionId(null)` at L132 → `JsonInclude.NON_NULL` (invariant 11) drops `sid`.
4. `jti` prefix `tr` (TRANSIENT) + `rt` (default) + `cc` (cc grant) = `trrtcc`.

## Dim 2 — `password` (ROPC) token

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `sid` presence | present | present (`47kTGgur5MzdlPXrEmc5vbyE`) | ✓ |
| `jti` prefix (six chars) | `onrtro` | `onrtro` | ✓ |
| Decomposition `tr/on/of` | `on` (ONLINE) | `on` | ✓ |
| Decomposition `rt/ft` | `rt` (refresh-token-context default) | `rt` | ✓ |
| Decomposition grant family | `ro` (ROPC) | `ro` | ✓ |

Reasoning chain:
1. `OAuth2GrantTypeBase.java:398` defaults `useRefreshToken()` to `true` for the password grant.
2. With `useRefreshToken()=true`, the L120 if-branch fires; the L130 transient check is never evaluated → `sid` retained.
3. The session is online (no `offline_access` in the requested `scope` param).
4. Prefix `on` + `rt` + `ro` = `onrtro`.

## Dim 3 — trap-menu compliance

`prediction-target.md` enumerates five plausible-but-wrong shapes. The fresh prediction explicitly ruled out four with skill citation:

| Trap | Skill argument used to rule it out | Match (actual) |
| --- | --- | --- |
| Both have `sid`, both `onrt…` | invariant 12: cc with default attr → transient/null path | ✓ ruled out, actual cc has `sid` absent |
| Neither has `sid` | invariant 12: ROPC default `useRefreshToken=true` → L120 if-branch | ✓ ruled out, actual pwd has `sid` |
| `oftcc:` for cc | `offline_access` is optional, not requested → ONLINE/TRANSIENT not OFFLINE | ✓ ruled out, actual is `trrtcc:` |
| `sid` present on cc because "session exists server-side" | invariant 12: post-mapper null is in-memory; NON_NULL drops on the wire | ✓ ruled out, actual cc has `sid` absent |

The fresh prediction selected option 5 (the correct combination) and landed both pairs exactly.

## Verdict

**PASS** on both grants — same as prior run. Invariant 12 + the `references/post-mapper.md` defaults table + the prefix decoder are jointly sufficient for a fresh-context agent to derive both `(sid_presence, jti_prefix)` pairs from the documented contract alone.

## Skill-edit recommendations from this re-run

The fresh predictor surfaced two actionable observations:

1. The `ro` letter for ROPC is named in invariant 12 and prediction-target.md but is NOT directly anchored by a positive-control fixture in the skill (only `cc` is, via `token-openid.json` and `token-with-refresh-openid.json`). The agent committed correctly via elimination ("ROPC must use a non-cc family code; the only one named is `ro`"). A grant-family letter table in invariant 12 or the `post-mapper.md` "Diagnostic — read the `jti` prefix" section (`cc` → client_credentials, `ro` → ROPC, `co` → authorization_code, …) would make this derivation explicit rather than by elimination.
2. The `ft` (refresh-token-free) letter pair is named in the prefix decomposition rule but the skill does not say when an `ft` (rather than `rt`) second pair would surface on the wire. Adding a one-liner clarifying the conditions for `ft` (or noting it is unreachable on these grant flows) would close the loop on the second pair's letter range.

Both are strict-improvement signals; neither would change a verdict.

## Comparison to prior round

Prior `diff-fresh.md` (preserved at `/tmp/adv-prev-2026-05-07/adv3-diff-fresh.md`) reached the same verdict via the same invariant 12 + post-mapper.md path. No regression. The skill text on invariant 12 still produces both correct pairs.
