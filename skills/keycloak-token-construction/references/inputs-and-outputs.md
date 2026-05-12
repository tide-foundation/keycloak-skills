# Inputs and outputs

> **All source paths in this document are remote URLs at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak) tag `26.5.5` — they are NOT files in this working directory.** Shorthand like `TokenManager.L992-994` or `OAuth2GrantTypeBase.java:132` refers to the same upstream sources. Use `WebFetch`; do not look for them on the local filesystem. Full path → URL mapping is in [source-pointers.md](source-pointers.md).

Defines the contract of the pure function this skill models: what state must be
known to predict a token's claims, and what shape the output takes per surface.

## Inputs

The token-construction function takes five inputs. Anything not listed here is
either out of scope (auth, signing) or derivable from these.

### 1. `user` — the authenticated user

A `UserModel`. Must expose:

- `getId()` — used by `SubMapper` (and by `initToken` for transient sessions).
- `getRoleMappingsStream()` and full deep-role expansion via
  `RoleUtils.expandCompositeRoles` — input to scope-allowedness
  (DCSC.L298-299) and role-mapper output.
- Standard property accessors used by `UserPropertyMapper` (`getEmail`,
  `getUsername`, `getFirstName`, …) and attribute accessors used by
  `UserAttributeMapper`.

Service accounts are users — for the `client_credentials` grant, the user is
the client's service-account user (`service-account-<clientId>`). Treat them
identically.

### 2. `client` — the requesting `ClientModel`

Must expose:

- `getClientId()` — becomes `azp`.
- `getProtocol()` — must equal `"openid-connect"` for any of this to apply.
- `isFullScopeAllowed()` — gates the role-intersection short-circuit
  (TokenManager.L605-609); does **not** gate mapper dispatch.
- `getClientScopes(true)` and `getClientScopes(false)` — default vs optional
  client scopes. Inputs to scope resolution.
- `getScopeMappingsStream()` (via `ClientModel extends ClientScopeModel`) —
  the client's own role allowlist when `fullScopeAllowed=false`.
- `isConsentRequired()` — gates `verifyConsentStillAvailable`
  (TokenManager.L781-790); orthogonal to claim shape but can fail the request.
- Client attributes:
  - `client.use.lightweight.access.token.enabled` — switches the access-token
    mapper toggle from `access.token.claim` to `lightweight.claim`.
  - `access.token.lifespan`, etc. — feed `getTokenExpiration`. Out of model
    for claim shape; relevant only for `exp`.

### 3. `scopeParam : String?` — the OAuth `scope` form parameter

Whitespace-separated, may be null, may contain `openid`, may contain dynamic
scope prefixes like `org:acme`. Algorithmically distinct from the `scope`
*claim* — see [scope-resolution.md](scope-resolution.md).

### 4. `surface` — which token / response is being constructed

One of: `access_token`, `id_token`, `userinfo`, `introspection`,
`access_token_response`. Selects the entry method on `TokenManager` and the
mapper interface used as the surface filter.

### 5. `sessionCtxAttrs` — `ClientSessionContext` attributes

A bag of side-channel inputs set by upstream code on the auth session or
client session. The ones that affect claim construction:

| Attribute / note key | Source class | Effect |
| --- | --- | --- |
| `OIDCLoginProtocol.NONCE_PARAM` | auth-session | Becomes `nonce` on ID token (TokenManager.L1274) |
| `OIDCLoginProtocol.ISSUER` (note) | auth-session | Becomes `iss` (L999); set during auth-session attach, **not** by post-auth code |
| `OAuth2Constants.SCOPE_PARAM` (note) | auth-session | Read by `TokenUtil.isOIDCRequest` to decide whether `getScopeString` re-attaches `openid` (DCSC.L207-209) |
| `Constants.REQUESTED_AUDIENCE_CLIENTS` | request | Triggers `restrictRequestedAudience` post-mapper (TokenManager.L802-807); also prunes client-role allowlist (DCSC.L290-295) |
| `restrictedScopes` (DCSC ctor arg) | token exchange | Filters allowed scopes pre-`isClientScopePermittedForUser` (DCSC.L253-256) |
| `USE_LIGHTWEIGHT_ACCESS_TOKEN_ENABLED` (session attribute) | various | Forces lightweight branch even when client attribute isn't set (`AbstractOIDCProtocolMapper.L84-87`) |

## Output shape

### Access token — `AccessToken extends IDToken`

