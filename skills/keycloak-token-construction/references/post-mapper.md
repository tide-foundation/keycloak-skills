# Post-mapper transforms

> **All source paths in this document are remote URLs at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak) tag `26.5.5` — they are NOT files in this working directory.** Shorthand like `TokenManager.L802-807`, `OAuth2GrantTypeBase.java:128-135`, or `ClientCredentialsGrantType.java:111-115` refers to the same upstream sources. Use `WebFetch`; do not look for them on the local filesystem. Full path → URL mapping is in [source-pointers.md](source-pointers.md).

Defines what runs *after* the per-mapper loop on each surface. Only the
access-token surface has a true post-mapper transform that mutates the claims
map in-place; the ID-token path adds an indirect post-step via `at_hash`
which is out of model.

## Access-token: `restrictRequestedAudience`

Fires inside `transformAccessToken` after the mapper loop completes
(TokenManager.L802-807, implementation at L1406-1414).

```
transformAccessToken(session, token, userSession, ctx):                   # L793
    for mapper in getSortedProtocolMappers(ctx, isAccessTokenMapper):
        token ← mapper.transformAccessToken(token, model, ...)
    requested ← ctx.getAttribute(Constants.REQUESTED_AUDIENCE_CLIENTS)    # L802-803
    if requested != null:
        restrictRequestedAudience(token, requested)                       # L805
    return token

restrictRequestedAudience(token, requested : Set<String>):                # L1406-1414
    if token.audience == null:
        return token                                                      # no-op
    audienceToSet ← new HashSet<>(requested)
    audienceToSet.retainAll(Set.of(token.audience))                       # intersect
    token.audience ← audienceToSet.toArray(String[]::new)
        # Note: not nulled when empty — `aud` ends up as a zero-length array.
        # The wire serialization may still drop it, but the in-memory token
        # has a non-null empty audience after this call.
    token.resourceAccess.keySet().removeIf(clientId ->
        clientId ∉ audienceToSet)
        # Source has no null guard on getResourceAccess(); it relies on
        # AccessToken.getResourceAccess() returning a non-null map.
    return token
```

When fires:

- Token exchange (`urn:ietf:params:oauth:grant-type:token-exchange`) with a
  `requested_token_type` that triggers audience narrowing.
- Refresh-with-`requested_token_type` flows that pass an explicit audience
  list.
- Any internal caller that sets `Constants.REQUESTED_AUDIENCE_CLIENTS` on the
  client session ctx before invoking `createClientAccessToken`.

When does **not** fire:

- Plain `client_credentials`, `password`, `authorization_code`, or `refresh_token`
  grants that don't pass a requested-audience list. The fixtures in this
  skill exercise this branch: `requested == null` → no restriction.

The same attribute also affects the role allowlist filter inside
`isClientScopePermittedForUser` (DCSC.L290-295), but that runs at scope
resolution time, not post-mapper.

## Access-token: transient-session `sid` nulling

Fires inside the grant-type entry path *between* `transformAccessToken`
and `generateIDToken`, in `OAuth2GrantTypeBase.java:128-135`. Not part of
`TokenManager`; the dispatcher in the grant code performs it explicitly.

```
# OAuth2GrantTypeBase.processTokenResponse, paraphrased L120-135:
if grant.useRefreshToken():                                      # L120
    responseBuilder.generateRefreshToken(...)
    # ... offline-session cleanup ...
else:
    sessionType ← encoder.getTokenContextFromTokenId(             # L130-131
                      responseBuilder.getAccessToken().getId()
                  ).getSessionType()
    if sessionType == AccessTokenContext.SessionType.TRANSIENT:
        accessToken.setSessionId(null)                           # L132   ← the nulling
        event.session((String) null)                             # L133   ← clears event sessionId too
```

Trigger condition (precisely): **both** must hold —
(a) the grant's `useRefreshToken()` returns **false**, **and**
(b) the encoded token id resolves to `AccessTokenContext.SessionType.TRANSIENT`.
The two are coupled in practice because the grant code that decides
`useRefreshToken=false` also creates a TRANSIENT session
(`ClientCredentialsGrantType.java:111-115` — the only post-auth grant where
this happens by default), but the runtime check is on the encoded session
type, not on `useRefreshToken` directly. Defaults across grants:

