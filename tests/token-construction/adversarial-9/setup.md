# adversarial-9 — token-exchange `restrictRequestedAudience` narrowing (invariant 8)

## The seam

This is a **two-leg standard token-exchange fixture** probing invariant
8 of the target skill: *"`restrictRequestedAudience` runs after the
access-token mappers. If `Constants.REQUESTED_AUDIENCE_CLIENTS` is set
on the session ctx (token exchange / requested-audience refresh), `aud`
and `resource_access` are pruned post-mapper (TokenManager.L802-807,
L1406)."*

Leg 1 mints a subject access token via the password grant on
`adv9-client` (`fullScopeAllowed=true`), so `AudienceResolveProtocolMapper`
resolves the user's client roles into a pre-restrict audience of
`[adv9-target-a, adv9-target-b, account]` with matching
`resource_access` keys. Leg 2 exchanges that token
(`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`) with
`audience=adv9-target-a` and — load-bearingly — **no
`requested_token_type` and no `scope`**.

**Why omitting `requested_token_type` is the heart of the seam.** The
target skill's `references/post-mapper.md` ("When fires" list, ~L42-43)
attributes the narrowing trigger to a token-exchange request "with a
`requested_token_type` that triggers audience narrowing". That wording
is **wrong at 26.5.5**: verified against source
(`StandardTokenExchangeProvider.java` L245-246), the trigger is the
`audience` parameter alone — `REQUESTED_AUDIENCE_CLIENTS` is set iff
`params.getAudience() != null && !targetAudienceClients.isEmpty()`.
`requested_token_type` merely selects the output token type (default
`access_token`). A predictor that takes post-mapper.md's trigger
attribution literally will conclude that this request — which sends
`audience` but no `requested_token_type` — does NOT fire the narrowing,
and will land on trap 1 (full un-narrowed `aud`). That is exactly the
`fail-skill-gap` outcome this fixture exists to detect; the discrepancy
analysis lives in
`skills/keycloak-token-fixture-build/references/token-exchange.md` §"The
invariant-8 seam", which is on the predictor's MUST-NOT-read list.

