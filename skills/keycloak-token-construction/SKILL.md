---
name: keycloak-token-construction
description: Reference for Keycloak 26.5.5 OIDC token construction — scope resolution, mapper-set assembly, base claims set by `initToken`, the per-surface mapper execution pipeline, and post-mapper transforms (audience restriction). Use whenever the task involves explaining or validating which claims appear in a Keycloak-issued access token, ID token, userinfo response, or introspection response; reasoning about which mapper produced which claim or why a claim is missing; auditing a client-scope or protocol-mapper configuration against an issued token; debugging differences between full-scope and restricted clients; or answering any "why is this claim in this token?" question. Engage proactively whenever Keycloak claim provenance, mapper toggles (`access.token.claim`, `id.token.claim`, `userinfo.token.claim`, `introspection.token.claim`, `lightweight.claim`), `clientSessionCtx`, `transformAccessToken` / `transformIDToken` / `transformUserInfoAccessToken` / `transformIntrospectionAccessToken`, or "this client scope is/isn't appearing in `scope`" come up, even if the user does not name the skill.
---

# Keycloak post-authentication token construction (26.5.5)

> **All source paths cited in this skill (here and in `references/`) are remote URLs at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak) tag `26.5.5` — they are NOT files in this working directory.** Do not attempt to read them from the local filesystem. Use `WebFetch` if you need to inspect them; otherwise rely on the line numbers cited inline. Shorthand forms like `TokenManager.L605`, `DCSC.L188-212`, or `OAuth2GrantTypeBase.java:128-135` all refer to the same upstream Java sources. Full path → URL mapping is in [references/source-pointers.md](references/source-pointers.md).

Pinned tag: **26.5.5**. Every line number cited here and in the references is at
that tag. Out-of-scope: authentication, grant-type validation, session
establishment, signing, hash claims (`at_hash`, `c_hash`, `s_hash`).
In-scope: from "the user is already authenticated and we have a
`ClientSessionContext`" through to "the claims map for the requested surface".

Treat token construction as a pure function:

```
construct(user, client, requestedScopeParam, surface, sessionCtxAttrs)
        → claimsMap
```

The five surfaces are **access token**, **ID token**, **userinfo**,
**introspection**, and **access-token response envelope**. They share scope
resolution and mapper-set assembly; they diverge at the per-mapper toggle check
(see [references/mapper-execution.md](references/mapper-execution.md)).

## Macro flow

```
1. Resolve scopes              → DefaultClientSessionContext.allowedClientScopes
   (TokenManager.getRequestedClientScopes  + DCSC.isAllowed)

2. Assemble mapper set         → clientSessionCtx.getProtocolMappersStream()
   (union over allowed scopes, filtered by client.protocol and isEnabled)

3. Build base claims (access)  → TokenManager.initToken
   (id, typ, sub-if-transient, iat, azp, iss, scope, acr-if-no-stepup,
    sid, exp — see references/base-claims.md)

4. Run mapper pipeline         → TokenManager.transform<Surface>
   sort by priority ASC, then for each mapper:
     surface_toggle_passes(model)  ?  mapper.setClaim(token, ...)  :  skip

5. Post-mapper transforms      → restrictRequestedAudience  (access-token only)

6. (ID token only) generateIDToken seeds an IDToken from the *transformed*
   access token, then runs OIDCIDTokenMapper-side mappers on it.
```

That is the entire post-auth construction loop. Everything else in this skill
is the detail behind one of these six steps.

## Per-surface entry points on `TokenManager`

| Surface | Entry method | Mapper interface | Toggle key |
| --- | --- | --- | --- |
| Access token | `transformAccessToken` (L793) | `OIDCAccessTokenMapper` | `access.token.claim` (or `lightweight.claim` if lightweight) |
| ID token | `transformIDToken` (L973), called from `generateIDToken` (L1262) | `OIDCIDTokenMapper` | `id.token.claim` |
| Userinfo | `transformUserInfoAccessToken` (L823) | `UserInfoTokenMapper` | `userinfo.token.claim` (falls back to `id.token.claim`) |
| Introspection | `transformIntrospectionAccessToken` (L834) | `TokenIntrospectionTokenMapper` | `introspection.token.claim` (falls back to `access.token.claim`, lightweight-unaware) |
| AT response envelope | `transformAccessTokenResponse` (L811) | `OIDCAccessTokenResponseMapper` | `access.tokenResponse.claim` |

Naming hazards worth pre-loading:

- `TokenManager.transformUserInfoAccessToken` is the dispatcher; the leaf
  interface method is `UserInfoTokenMapper.transformUserInfoToken`. Both names
  exist; they live at different layers. Don't grep for the wrong one.
