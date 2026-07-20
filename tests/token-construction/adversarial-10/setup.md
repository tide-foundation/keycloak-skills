# adversarial-10 — token-exchange `restrictedScopes` shrinks the mapper set (scope-resolution `isAllowed` + mapper-set-assembly)

## The seam

This is a **two-leg standard token-exchange fixture** probing the
`restrictedScopes` seam: the exchange leg's `scope` parameter feeds
`restrictedScopes` into the `DefaultClientSessionContext` ctor
(`StandardTokenExchangeProvider` L186-200, L233 — see the fixture-build
skill's token-exchange.md request-surface table), which filters the
allowed-scope set via `isAllowed` (target skill
`references/scope-resolution.md`, DCSC.L252-267: *"if restrictedScopes
!= null and s.name ∉ restrictedScopes: return false"*) and therefore
shrinks the mapper set (target skill
`references/mapper-set-assembly.md` L98-100: *"`restrictedScopes`
(token exchange) changes which scopes pass `isAllowed`, which changes
which mappers are pulled into the union. Token exchange can therefore
see a strictly smaller mapper set than the unrestricted issuance."*).

Leg 1 mints a subject token via the password grant with **no scope
param** → all default scopes apply, including the custom default scope
`adv10-scope` whose only mapper hardcodes `adv10_marker: "present"`
into the access token, and `basic` whose `SubMapper` writes `sub`
(SKILL.md invariant 1: `initToken` sets `sub` only on TRANSIENT
sessions; for this persistent online session `sub` is mapper
territory). Leg 2 exchanges that token with `scope=profile` — and
nothing else. Three independent observables then triangulate the one
mechanism:

1. `adv10_marker` — survives iff `adv10-scope`'s mapper is still in
   the mapper set. It is filtered out iff `restrictedScopes` =
   {profile} excludes `adv10-scope` from `isAllowed`.
2. `sub` — survives iff `basic` (a built-in default scope) is still in
   the allowed set so SubMapper runs. This is the second jaw of the
   trap: a reader can accept that custom scopes get down-scoped away
   (dropping the marker) while assuming built-ins like `basic` are
   immune (trap 2). If the filter is uniform, SubMapper is gone,
   invariant 1 says `initToken` left `sub` null (persistent session),
   and invariant 11 (NON_NULL wire serialization) deletes the key.
3. `scope` claim — `getScopeString()` over the *allowed* set (SKILL.md
   invariant 2), not the request param echoed and not the subject
   token's scope claim. With allowed = {profile} (+client, filtered
   out at DCSC.L200), the claim is exactly `"profile"` — no `openid`
   attachment (original exchange scope param has no `openid`).

The misreads the seam separates: "exchange copies claims / inherits
the subject mapper set" (trap 1); "built-in defaults are immune to
restrictedScopes" (trap 2); "down-scoping must be a subset of the
subject token's scope claim, else 400" (trap 4 — actually
`TokenManager.isValidScope` validates against the *client's*
registered scopes, and `profile` is a default client scope, so it
passes); "restrictedScopes only rewrites the scope string, not the
mapper set" (trap 5). Only a reader who runs the full chain
scope-param → restrictedScopes → isAllowed → mapper-set union →
invariant 1 → invariant 11 lands on trap 3.

## Pre-mint expected values (builder's commitment)

- `outcome = token_minted` (HTTP 200; `profile` is a registered
  default client scope of `adv10-client`, so pre-flight
  `isValidScope` passes; `scope=offline_access` is the only
  specially-rejected name on the exchange path).
- `adv10_marker = ABSENT` — `adv10-scope` ∉ restrictedScopes
  {profile} → fails `isAllowed` → its hardcoded-claim mapper is not in
  the union.
- `sub = ABSENT` — `basic` ∉ {profile} → SubMapper filtered out with
  the rest; persistent (online) session so `initToken` never set
  `sub` (invariant 1); null → dropped from wire (invariant 11).
- `scope_claim_multiset = {profile}` — exactly one name.
- **Expected-correct trap-menu entry: #3.**

### Collateral expectations (not prediction targets)

- `email` and `email_verified` ABSENT — the `email` scope is filtered
  out the same way, its UserPropertyMappers never run.
- `aud` ABSENT — `roles` scope filtered → `AudienceResolveProtocolMapper`
  gone → no audience written by anyone → null → NON_NULL drops it
  (base-claims.md: `aud` is mapper-only on the access token). The
  subject token's `aud: "account"` is NOT inherited.
- `realm_access` / `resource_access` ABSENT — `roles` scope filtered →
  `UserRealmRoleMappingMapper` / `UserClientRoleMappingMapper` gone.
- `profile`-scope mappers still fire: `name = "Adv Ten"`,
  `preferred_username = "adv10-user"`, `given_name = "Adv"`,
  `family_name = "Ten"` all PRESENT.
- Base claims untouched by the filter: `azp = adv10-client`, `iss`,
  `typ = Bearer`, `acr` (initToken branch, step-up off), `sid`
  PRESENT and equal to the subject token's `sid` (same online user
  session; the STEP.L279-281 nulling fires only on TRANSIENT), `jti`
  prefix `onrtte:` (online session, token-exchange grant axis).