The second jaw of the trap is the `resource_access` prune. Invariant 8
and post-mapper.md's pseudocode (`token.resourceAccess.keySet().removeIf(
clientId ∉ audienceToSet)`) both state that the intersect rewrites
`resource_access` too, not just `aud`. A reader who applies the `aud`
intersect but forgets the companion prune lands on trap 2; a reader who
exempts the built-in `account` audience lands on trap 3; a reader who
over-applies `checkRequestedAudiences` ("Requested audience not
available" → 400) to a *reachable* audience lands on trap 4. The seam
is designed per token-exchange.md so the requested audience survives
(the user holds `role-a` on `adv9-target-a`), which keeps the
empty-intersection edge — unreachable on a 200 on this path — out of
play and makes the observable the pruning of the *other* pre-restrict
members.

## Pre-mint expected values (builder's commitment)

- `outcome = token_minted` (HTTP 200; `checkRequestedAudiences` passes
  because `adv9-target-a` survives the intersect).
- `aud_set = {adv9-target-a}` — intersect of requested
  `{adv9-target-a}` with pre-restrict
  `{adv9-target-a, adv9-target-b, account}`.
- `resource_access_keys = {adv9-target-a}` — the removeIf drops
  `adv9-target-b` AND `account`.
- **Expected-correct trap-menu entry: #5.**
- Secondary expectations (not prediction targets): `jti` prefix
  `onrtte:`, `sid` present (online session, STEP.L279-281 nulling fires
  only on TRANSIENT), `issued_token_type` present in the response
  envelope, `azp = adv9-client`.

## Realm / client / user configuration

Realm: `adv-9` (fresh, prefixed `adv-` per the harness convention).
Default realm settings otherwise; access-token lifespan is the 26.5.5
default 300 s (bounds the window between leg 1 and the leg-2 mints).

Client: `adv9-client` (requesting client AND subject-token client)
- Confidential (`publicClient=false`), secret `adv9-secret-cafebabe`
  (masked as `**********` in the partial export).
- `directAccessGrantsEnabled=true` — mints the leg-1 subject token via
  the password grant.
- `standardFlowEnabled=false`, `implicitFlowEnabled=false`,
  `serviceAccountsEnabled=false` — out of scope for this seam.
- `fullScopeAllowed=true` — required so both target clients' roles
  resolve into the subject token's `aud`/`resource_access`
  pre-restrict.
- `attributes: {"standard.token.exchange.enabled": "true"}` — the
  per-client toggle for standard (V2) exchange
  (`OIDCConfigAttributes.STANDARD_TOKEN_EXCHANGE_ENABLED`, checked at
  STEP.L94). Verified preserved as string `"true"` in
  `realm-config.json`.
- Using the same client for both legs means `subject_token.azp ==`
  requesting client, so the audience-membership check at STEP.L169-171
  is bypassed — no audience mapper needed on the subject client.
- Default client scopes only (`web-origins`, `acr`, `profile`, `roles`,
  `basic`, `email`); no custom scopes or mappers — the seam is
  post-mapper, adding mappers would only add noise.

Client: `adv9-target-a`
- Confidential, secret `target-secret` (masked in export),
  `standardFlowEnabled=false`. Never called directly; exists only as an
  audience target.
- Client role `role-a`.

Client: `adv9-target-b`
- Identical shape: confidential, secret `target-secret`,
  `standardFlowEnabled=false`.
- Client role `role-b`.

User: `adv9-user` — **NOT in `realm-config.json`** (partial-export
never emits users; same as every prior fixture — adversarial-3
documents its user here in setup.md the same way). Full config:
- `username=adv9-user`, password `password` (non-temporary),
  `enabled=true`, `emailVerified=true`, `requiredActions=[]`.
- `firstName=Adv`, `lastName=Nine`, `email=adv9@example.test` —
  populated because the realm's `verify-profile` authenticator demands
  them for the password grant even with `requiredActions=[]` (see
  adversarial-1's surprises.md).
- Client-role mappings: `role-a` on `adv9-target-a` AND `role-b` on
  `adv9-target-b`. These mappings are what put both targets into the
  subject token's pre-restrict audience.

Everything else the partial export omits: client secrets (masked,
values recorded above), user + credentials + role mappings (recorded
above). Nothing else was configured off-export.

## The two requests

### Leg 1 — subject-token mint (`request-1.json`)

```
POST /realms/adv-9/protocol/openid-connect/token
grant_type=password
client_id=adv9-client
client_secret=adv9-secret-cafebabe
username=adv9-user
password=password
```

No `scope` param → default scopes only (`scope: "email profile"` in the
token; no `openid`, no ID token — irrelevant to the seam). Decoded
payload published as `subject-token.json` (public input, deliberately
NOT named `actual-token-1.json`). Captured pre-restrict values:
`aud = [adv9-target-a, adv9-target-b, account]`, `resource_access` keys
`{adv9-target-a, adv9-target-b, account}`, `jti` prefix `onrtro:`.

### Leg 2 — the exchange (`request-2.json`, the token under test)

```
POST /realms/adv-9/protocol/openid-connect/token
grant_type=urn:ietf:params:oauth:grant-type:token-exchange
client_id=adv9-client
client_secret=adv9-secret-cafebabe
subject_token=<the literal leg-1 JWT>
subject_token_type=urn:ietf:params:oauth:token-type:access_token
audience=adv9-target-a
```

**No `requested_token_type`** (defaults to `access_token`; its absence
is the trigger-attribution trap — see "The seam") and **no `scope`**
(no down-scoping noise). `request-2.json` was frozen by hand
immediately after leg 1, before this file and prediction-target.md were
written, and before any exchange mint.

## Plausible outputs (the trap menu)

Same five entries as prediction-target.md; the builder's expected-correct
entry is marked here (never in the public file).

1. `aud_set = {adv9-target-a, adv9-target-b, account}`,
   `resource_access_keys` likewise full — reader who concluded no
   audience narrowing fires on this request (the post-mapper.md
   `requested_token_type` trigger misread; this is the misread the
   fixture is aimed at).
2. `aud_set = {adv9-target-a}`,
   `resource_access_keys = {account, adv9-target-a, adv9-target-b}` —
   reader who applied the `aud` intersect but missed the
   `resource_access` prune.
3. `aud_set = {adv9-target-a, account}`, `resource_access` pruned to
   match — reader who thinks built-in/service audiences are exempt from
   the intersect.
4. HTTP 400 / no token minted — reader who over-applied the "requested
   audience not available" rejection to a reachable audience.
5. `aud_set = {adv9-target-a}`,
   `resource_access_keys = {adv9-target-a}`. **← expected correct.**

## Minimum specificity to pass

Both sets concrete (or `http_400_no_token` with both `null`). No
either/or across trap rows; no unresolved "depends on
`requested_token_type`" — the request is public and omits it. Single-
audience string-vs-array serialization is explicitly not scored.

## Determinism check plan

Mint leg 2 twice (`exchange a`, `exchange b`) **against the same
subject token** (`subject-token.jwt`, pinned input). Strip set:
`iat, exp, jti, auth_time, session_state, sid, nbf` via
`jq -S 'del(...)'`; additionally the `jti` prefix (before the colon)
must be identical across both mints — expected `onrtte:`. The fields
under test (`aud`, `resource_access`) are NOT in the strip set; any
a/b diff in them is a fixture failure requiring redesign. If the
subject token expires (300 s) before both mints complete, re-mint leg
1 and re-freeze `request-2.json`/`subject-token.json`, note it in
surprises.md, and leave prediction-target.md untouched (its targets
reference no volatile leg-1 values).

## Resolution after capture

(The bullets below were drafted pre-mint as the builder's expectations
and verified verbatim against the captures post-mint — every claim
held; see surprises.md §3 for the protocol note.)

- **Both leg-2 mints returned HTTP 200** with `issued_token_type:
  urn:ietf:params:oauth:token-type:access_token` in the envelope, no
  `refresh_token` (`refresh_expires_in: 0`).
- **`aud` = `"adv9-target-a"`** (single value, serialized as a JSON
  string on the wire — set `{adv9-target-a}`; serialization shape not
  scored per prediction-target.md).
- **`resource_access` keys = `{adv9-target-a}`** — `adv9-target-b` AND
  `account` both pruned. `realm_access` untouched (the prune rewrites
  `resource_access` only).
- Trap-menu entry **#5** is the actual outcome, matching the pre-mint
  expectation. No 6th trap needed.
- `jti` prefix `onrtte:` on both mints (suffixes
  `46daeeef-…` / `861fbaaf-…` varied); `sid` present and identical
  across both mints AND identical to the subject token's `sid`
  (`kMdCV-wvlOh9TFD2r4pySXDQ` — same user session);
  `scope: "email profile"` carried over unchanged.
- Determinism: `jq -S` payloads stripped of
  `iat,exp,jti,auth_time,session_state,sid,nbf` byte-identical between
  a and b; `actual-token-2-a.json` copied to `actual-token-2.json`.
- Subject token did NOT need re-minting; both mints completed ~168 s
  before the subject `exp`.
- Log evidence: `log-2-*.txt` each carry the `type="TOKEN_EXCHANGE"`
  event line with `audience="adv9-target-a"`,
  `token_id="onrtte:…"`, and — notably —
  `requested_token_type="urn:ietf:params:oauth:token-type:access_token"`
  even though the request omitted that parameter (the event logs the
  server-side *default*, not the wire request; see surprises.md §1).