- `AbstractOIDCProtocolMapper.java` lives at
  [`services/src/main/java/org/keycloak/protocol/oidc/mappers/`](https://github.com/keycloak/keycloak/tree/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers) at this tag, not
  at `server-spi-private/...`.

## Routing — go to the right reference

- **"What goes in / what comes out?"** → [references/inputs-and-outputs.md](references/inputs-and-outputs.md)
- **"Why is/isn't scope X in `clientSessionCtx`?"** → [references/scope-resolution.md](references/scope-resolution.md)
- **"Which mappers run, and in what order?"** → [references/mapper-set-assembly.md](references/mapper-set-assembly.md)
- **"Where did `iss` / `sub` / `acr` / `scope` come from?"** → [references/base-claims.md](references/base-claims.md)
- **"Did this mapper fire on this surface?"** → [references/mapper-execution.md](references/mapper-execution.md)
- **"Why was `aud` rewritten after the mappers ran?"** → [references/post-mapper.md](references/post-mapper.md)
- **"Why is/isn't the `organization` claim present, and in what shape?"** → [references/organizations.md](references/organizations.md)
- **"Where is this in the source?"** → [references/source-pointers.md](references/source-pointers.md)

## Critical invariants the verifier must enforce

These are the rules whose violation produces the most common false positives
when validating a token against a mapper set. State them up front; the
references back them up with line numbers.

1. **`sub` is not always set by `initToken`.** `initToken` sets `sub` only for
   *transient* user sessions (TokenManager.L992-994). For all other sessions,
   `sub` is set later by `SubMapper`. A model that assumes `sub` is base-claim
   territory will mispredict pairwise and transient cases.

2. **The `scope` claim is not the requested scope param.** It is
   `DefaultClientSessionContext.getScopeString()` — names of *allowed* client
   scopes whose `isIncludeInTokenScope()` is true, with `openid` re-attached if
   the original request was OIDC (DCSC.L188-212). The client itself is filtered
   out (DCSC.L200). A scope with no `include.in.token.scope` attribute defaults
   to **true**, not false (`ClientScopeModel.java:109-112`).

3. **Lightweight access tokens use a different toggle.** When
   `client.use.lightweight.access.token.enabled` is set or the session attribute
   `USE_LIGHTWEIGHT_ACCESS_TOKEN_ENABLED` is set, mappers gate on
   `lightweight.claim`, not `access.token.claim`. A mapper with
   `access.token.claim=true` and `lightweight.claim=false` is **silently
   skipped** on lightweight access tokens.

4. **Introspection's fallback ignores lightweight.** When
   `introspection.token.claim` is unset, the introspection toggle falls back to
   `access.token.claim` — but it bypasses the lightweight branch. So a mapper
   with `access.token.claim=true`, `lightweight.claim=false`,
   `introspection.token.claim` unset is on for introspection regardless of
   lightweight mode (`OIDCAttributeMapperHelper.L414-422`).

5. **Userinfo's fallback uses `id.token.claim`, not `access.token.claim`.**
   When `userinfo.token.claim` is unset, the userinfo toggle falls back to
   `id.token.claim` (`OIDCAttributeMapperHelper.L403-411`). This is opposite of
   what most engineers expect.

6. **`fullScopeAllowed` short-circuits role intersection, not mapper dispatch.**
   When `client.fullScopeAllowed=true`, `TokenManager.getAccess` (L605-609)
   returns the user's full role set without intersecting with client-scope role
   mappings. The *mapper set* is unaffected — it still comes from the allowed
   client scopes. The role-driven mappers
   (`UserRealmRoleMappingMapper`, `UserClientRoleMappingMapper`,
   `AudienceResolveProtocolMapper`) then have a larger or smaller input
   depending on this flag, which is what produces the empirical token-body
   diff between `test-client` and `test-client-restricted` in the fixtures.

7. **ID-token base claims are sourced from the *already-transformed* access
   token**, except for `sub`, `aud`, and `iat` which are reset
   (TokenManager.L1268-1276). Mapper mutations of the access token are
   inherited by the ID token unless an ID-token mapper rewrites them.

8. **`restrictRequestedAudience` runs after the access-token mappers.** If
   `Constants.REQUESTED_AUDIENCE_CLIENTS` is set on the session ctx (token
   exchange / requested-audience refresh), `aud` and `resource_access` are
   pruned post-mapper (TokenManager.L802-807, L1406). Verifying mapper output
   without applying this prune will over-report `aud` for those flows.

9. **`at_hash`, `c_hash`, `s_hash` are out of model.** They are computed over
   the encoded JWS, not over the claims map (TokenManager.L1338-1341, after
   `session.tokens().encode(...)` at L1329). A claims-only verifier cannot
   produce them; treat them as opaque.

10. **Mapper sort ties are not deterministic.** `ProtocolMapperUtils.compare`
    (L172-175) returns only priority. The upstream stream is a
    `Set<ProtocolMapperModel>` (DCSC.L68, L325), so equal-priority mappers run
    in `HashSet` iteration order. If two mappers write the same claim path,
    require distinct priorities or flag the case as unverifiable. The same
    HashSet contract governs intra-mapper iteration over user-state Sets — see
    [references/organizations.md](references/organizations.md) §5 for the
    `oidc-organization-membership-mapper` wildcard case, anchored by the
    cross-fixture order divergence between adversarial-5 and adversarial-6.

11. **Wire serialization drops null claims.** Token JSON is produced with
    `JsonInclude.NON_NULL` (`core/.../util/JsonSerialization.java:48`). Any
    claim left null in memory disappears from the wire. A mapper firing on a
    surface is **not** the same as a non-null claim appearing in the JSON:
    `UserPropertyMapper`, `UserAttributeMapper`, `UserSessionNoteMapper`, and
    the role/audience mappers all no-op when their source value is null/empty,
    producing absent claims even when the toggle gate passes. See
    [references/inputs-and-outputs.md](references/inputs-and-outputs.md#wire-serialization--jsoninclude-non_null)
    and [references/mapper-execution.md](references/mapper-execution.md#fires-is-not-writes-a-non-null-claim).

12. **`sid` may be nulled post-`transformAccessToken` on the transient branch.**
    `OAuth2GrantTypeBase.java:128-135` calls `accessToken.setSessionId(null)`
    when the grant's `useRefreshToken()` returns false **and** the encoded
    token id resolves to `AccessTokenContext.SessionType.TRANSIENT`. Both
    conditions hold by default for `client_credentials` (controlled by client
    attribute `client_credentials.use_refresh_token`,
    `OIDCConfigAttributes.java:77`); they don't fire for
    `authorization_code`, `password`, or `refresh_token`. The null then propagates to id_token
    `sid` via `idToken.setSessionId(accessToken.getSessionId())` at
    TokenManager.L1275/L1290. NON_NULL drops it from the wire. A `jti`
    prefix of `trrtcc:` indicates the transient branch; `onrtcc:` /
    `oftcc:` indicate persistent sessions where `sid` is retained. Sibling
    call sites: `StandardTokenExchangeProvider.L280`,
    `V1TokenExchangeProvider.L348`, `AuthorizationTokenService.L369`. See
    [references/post-mapper.md](references/post-mapper.md#access-token-transient-session-sid-nulling).

13. **The `organization` claim has three scope-param entry paths with
    materially different behaviour.** Default mapper config emits the claim as
    a flat JSON array of org alias strings (`["acme"]`), same shape on access
    and ID tokens (and on userinfo/introspection by mapper-toggle analogy).
    Three paths:
    (a) **Unqualified `scope=organization`** (static): emits the claim ONLY
    when the user is a member of exactly one organisation. Multi-membership
    and zero-membership both produce a null write → NON_NULL drops the claim.
    (b) **Wildcard `scope=organization:*`** (dynamic): emits all of the user's
    memberships. The dedup rule at [references/scope-resolution.md](references/scope-resolution.md)
    L22-28 drops the static-default `organization` from candidates. Array
    order is HashSet-iteration over org UUIDs (see invariant 10 extension).
    (c) **Specific `scope=organization:<alias>`** (dynamic): narrows to that
    alias if the user is a member; if the alias doesn't exist for the user,
    pre-flight `isValidScope` rejects with HTTP 400 `invalid_scope` (NOT
    silently skipped, NOT minted-with-absent-claim). See
    [references/organizations.md](references/organizations.md) for the full
    behavioural table and the `isValidScope` vs silent-skip clarification.

14. **Role-injection mappers bypass the toggle gate, write to a cache (not
    a claim), and surface only through consumer role mappers.** The
    `oidc-hardcoded-role-mapper` (`HardcodedRole`) and
    `oidc-role-name-mapper` (`RoleNameMapper`) **override**
    `transformAccessToken` / `transformUserInfoToken` /
    `transformIntrospectionToken` and call `setClaim` *unconditionally* —
    they never read `access.token.claim` / `id.token.claim` / etc. Their
    config carries no `*.token.claim` keys at all, so the
    `fires_on_surface` pseudocode (which is for gated
    `AbstractOIDCProtocolMapper` mappers) **mispredicts them as skipped**.
    The only per-surface gate for this class is the surface-*interface*
    filter: both implement `OIDCAccessTokenMapper`, `UserInfoTokenMapper`,
    and `TokenIntrospectionTokenMapper` but **not** `OIDCIDTokenMapper`, so
    neither ever runs on the ID-token surface. Crucially, `setClaim` does
    not write `realm_access` / `resource_access` directly — it appends the
    role to the `RoleResolveUtil` resolved-roles cache (a session attribute
    keyed `RESOLVED_ROLES:<userSessionId>:<clientId>`, built from
    `clientSessionCtx.getRolesStream()`). The role reaches a token only
    when a **consumer** mapper reads that cache:
    `UserRealmRoleMappingMapper` / `UserClientRoleMappingMapper`
    (`realm_access` / `resource_access`, priority 40) and
    `AudienceResolveProtocolMapper` (`aud`, priority 30). Therefore the
    surface on which a hardcoded role appears is governed by the
    **consumer's** toggles, not by the hardcoded mapper. The priority
    chain `PRIORITY_HARDCODED_ROLE_MAPPER`=20 < audience-resolve=30 <
    role-mapper=40 makes the routing deterministic (injection precedes
    every read), and the cache is session- not surface-scoped, so a role
    injected on the access-token pass is visible to an ID-token consumer
    that fires (`id.token.claim=true`) even though `HardcodedRole` itself
    never runs on the ID surface. Finally, because the injection is
    appended *after* `getRolesStream()` resolved the user's real roles, it
    **bypasses `fullScopeAllowed` and the role allowlist** (invariant 6):
    the user need not hold the role. See
    [references/mapper-execution.md](references/mapper-execution.md#mappers-that-override-the-gate-role-injection-class)
    and fixture `adversarial-7`.

15. **Mapper writes to a base-claim name fall into three categories, only
    one of which actually overrides the base value.**
    `OIDCAttributeMapperHelper.mapClaim` looks up the leading path segment
    in a static `tokenPropertySetters` map before falling through to
    `otherClaims`. Three outcomes are possible for a single-segment claim
    name `X`:
    (a) **Modifiable** — `X ∈ {sub, azp, acr, auth_time, aud}`. `mapClaim`
    invokes a dedicated `PropertySetter` against the token object
    (`token.setSubject`, `token.issuedFor`, `token.setAcr`,
    `token.setAuth_time`, `token.audience`). The base value set by
    `initToken` / `generateIDToken` is replaced. Exactly one JSON key is
    emitted, mapper's value wins, no log.
    (b) **Non-modifiable (server-owned)** — `X ∈ {jti, typ, iat, exp, iss,
    scope, nonce, session_state}`. `mapClaim` invokes a sentinel
    `notAllowedInToken` setter that logs `WARN Claim '<X>' is
    non-modifiable in IDToken. Ignoring the assignment for mapper
    '<mapperName>'.` and drops the write. The base value stands. The WARN
    fires once per surface where the mapper's toggle gate passed (e.g. a
    mapper with `access.token.claim=true` and `id.token.claim=true`
    writing `iss` emits two WARN lines per token mint).
    (c) **Collision (silent, hazardous)** — any other name that happens
    to be a dedicated `@JsonProperty` field on `JsonWebToken` / `IDToken`
    / `AccessToken` but is **not** in either map. `sid` is the canonical
    case: `mapClaim` writes `otherClaims["sid"]`, but the dedicated `sid`
    field still serializes via its `@JsonProperty("sid")` — so the JSON
    body contains **two `"sid":` keys**. No WARN. Parsers that take
    last-wins observe the mapper value; parsers that take first-wins
    observe the real session id. Treat any mapper writing to a base-claim
    name outside the modifiable/non-modifiable sets as producing an
    ill-formed token; do not predict either value as authoritative.
    The five `tokenPropertySetters` setters bypass `otherClaims` entirely,
    so the modifiable case never produces a duplicate key. Multi-segment
    claim paths (`foo.bar`) never hit this filter; they always route into
    `otherClaims` and never collide with base-claim names. Verified
    empirically against KC 26.5.5 for `azp` (modifiable, single key),
    `iss` (WARN-dropped twice on AT+ID surfaces), and `sid` (duplicate
    JSON key, no WARN). See
    [references/mapper-execution.md](references/mapper-execution.md#claim-name-routing-inside-setclaim-mapclaim-reserved-name-filter).

## When to consult fixtures

The `fixtures/` directory ships eight `(request, log, token)` triples — four on
`test-client` (`fullScopeAllowed=true`), three on `test-client-restricted`
(`fullScopeAllowed=false`), and one positive control captured with
`client_credentials.use_refresh_token=true` to exercise the persistent-session
branch (`with-refresh-openid`). Use them as ground truth when a behavioral
question has no clean source-only answer. The empirical token-body diff for
invariant 6 is in `token-default-scopes.json` vs
`token-restricted-default-scopes.json`. The empirical anchor for invariant 12
is `token-openid.json` (transient, `sid` absent, `jti` prefix `trrtcc:`) vs
`token-with-refresh-openid.json` (persistent, `sid` populated, prefix
`onrtcc:`). Mapper internals are not logged at any level — token bodies are
the authoritative output.