- Response envelope: `issued_token_type =
  urn:ietf:params:oauth:token-type:access_token`, no refresh token.

## Realm / client / scope / mapper / user configuration

Realm: `adv-10` (fresh, prefixed `adv-` per the harness convention).
Default realm settings otherwise; access-token lifespan is the 26.5.5
default 300 s (bounds the window between leg 1 and the leg-2 mints).

Client scope: `adv10-scope`
- Protocol `openid-connect`, attributes
  `{"include.in.token.scope": "true"}` (explicit true so its name
  provably belongs in the subject token's `scope` claim — making its
  *disappearance* from the exchanged token's claim attributable to
  `isAllowed`, not to the include-in-token-scope filter).
- ONE protocol mapper: `oidc-hardcoded-claim-mapper` named
  `adv10-marker-mapper`, config `claim.name=adv10_marker`,
  `claim.value=present`, `jsonType.label=String`,
  `access.token.claim=true`, `id.token.claim=false`,
  `userinfo.token.claim=false`. Hardcoded-claim chosen per
  seam-design.md: deterministic value, zero user/role/session
  dependency — the ONLY way it can vanish is the mapper leaving the
  set.

Client: `adv10-client` (requesting client AND subject-token client)
- Confidential (`publicClient=false`), secret `adv10-secret-feedface`
  (masked as `**********` in the partial export).
- `directAccessGrantsEnabled=true` — mints the leg-1 subject token via
  the password grant.
- `standardFlowEnabled=false`, `implicitFlowEnabled=false`,
  `serviceAccountsEnabled=false` — out of scope for this seam.
- `fullScopeAllowed=true` — irrelevant to the mapper set (SKILL.md
  invariant 6) but keeps the subject token's role claims populated as
  leg-1 givens.
- `attributes: {"standard.token.exchange.enabled": "true"}` — the
  per-client toggle for standard (V2) exchange, preserved as string
  `"true"` in `realm-config.json` (verified).
- Same client on both legs → `subject_token.azp` == requesting client
  → the audience-membership check (STEP.L169-171) is bypassed.
