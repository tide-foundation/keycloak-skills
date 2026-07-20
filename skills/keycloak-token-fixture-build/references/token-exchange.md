# Token-exchange fixtures (chained two-leg flows)

How to build a fixture whose token under test is minted by **standard
token exchange** (`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`)
on stock Keycloak 26.5.5. Exchange fixtures are **two-leg**: leg 1 mints
a subject token; leg 2 exchanges it. That chaining breaks two of the
single-leg harness rules, so this file amends them explicitly. Everything
not amended here works exactly as for single-leg fixtures.

> Source refs are at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak)
> tag `26.5.5`, same convention as the target skill. `STEP.L94` means
> [`services/src/main/java/org/keycloak/protocol/oidc/tokenexchange/StandardTokenExchangeProvider.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/tokenexchange/StandardTokenExchangeProvider.java)
> line 94.

## Scope: standard (V2) exchange only

- Standard token exchange is a **default-enabled server feature** on
  stock 26.5.5 (`Profile.Feature.TOKEN_EXCHANGE_STANDARD_V2`,
  `Type.DEFAULT`, `common/.../Profile.java:80`) — the fixture stack's
  `docker-compose.yml` needs no `KC_FEATURES` edit. Only a per-client
  toggle is required (see recipe).
- Legacy V1 exchange (`V1TokenExchangeProvider`) needs the preview
  `token-exchange` feature flag (`Profile.java:79`, `Type.PREVIEW`)
  plus fine-grained admin permissions — a compose change. External-to-
  internal V2 (`ExternalToInternalTokenExchangeProvider`) is
  EXPERIMENTAL (`Profile.java:81`). Both **out of scope** for fixtures
  until the stack grows a feature profile. Don't try to probe them on
  the stock stack; the request will route to the standard provider or
  fail.

## Protocol amendments for chained flows

### Amendment 1 — pre-mint commitment applies to the token under test

Harness invariant 1 ("write `prediction-target.md` before any token is
minted") is impossible verbatim: `request-2.json` must embed the literal
`subject_token` JWT, which cannot exist before leg 1 is minted. The
amended ordering:

```
1. Build realm (recipe below), export realm-config.json
2. Mint leg 1 (subject token)            ← allowed pre-commitment
3. Freeze request-2.json + subject-token.json
4. Write prediction-target.md + trap menu   ← commitment point
5. Mint leg 2 (exchange), twice for determinism
6. Capture logs, write actual-token-2.json
```

The commitment point moves between the legs. Two hard rules keep the
commitment meaningful:

- **Prediction targets may only concern the exchanged token (leg 2).**
  Everything in the subject token is a *given input*, not a prediction
  target. A fixture whose target is derivable by copying a field out of
  `subject-token.json` is not probing the skill.
- **Targets must not reference volatile leg-1 values** (`jti`, `iat`,
  `exp`, `sid`, `session_state` of the subject token). Then, if the
  subject token expires mid-build and must be re-minted, you re-freeze
  `request-2.json` / `subject-token.json` without invalidating the
  committed targets. If a target would break under subject re-mint, the
  seam is wrongly coupled to leg 1 — redesign.

### Amendment 2 — the subject token is a public artifact

The predictor **may** read the subject token. It is embedded in
`request-2.json` (a MAY-read file) and base64-decodable anyway; treating
it as contamination would make the predictor's rules self-contradictory.
The ruling: the subject token is an *input* to the function under test,
exactly like `realm-config.json`. To make this unambiguous, the builder
publishes it decoded:

| Artifact | Predictor | Content |
| --- | --- | --- |
| `request-1.json` | MAY read | Leg-1 mint request (adversarial-3 JSON shape) |
| `subject-token.json` | MAY read | Decoded leg-1 access-token payload |
| `request-2.json` | MAY read | Exchange request; `form.subject_token` is the literal JWT |
| `actual-token-2.json` | MUST NOT read | Decoded exchanged-token payload |
| `log-1.txt`, `log-2*.txt` | MUST NOT read | Bracketed container logs |

The `actual-token*` / `log*` deny-list from `harness.md` is unchanged —
leg-1's decoded payload deliberately gets a *different* filename
(`subject-token.json`, never `actual-token-1.json`) so the existing
deny-list stays correct verbatim. When spawning the predictor, add
`subject-token.json` to the MAY-read list and state Amendment 2's
ruling in the prompt (see `harness.md` §chained-flow addendum).

### Determinism check for two-leg fixtures

Run both determinism mints of leg 2 **against the same subject token**.
That pins the input; any diff between the two exchanged tokens is then
attributable to the exchange leg itself. Strip set is unchanged
(seam-design.md Step 6). The `jti` *prefix* of the exchanged token must
be stable across mints — live capture on 26.5.5 shows exchange-minted
access tokens carry the `onrtte:` prefix (ONLINE session, token-exchange
grant axis), and `sid` is retained (the `STEP.L279-281` nulling fires
only on TRANSIENT, same check as `OAuth2GrantTypeBase`).

Subject-token lifetime is the realm's access-token lifespan — **300
seconds** on a fresh 26.5.5 realm (live-measured `exp − iat`). Both
leg-2 mints plus the prediction-target write fit comfortably; if a
seam needs longer, raise the realm's `accessTokenLifespan` **before**
leg 1 rather than re-minting between the two leg-2 mints.

## Realm recipe

Minimum config for an exchange fixture, on top of seam-design.md Step 4:

1. **Requesting client** (the one that calls the exchange): confidential
   (`publicClient=false` — public clients are rejected at STEP.L152-156),
   `directAccessGrantsEnabled=true` if it also mints the subject token,
   and the toggle:
   ```json
   "attributes": { "standard.token.exchange.enabled": "true" }
   ```
   (`OIDCConfigAttributes.STANDARD_TOKEN_EXCHANGE_ENABLED`, checked via
   `OIDCAdvancedConfigWrapper.isStandardTokenExchangeEnabled` at
   STEP.L94. Off → 400 "Standard token exchange is not enabled for the
   requested client".) Verify the attribute survives in the
   `realm-config.json` export — it does, as a string `"true"`.
2. **Subject-token client**: simplest is the requesting client itself.
   When `subject_token.azp` (`issuedFor`) equals the requesting client,
   the audience-membership check is **bypassed** (STEP.L169-171:
   `if (!client.equals(tokenHolder)) forbiddenIfClientIsNotWithinTokenAudience(token)`).
   If you use a *different* subject client, the requesting client must
   appear in the subject token's `aud` (add an audience mapper on the
   subject client) or leg 2 fails 403.
3. **User**: password-grant user with `firstName`, `lastName`, `email`
   set (same verify-profile requirement as single-leg fixtures).
4. **Audience targets** (only if the seam involves `aud` narrowing):
   one or more extra clients the user holds client roles on, so
   `AudienceResolveProtocolMapper` populates a multi-valued `aud`
   pre-restrict.

## The exchange request (leg 2)

```
POST /realms/{realm}/protocol/openid-connect/token
grant_type=urn:ietf:params:oauth:grant-type:token-exchange
client_id=...&client_secret=...
subject_token=<leg-1 access token>
subject_token_type=urn:ietf:params:oauth:token-type:access_token
[audience=<clientId>]            ← drives aud narrowing (see below)
[scope=<names>]                  ← ADD-ONLY on a stock realm (see table)
[requested_token_type=...]       ← default access_token
```

Verified request-surface facts (all STEP at 26.5.5):

| Parameter | Behaviour | Source |
| --- | --- | --- |
| `subject_token_type` | Required; **access tokens only** — anything else → "Parameter 'subject_token' supports access tokens only" | L105-113 |
| `subject_token` | Verified as an identity token (`AuthenticationManager.verifyIdentityToken`); invalid/expired → 400 `invalid_token` | L126-133 |
| `subject_issuer` | **Not supported** on the standard path. External-to-internal exchange lives in legacy V1 (preview) or in `ExternalToInternalTokenExchangeProvider` behind the EXPERIMENTAL `token-exchange-external-internal:v2` feature (`Profile.java:81`) — both off on the stock stack | L88-92 |
| `audience` | Resolves to client models; disabled audience client → 400 `invalid_client` (validateAudience, L159-166). Resolved list → `Constants.REQUESTED_AUDIENCE_CLIENTS` on the session ctx | L159-166, L245-246 |
| `scope` | `TokenManager.isValidScope` gate; then included **"as is"** — the param only *adds* optional scopes to the candidate set, exactly like a normal token request. It does NOT populate `restrictedScopes`: STEP.L233 passes `context.getRestrictedScopes()` (`TokenExchangeContext.java:128-133`, server-spi-private), whose setter has exactly ONE caller in the whole 26.5.5 tree — `DownscopeAssertionGrantEnforcerExecutor.java:65`, a **client-policy executor**. With no client policy configured (stock realm), `restrictedScopes` is null and the DCSC filter is inert — an exchange `scope` param can never shrink the mapper set on a stock realm. Empirically anchored by fixture `adversarial-10` (subject-token marker claim, `sub`, and full scope set all survived `scope=profile`). | L185-200, L233 |
| `scope=offline_access` | Rejected: 400 "Scope offline_access not allowed for token exchange" | L235-241 |
| `requested_token_type` | Default `access_token`. Supported: `access_token`, `id_token`, `refresh_token`. `refresh_token` additionally requires client `useRefreshToken` + `standard.token.exchange.enableRefreshRequestedTokenType` ≠ NO. Note: `saml2` passes the type gate (L351-354) but the standard provider rejects it later with the same "requested_token_type unsupported" error | L345-366, L322-326 |
| `requested_token_type=refresh_token` + `audience` | Audience narrowing **persists across refreshes**: the exchange writes the requested audience into the refresh token as claim `req-aud` (`TokenManager.java:1205`, `Constants.java:212`); every subsequent refresh reads it back and re-sets `REQUESTED_AUDIENCE_CLIENTS` (`TokenManager.java:340-347`) — no request parameter involved on the refresh leg | TM L1205, L340-347 |
| Response | Envelope gains `issued_token_type`; for `id_token` requests the ID token is returned **in the `access_token` field** per RFC 8693 | L303, L289-295 |

## The invariant-8 seam (`restrictRequestedAudience`)

**Status: executed as `adversarial-9` (verdict PASS)** — the sketch
below is the as-built design, kept as the template for exchange seams.
Two facts shape it:

1. **The narrowing trigger is the `audience` parameter, not
   `requested_token_type`.** `REQUESTED_AUDIENCE_CLIENTS` is set iff
   `params.getAudience() != null && !targetAudienceClients.isEmpty()`
   (STEP.L245-246). ⚠ **Known discrepancy**: the target skill's
   `references/post-mapper.md` L42-43 currently attributes the trigger
   to `requested_token_type`. That wording is **wrong at 26.5.5**
   (verified against source, 2026-07-20). Outcome when tested: the
   adversarial-9 fresh predictor flagged the passage as ambiguous but
   recovered via the L46-47 catch-all bullet plus the RFC 8693 default
   and committed correctly — verdict PASS, so the target-skill
   correction is an *optional clarity edit* (human decision, see
   `adversarial-9/diff.md`), not verdict-mandated. Keep the fact above
   as the build-side truth, keep the un-narrowed-`aud` shape in any
   trap menu that reuses this seam, and do **not** leak this note into
   any MAY-read artifact — regression re-runs still need clean
   predictors. Because this file carries the discrepancy analysis,
   exchange-fixture predictors must have
   `skills/keycloak-token-fixture-build/` on their MUST-NOT-read list
   (see harness.md §chained-flow addendum).
2. **The empty-intersection edge is unreachable on a success
   response.** `checkRequestedAudiences` (called at STEP.L277, body
   L328-337) runs *after* `generateAccessToken()` — i.e. after mappers
   and `restrictRequestedAudience` — and 400s with "Requested audience
   not available" if any requested audience is missing from the final
   `aud`. So the zero-length-`aud`-array edge documented in the target
   skill's post-mapper.md can never appear in a captured 200 response
   on this path. Design the seam so the requested audience *survives*
   (user holds a role on it) and the observable is the **pruning of
   the other pre-restrict `aud` members**.

Concrete seam sketch: user holds client roles on `target-a` and
`target-b`; requesting client has `fullScopeAllowed=true` so both reach
`aud` pre-restrict; leg 2 passes `audience=target-a` and **no**
`requested_token_type`. Correct prediction: `aud` = `target-a` only
(plus any surviving mapper-added members that intersect), and
`resource_access` keys pruned to match. Trap menu candidates:

1. `aud` contains both targets — reader concluded no narrowing fires
   because no `requested_token_type` was sent (the post-mapper.md L42-43
   misread — see discrepancy note above).
2. `aud` = `target-a` ∪ mapper output un-pruned, `resource_access`
   untouched — reader applied the intersect to `aud` but missed the
   `resource_access` prune.
3. `aud` replaced wholesale by the `audience` param even if no mapper
   emitted it — reader modelled "replace", not "intersect".
4. 400 error — reader over-applied `checkRequestedAudiences` to a
   reachable audience.
5. Correct: intersect + `resource_access` prune.

## Capture tooling

`scripts/capture-exchange.sh` (this skill) runs the two legs with the
same timestamp-bracketed log capture as the target skill's
`capture-tokens.sh`. It is split into subcommands **because the
commitment point sits between the legs**:

```
# From the fixture directory (tests/token-construction/adversarial-N/):
REALM=adv-N SUBJECT_CLIENT_ID=... SUBJECT_CLIENT_SECRET=... \
  USERNAME=... PASSWORD=... \
  ../../../skills/keycloak-token-fixture-build/scripts/capture-exchange.sh subject

#   → request-1.json, subject-token.json, subject-token.jwt, log-1.txt
#   Now write prediction-target.md. Then:

REALM=adv-N EXCHANGE_CLIENT_ID=... EXCHANGE_CLIENT_SECRET=... \
  AUDIENCE=target-a \
  ../../../skills/keycloak-token-fixture-build/scripts/capture-exchange.sh exchange a
REALM=adv-N EXCHANGE_CLIENT_ID=... EXCHANGE_CLIENT_SECRET=... \
  AUDIENCE=target-a \
  ../../../skills/keycloak-token-fixture-build/scripts/capture-exchange.sh exchange b

#   → request-2.json, actual-token-2-a.json / -b.json, response-2-*.json, log-2-*.txt
#   Diff the two -a/-b payloads per seam-design.md Step 6, then keep
#   one as actual-token-2.json.
```

`subject-token.jwt` (the raw JWT, consumed by the `exchange`
subcommand) is builder plumbing — don't list it either way for the
predictor; its decoded content is already public as
`subject-token.json`.

## Live verification

Durable empirical anchors now exist as fixtures:
`tests/token-construction/adversarial-9/` (audience narrowing +
`resource_access` prune, PASS) and `adversarial-10/` (`restrictedScopes`
provenance — scope param add-only on a stock realm, PASS with
source-escape). The original smoke-test run (stock stack, throwaway
realm, 2026-07-20, via `scripts/capture-exchange.sh`) established:

- Exchange succeeds with only the `standard.token.exchange.enabled`
  client attribute — no compose change.
- `audience=target-a` with **no** `requested_token_type` narrowed
  `aud` from `[target-a, target-b, account]` to `target-a` and pruned
  `resource_access` to match. The no-audience control mint kept all
  three — the narrowing trigger is the `audience` param, live-proven.
- Unreachable audience → 400
  `"Requested audience not available: <clientId>"` — the
  empty-`aud` edge did not mint.
- Exchanged-token `jti` prefix `onrtte:` on both determinism mints
  (suffix varied); `sid` present and identical across mints (same
  subject session); `issued_token_type` present in the envelope;
  stripped payloads byte-identical.

## Anti-patterns

- **Predicting leg-1 claims.** The subject token is input. If your
  trap menu has a leg-1 row, the seam is wrong.
- **Using `audience` to point at a client the user has no roles on**
  (and that no mapper emits): leg 2 400s at `checkRequestedAudiences`
  — you get an error fixture, not a claims fixture.
- **Probing V1 semantics** (impersonation, `subject_issuer`,
  external-internal) on the stock stack.
- **Re-minting the subject token between the two determinism mints.**
  The input must be pinned for the diff to mean anything.
- **Designing a down-scoping seam around the exchange `scope` param.**
  On a stock realm it cannot shrink anything — `restrictedScopes` stays
  null (see the `scope` row above; refuted premise of adversarial-10's
  original design). A real down-scoping seam requires configuring a
  `DownscopeAssertionGrantEnforcerExecutor` client policy first.
- **`requested_token_type=refresh_token` without both client flags**
  (`useRefreshToken` + `standard.token.exchange.enableRefreshRequestedTokenType`):
  400 "requested_token_type unsupported".