| Grant | `useRefreshToken()` source | Default | Net effect |
| --- | --- | --- | --- |
| `client_credentials` | [`ClientCredentialsGrantType.java:154-156`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/ClientCredentialsGrantType.java#L154-L156) reads client attribute `client_credentials.use_refresh_token` (constant `OIDCConfigAttributes.USE_REFRESH_TOKEN_FOR_CLIENT_CREDENTIALS_GRANT`, [`server-spi-private/.../OIDCConfigAttributes.java:77`](https://github.com/keycloak/keycloak/blob/26.5.5/server-spi-private/src/main/java/org/keycloak/protocol/oidc/OIDCConfigAttributes.java#L77)) | `"false"` | TRANSIENT session created at [`ClientCredentialsGrantType.java:111-115`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/ClientCredentialsGrantType.java#L111-L115); both branches of the `OAuth2GrantTypeBase.L130` check fire → `sid` nulled |
| `authorization_code`, `password`, `refresh_token` | [`OAuth2GrantTypeBase.java:398`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java#L398) | `true` | takes the L120 if-branch entirely; the TRANSIENT check at L130 is never evaluated; `sid` retained |

Because `generateIDToken` reads `idToken.setSessionId(accessToken.getSessionId())`
at TokenManager.L1275 / L1290 *after* the access-token nulling has already
fired, the null propagates to the id_token's `sid` as well. With Keycloak's
`JsonInclude.NON_NULL` serializer ([`core/.../util/JsonSerialization.java:48`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/util/JsonSerialization.java#L48)),
null `sid` is dropped from the wire JSON entirely — verifiers comparing a
captured token to the in-memory model must treat absent-on-wire as equivalent
to null-in-memory.

### Diagnostic — read the `jti` prefix

`TokenContextEncoderProvider.encodeTokenId` (TokenManager.L987-989) prefixes
the token id with a tag derived from `AccessTokenContext.SessionType`:

| Prefix | Session type | `sid` likely present? |
| --- | --- | --- |
| `trrtcc:` | TRANSIENT (transient-refresh-token-context) | No — nulled by L132 |
| `onrtcc:` | ONLINE | Yes |
| `oftcc:` (and similar) | OFFLINE | Yes |

Verifiers can use the prefix as ground-truth for which branch a captured
token came from without re-running the issuance. The contrast is empirically
anchored by the fixture pair `token-openid.json` (transient, `sid` absent)
vs `token-with-refresh-openid.json` (online, `sid` present).

### Sibling `setSessionId(null)` call sites

Three other code paths null `sid` post-construction. None are exercised by
the fixtures in this skill, but a verifier handling those flows must model
the same propagation:

- [`StandardTokenExchangeProvider.java:280`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/tokenexchange/StandardTokenExchangeProvider.java#L280) — token-exchange flows.
- [`V1TokenExchangeProvider.java:348`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/tokenexchange/V1TokenExchangeProvider.java#L348) — legacy v1 token exchange.
- [`AuthorizationTokenService.java:369`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/authorization/authorization/AuthorizationTokenService.java#L369) — RPT (Authorization Service) flows.

The trigger logic differs per call site — a verifier must inspect each — but
the propagation to `id_token.sid` via `generateIDToken` is the same.

## How `aud` is built up before the restrict step

Mappers build `aud` cumulatively across the loop. Notable contributors:

| Mapper | Effect on `aud` |
| --- | --- |
| `AudienceResolveProtocolMapper` | Adds clientIds for any **client role** the user holds whose owning client isn't already in `aud`. Driven by the role allowlist that `fullScopeAllowed` and `REQUESTED_AUDIENCE_CLIENTS` shape upstream. |
| `AudienceProtocolMapper` | Adds an operator-configured `included.client.audience` (a clientId resolved at runtime) and/or `included.custom.audience` (a literal string) to `aud`. |
| `HardcodedClaim` (only if configured against the `aud` path) | Writes a constant value at any configurable claim path; if an operator points it at `aud`, it contributes there. |
| `restrictRequestedAudience` (post-loop) | Intersects with `requested`; rewrites `resource_access` to drop entries whose key is no longer in the intersection. |

Order matters because `restrictRequestedAudience` operates on the *final* `aud`
after all mappers have written. If two mappers race to write `aud` at equal
priority, the order is non-deterministic
(see [mapper-set-assembly.md](mapper-set-assembly.md#tie-breaking-is-non-deterministic))
but the post-loop intersect is stable: the same input set produces the same
output regardless of mapper order.

## ID-token: no post-mapper transform on the claims map

`transformIDToken` (L973-981) is followed only by:

- An `at_hash` flag set in `generateIDToken` at L1289-1292; the actual hash
  is computed in `AccessTokenResponseBuilder.build()` at L1338-1341 *after*
  `session.tokens().encode(accessToken)` runs at L1329. Out of model — the
  hash is over the JWS, not the claims map.
- `c_hash` and `s_hash` (set under similar conditions for code/state hash) —
  also computed after encoding.

A pure-function-over-claims model **cannot** produce `at_hash`, `c_hash`, or
`s_hash`. Treat them as opaque.

## Userinfo: no post-mapper transform

`transformUserInfoAccessToken` returns the decorated AccessToken directly. The
subsequent `generateUserInfoClaims` (L845-934) is a *projection*, not a
transform — it does not call any mapper. Notable projection rules:

- `sub` is always written from the AccessToken's `sub` field (whichever
  mapper wrote it on the access-token surface).
- `otherClaims` is bulk-copied at L914.
- A small set of standard userinfo wire fields is added outside this skill's
  scope.

## Introspection: no post-mapper transform on the claims map

`transformIntrospectionAccessToken` returns the decorated AccessToken
directly. Wire-level fields (`active: true`, etc.) are added by the
introspection endpoint, not by the construction pipeline.

## AT response envelope: no post-mapper transform

`transformAccessTokenResponse` (L811-821) is itself the post-encode step —
runs in `build()` at L1372 after the access/id/refresh tokens are already
encoded onto the response. Mappers on this surface write to the envelope,
not to any token claims map.

## Collision handling

There is no explicit collision arbiter. The mapper loop is a fold:

```
seed   = base claims
fold   = (token, mapper) -> { mapper.transformX(token, ...); return token; }
result = mappers.reduce(seed, fold)
```

The token object is mutated in place. Last writer wins per claim path. The
priority sort is the only ordering primitive. Common collision sites:

- `realm_access.roles` — role mappers append to a list/map; if the list is
  pre-populated by a `HardcodedClaim`, both contributions can survive
  depending on the mapper's merge logic.
- `aud` — multiple audience mappers all `addAudience` rather than overwrite,
  so they generally accumulate (then `restrictRequestedAudience` may prune).
- `sub` — `SubMapper` and `SHA256PairwiseSubMapper` both write `sub`.
  Configure exactly one per client.
- Custom claims at the same path with `HardcodedClaim` and a user-attribute
  mapper — last writer at the priority sort wins; flag if priorities tie.

## Pseudocode summary

```
postProcess(token, surface, ctx, grant):
    if surface == access_token:
        requested ← ctx.attr(REQUESTED_AUDIENCE_CLIENTS)
        if requested != null and token.aud != null:
            kept ← (Set<String>) requested ∩ Set.of(token.aud)
            token.aud ← kept as String[]              # NOT nulled when empty
            token.resource_access.dropKeysNotIn(kept)
        # Performed in the grant dispatcher, not TokenManager:
        if grant != null and not grant.useRefreshToken() \
                          and encodedSessionType(token.id) == TRANSIENT:   # OAuth2GrantTypeBase.L128-135
            token.sid ← null
            # propagates to id_token.sid via generateIDToken at L1275/L1290
    return token
    # ID token, userinfo, introspection, response envelope: no claims-map
    # post-mapper transform of their own.
```

## See also

- [`TokenManager.java:793-810`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L793-L810) — `transformAccessToken` and the `restrictRequestedAudience` call site.
- [`TokenManager.java:1406-1414`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1406-L1414) — `restrictRequestedAudience` body.
- [`TokenManager.java:1289-1341`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1289-L1341) — `at_hash`/`c_hash`/`s_hash` are JWS-level, not claim-level.
- [`DefaultClientSessionContext.java:290-295`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L290-L295) — the audience attribute also gates the role allowlist (upstream of the post-mapper transform).
- [`AudienceResolveProtocolMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AudienceResolveProtocolMapper.java) — pre-restrict `aud` builder.
- [`OAuth2GrantTypeBase.java:128-135`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java#L128-L135) — transient `setSessionId(null)` site.
- [`OAuth2GrantTypeBase.java:398`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java#L398) — `useRefreshToken()` default.
- [`ClientCredentialsGrantType.java:111-115`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/ClientCredentialsGrantType.java#L111-L115), [`154-156`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/ClientCredentialsGrantType.java#L154-L156) — TRANSIENT session decision and `client_credentials.use_refresh_token` read.
- [`OIDCConfigAttributes.java:77`](https://github.com/keycloak/keycloak/blob/26.5.5/server-spi-private/src/main/java/org/keycloak/protocol/oidc/OIDCConfigAttributes.java#L77) — `USE_REFRESH_TOKEN_FOR_CLIENT_CREDENTIALS_GRANT` constant (the attribute key).
- [`JsonSerialization.java:48`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/util/JsonSerialization.java#L48) — `JsonInclude.NON_NULL` (why null `sid` is absent on the wire).