- Default client scopes: the six built-ins (`web-origins`, `acr`,
  `roles`, `profile`, `basic`, `email`) **plus `adv10-scope`**
  (assigned via PUT `/default-client-scopes/{scopeId}`; verified in
  the export's `defaultClientScopes` list). No optional scopes beyond
  the realm defaults; none are requested.

User: `adv10-user` — **NOT in `realm-config.json`** (partial-export
never emits users; same as every prior fixture). Full config:
- `username=adv10-user`, password `password` (non-temporary),
  `enabled=true`, `emailVerified=true`, `requiredActions=[]`.
- `firstName=Adv`, `lastName=Ten`, `email=adv10@example.test` —
  populated because the realm's `verify-profile` authenticator demands
  them for the password grant (adversarial-1's surprises.md).
- No extra role mappings — only the realm defaults
  (`default-roles-adv-10`).

Everything else the partial export omits: client secret (masked,
value recorded above), user + credentials (recorded above). Nothing
else was configured off-export.

## The two requests

### Leg 1 — subject-token mint (`request-1.json`)

```
POST /realms/adv-10/protocol/openid-connect/token
grant_type=password
client_id=adv10-client
client_secret=adv10-secret-feedface
username=adv10-user
password=password
```

No `scope` param → all default scopes apply. Decoded payload published
as `subject-token.json` (public input, deliberately NOT named
`actual-token-1.json`). Leg-1 givens captured there:
**`adv10_marker: "present"`** (the custom default scope's mapper fired
on the unrestricted mint) and
**`sub: "ff43d141-cd9f-4dd5-a291-4d5b81d6345f"`** (SubMapper fired —
`basic` was in the allowed set). Also: `scope: "email adv10-scope
profile"` (built-ins `roles`/`web-origins`/`basic`/`acr` are
include-in-token-scope=false), `aud: "account"`, `realm_access` +
`resource_access.account` present, `jti` prefix `onrtro:`, `sid`
present.

### Leg 2 — the exchange (`request-2.json`, the token under test)

```
POST /realms/adv-10/protocol/openid-connect/token
grant_type=urn:ietf:params:oauth:grant-type:token-exchange
client_id=adv10-client
client_secret=adv10-secret-feedface
subject_token=<the literal leg-1 JWT>
subject_token_type=urn:ietf:params:oauth:token-type:access_token
scope=profile
```

**`scope=profile` is the whole seam** — it becomes `restrictedScopes`
on the exchange leg's DCSC. **No `audience`** (no aud-narrowing noise;
`REQUESTED_AUDIENCE_CLIENTS` never set) and **no
`requested_token_type`** (defaults to access_token).
`request-2.json` was frozen by hand immediately after leg 1, before
this file and prediction-target.md were written, and before any
exchange mint.

## Plausible outputs (the trap menu)

Same five entries as prediction-target.md; the builder's
expected-correct entry is marked here (never in the public file).

1. `adv10_marker = "present"`, `sub = PRESENT`,
   `scope_claim_multiset` ⊇ {adv10-scope} — reader who thinks the
   exchanged token inherits the subject token's mapper set / scopes
   ("exchange copies claims").
2. `adv10_marker = ABSENT`, `sub = PRESENT`,
   `scope_claim_multiset = {profile}` — reader who applies
   `restrictedScopes` to custom/optional scopes but assumes built-in
   default scopes (`basic`, and its SubMapper) are immune.
3. `adv10_marker = ABSENT`, `sub = ABSENT`,
   `scope_claim_multiset = {profile}` — reader who applies the filter
   uniformly to every candidate scope including `basic`, then
   invariant 1 + invariant 11. **← expected correct.**
4. HTTP 400 `invalid_scope` / no token — reader who thinks
   `scope=profile` is invalid on the exchange leg (subset-of-subject-
   scope misread; actually validated against the client's registered
   scopes).
5. `adv10_marker = "present"`, `sub = PRESENT`,
   `scope_claim_multiset = {profile}` — reader who thinks
   `restrictedScopes` only affects the `scope` claim string, not the
   mapper set.

## Minimum specificity to pass

All three commitments concrete (or `http_400_no_token` with all three
`null`). No either/or across trap rows; no unresolved "depends on what
restrictedScopes contains" — the request is public and its `scope`
param is literal. JSON serialization beyond presence/absence is not
scored.

## Determinism check plan

Mint leg 2 twice (`exchange a`, `exchange b`) **against the same
subject token** (`subject-token.jwt`, pinned input). Strip set:
`iat, exp, jti, auth_time, session_state, sid, nbf` via
`jq -S 'del(...)'` — **`sub` is NOT stripped**: it is a field under
test and must itself be identical across mints (it would be the user
UUID if present at all). The `jti` prefix (before the colon) must be
identical across both mints — expected `onrtte:`. Any a/b diff in
`adv10_marker`, `sub`, or `scope` is a fixture failure requiring
redesign. If the subject token expires (300 s) before both mints
complete, re-mint leg 1, re-freeze `request-2.json` /
`subject-token.json`, note it in surprises.md, and leave
prediction-target.md untouched (its targets reference no volatile
leg-1 values).

## Resolution after capture

**The builder's pre-mint expectation (#3) was FALSIFIED. The actual
outcome is trap-menu entry #1.** (A first draft of this section was
pre-written at the commitment point assuming #3; it was replaced
wholesale with the actuals below — see surprises.md §1 and §4.)