A claims map. Base claims set by `initToken`; mapper claims merged on top via
`mapper.setClaim`. The exact key set is the union of (a) base claims that
`initToken` always writes (`jti`, `typ`, `iat`, `azp`, `iss`, `scope`, `sid`,
`exp` — plus `acr` when step-up is off and `sub` when the session is
TRANSIENT) and (b) one entry per claim path written by a mapper that fires on
this surface for this client+user. There is no closed list across all
configurations; the verifier must enumerate firing mappers per request. As an
empirical anchor, the keys present in `fixtures/token-default-scopes.json`
(client-credentials grant on `test-client`, full scope, no `scope` param) are:
`exp, iat, jti, iss, aud, sub, typ, azp, sid, acr, allowed-origins,
realm_access, resource_access, scope, clientHost, clientId, clientAddress,
client_id, email_verified, preferred_username`.

### ID token — `IDToken`

Same Java type as the access token's superclass. Constructed fresh in
`generateIDToken` (TokenManager.L1262), then run through ID-token mappers.
Cannot be requested without `openid` in the scope param.

### Userinfo — `Map<String, Object>` projected from an `AccessToken`

`generateUserInfoClaims` (TokenManager.L845-934) projects the mapper-decorated
`AccessToken` into a flat map. The projection is shape-only — no further
mappers run. Any claim placed via `otherClaims` on the AccessToken is
bulk-copied at L914.

### Introspection — `AccessToken` decorated for the introspection surface

Same Java type as the access token, populated by mappers gated on
`introspection.token.claim`. Wire format adds `active: true` and a few
introspection-specific fields handled outside this skill.

### Access-token response envelope — `AccessTokenResponse`

The JSON returned by the token endpoint. Mappers gated on
`access.tokenResponse.claim` write top-level fields on this envelope (e.g.,
custom claims at the response level rather than inside `access_token`). Runs
in `build()` at L1372 — *after* the access/id/refresh tokens are encoded.

## Wire serialization — `JsonInclude.NON_NULL`

The output of token construction is an **in-memory** claims map. The wire JSON
is produced by [`core/src/main/java/org/keycloak/util/JsonSerialization.java:48`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/util/JsonSerialization.java#L48),
which configures the Jackson `ObjectMapper` with
`@JsonInclude(JsonInclude.Include.NON_NULL)`. **Any claim with a `null` value
is dropped from the wire JSON.** This rule applies to every surface (access
token, id token, userinfo, introspection, response envelope).

Concrete consequences a verifier will hit:

- `nonce` is absent on the wire when the request didn't carry one
  (`clientSessionCtx.getAttribute(NONCE_PARAM)` returns null) — not because
  the mapper didn't fire, but because the value was null.
- `email` (and other user-property claims) is absent when the user has no
  source attribute — `UserPropertyMapper` short-circuits, the field is never
  set, NON_NULL drops it. Same for `given_name`, `family_name`, etc.
- `auth_time` is absent on `client_credentials` flows — the AUTH_TIME session
  note is never set, the mapper writes nothing, NON_NULL drops it.
- `sid` is absent on the transient branch — `OAuth2GrantTypeBase.java:132`
  nulls it post-transform, NON_NULL drops it. See
  [post-mapper.md](post-mapper.md#access-token-transient-session-sid-nulling).

**Implication for verifiers:** when comparing a captured token to a predicted
claims map, treat absence-on-the-wire as equivalent to null-in-memory, not as
evidence that the mapper didn't fire or wasn't in the set. The toggle gates
(see [mapper-execution.md](mapper-execution.md)) decide whether the mapper
*runs*; what value it writes is a separate question, and a null write
disappears from the wire entirely.

The serialization rule is not surface-specific and not configurable per
mapper. There is no "include null" override on the OIDC path.

## What is *not* an input

- The realm's signing key — out of scope.
- The realm's name — appears in `iss` only via the auth-session note; this
  function treats `iss` as derived from the session ctx, not the realm.
- The HTTP request beyond the `scope` param and the session ctx attributes
  listed above.
- Time, except for `iat`/`exp`. Two consecutive issuances of the same
  `(user, client, scopeParam, surface)` produce identical claims modulo `iat`,
  `exp`, `jti`, and (for ID tokens) `id`.

## See also

- [`TokenManager.java:525-535`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L525-L535) — `createClientAccessToken` entry point.
- [`DefaultClientSessionContext.java:60-145`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L60-L145) — fields and constructor.
- [`AccessToken.java`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/representations/AccessToken.java) — claim field declarations.
- [`IDToken.java`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/representations/IDToken.java) — claim field declarations (superclass).
- [`JsonSerialization.java:48`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/util/JsonSerialization.java#L48) — `JsonInclude.NON_NULL` (wire serialization rule).