- **Both leg-2 mints returned HTTP 200** with
  `issued_token_type: urn:ietf:params:oauth:token-type:access_token`,
  no refresh token (`refresh_expires_in: 0`).
- **`adv10_marker = "present"`** in both exchanged payloads.
- **`sub` PRESENT** in both, value
  `ff43d141-cd9f-4dd5-a291-4d5b81d6345f` — identical to the subject
  token's `sub` and identical across mints.
- **`scope: "email adv10-scope profile"`** — multiset
  {email, adv10-scope, profile}, byte-identical to the subject token's
  scope claim and to the envelope `scope`. The `scope=profile` param
  down-scoped NOTHING.
- Trap-menu entry **#1** is the actual outcome ("exchange copies
  claims" — though the true mechanism is subtler, see below). The
  pre-mint expected entry #3 was wrong. No 6th trap was needed — the
  menu already contained the actual.
- **Why (source-verified post-capture, KC 26.5.5):**
  `StandardTokenExchangeProvider` L232-233 passes
  `context.getRestrictedScopes()` into
  `TokenManager.attachAuthenticationSession(...)` →
  `DefaultClientSessionContext.fromClientSessionAndClientScopes(...,
  restrictedScopes, ...)` → the DCSC.L253 filter. But
  `TokenExchangeContext.setRestrictedScopes` is invoked **only** by
  the client-policy executor
  `DownscopeAssertionGrantEnforcerExecutor` (TOKEN_EXCHANGE_REQUEST
  event; `services/.../clientpolicy/executor/DownscopeAssertionGrantEnforcerExecutor.java`
  L60-66). No client policy is configured on this stock realm, so
  `restrictedScopes == null` and the `isAllowed` restrictedScopes
  branch is inert. The exchange `scope` param only (a) passes
  pre-flight `isValidScope` and (b) lands in the auth-session
  SCOPE_PARAM note (ATEP L267) → `getRequestedClientScopes("profile")`
  → candidates = all default scopes ∪ {client} — the scope param can
  only ADD optional scopes to the candidate set, never subtract
  defaults. Full default mapper set → marker fires, SubMapper fires,
  email mappers fire, `getScopeString()` = "email adv10-scope
  profile".
- Collateral — all the "filtered" expectations failed the same way:
  `email`/`email_verified` PRESENT, `aud = "account"` PRESENT (roles
  scope alive → `AudienceResolveProtocolMapper` ran),
  `realm_access` + `resource_access.account` PRESENT (identical role
  sets to the subject token). The base-claim expectations held:
  `azp=adv10-client`, `typ=Bearer`, `acr="1"`, `sid` present and equal
  to the subject token's `sid` (`YVkqwmUYtcoIsnZUIn7BlDF1`) on both
  mints; `jti` prefix `onrtte:` on both (suffixes
  `36b730b6-…` / `1e8c081a-…` varied);
  `name`/`preferred_username`/`given_name`/`family_name` present.
- Determinism: `jq -S` payloads stripped of
  `iat,exp,jti,auth_time,session_state,sid,nbf` (with `sub` NOT
  stripped — it is a field under test) byte-identical between a and
  b; `actual-token-2-a.json` copied to `actual-token-2.json`.
- Subject token did NOT need re-minting; both mints completed ~144 s
  before the subject `exp`.
- Log evidence: `log-2-*.txt` carry the `type="TOKEN_EXCHANGE"` event
  with `scope="email adv10-scope profile"` (the *resolved* scope
  string, not the wire param — same post-default event semantics as
  adversarial-9's surprises.md §1) plus the pre-flight TRACE pair
  `Scopes to validate requested scopes against: web-origins acr roles
  profile basic adv10-scope email` / `scopes: profile`, which is the
  only log trace of the wire param. `log-1.txt` carries the leg-1
  `type="LOGIN"` event.
