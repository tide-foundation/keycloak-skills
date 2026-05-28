# Mapper execution pipeline

> **All source paths in this document are remote URLs at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak) tag `26.5.5` — they are NOT files in this working directory.** Shorthand like `AbstractOIDCProtocolMapper.L89-99` or `OIDCAttributeMapperHelper.L414-422` refers to the same upstream sources. Use `WebFetch`; do not look for them on the local filesystem. Full path → URL mapping is in [source-pointers.md](source-pointers.md).

Defines the per-mapper, per-surface execution loop: the toggle check that
decides whether a mapper fires on a given surface, and the dispatch into the
mapper's `setClaim` override.

## The five `transform<Surface>` methods on `TokenManager`

Same shape, same accumulator. They differ only in (a) which mapper interface
gates the surface filter and (b) which `transform<Surface>` method is invoked
on the leaf:

| Method | Line | Mapper interface filter | Leaf call |
| --- | --- | --- | --- |
| `transformAccessToken` | L793 | `OIDCAccessTokenMapper` | `mapper.transformAccessToken(token, model, …)` |
| `transformAccessTokenResponse` | L811 | `OIDCAccessTokenResponseMapper` | `mapper.transformAccessTokenResponse(response, model, …)` |
| `transformUserInfoAccessToken` | L823 | `UserInfoTokenMapper` | `mapper.transformUserInfoToken(token, model, …)` |
| `transformIntrospectionAccessToken` | L834 | `TokenIntrospectionTokenMapper` | `mapper.transformIntrospectionToken(token, model, …)` |
| `transformIDToken` | L973 | `OIDCIDTokenMapper` | `mapper.transformIDToken(token, model, …)` |

All five run the mapper list returned by `ProtocolMapperUtils.getSortedProtocolMappers`
through the `TokenCollector<T>` accumulator at L936-971: seed = input token,
accumulator = `applyMapper`, combiner = throws. The combiner-throws contract
means the stream is required to be sequential, so mapper order is
deterministic with respect to the priority sort (within the constraints
described in [mapper-set-assembly.md](mapper-set-assembly.md#tie-breaking-is-non-deterministic)).

## Per-mapper toggle check

Implemented once on `AbstractOIDCProtocolMapper`. Every concrete OIDC mapper
that doesn't override these methods inherits the gate. Predicates live on
`OIDCAttributeMapperHelper`.

```
# Each transform<Surface> method on AbstractOIDCProtocolMapper:
transform<Surface>(token, mappingModel, session, userSession, ctx):
    if NOT include_in_<surface>(mappingModel):
        return token                                    # SKIP
    setClaim(token, mappingModel, userSession, session, ctx)
    return token
```

The five gates:

```
# transformAccessToken — AbstractOIDCProtocolMapper.L89-99
include_in_access_token(model):
    lightweight ← getShouldUseLightweightToken(session)         # L84-87
                  # = client attribute  client.use.lightweight.access.token.enabled
                  #   OR session attribute USE_LIGHTWEIGHT_ACCESS_TOKEN_ENABLED
    if lightweight:
        return model.config["lightweight.claim"] == "true"      # OIDCAttributeMapperHelper.L425-427
    else:
        return model.config["access.token.claim"] == "true"     # L391-393

# transformIDToken — L101-110
include_in_id_token(model):
    return model.config["id.token.claim"] == "true"             # L387-389

# transformUserInfoToken — L73-82
include_in_userinfo(model):
    raw ← model.config["userinfo.token.claim"]                  # L403-411
    if raw == null:
        return include_in_id_token(model)                       # backwards-compat
    return raw == "true"

# transformIntrospectionToken — L124-133
include_in_introspection(model):
    raw ← model.config["introspection.token.claim"]             # L414-422
    if raw == null:
        return includeInAccessToken(model)                      # NOTE: not lightweight-aware
                                                                # i.e. checks access.token.claim==true
                                                                # regardless of lightweight mode
    return raw == "true"

# transformAccessTokenResponse — L112-122
include_in_access_token_response(model):
    return model.config["access.tokenResponse.claim"] == "true" # L395-397
```

### Toggle-key reference

| Java constant | Config key in `protocolMapper.config` | Default if missing |
| --- | --- | --- |
| `INCLUDE_IN_ACCESS_TOKEN` | `access.token.claim` | false |
| `INCLUDE_IN_ID_TOKEN` | `id.token.claim` | false |
| `INCLUDE_IN_USERINFO` | `userinfo.token.claim` | falls back to `id.token.claim` |
| `INCLUDE_IN_INTROSPECTION` | `introspection.token.claim` | falls back to `access.token.claim` (lightweight-unaware) |
| `INCLUDE_IN_ACCESS_TOKEN_RESPONSE` | `access.tokenResponse.claim` | false |
| `INCLUDE_IN_LIGHTWEIGHT_ACCESS_TOKEN` | `lightweight.claim` | false |

## Mappers that override the gate (role-injection class)

The toggle gate above is inherited **only** by mappers that leave
`AbstractOIDCProtocolMapper`'s `transform<Surface>` methods alone and just
override `setClaim`. A handful of built-in mappers instead **override
`transformAccessToken` / `transformUserInfoToken` /
`transformIntrospectionToken` directly and call `setClaim`
unconditionally** — they never consult `OIDCAttributeMapperHelper`, so
their `access.token.claim` / `id.token.claim` / `userinfo.token.claim` /
`introspection.token.claim` config keys are **absent and irrelevant**.
Applying the `fires_on_surface` pseudocode (below) to these mappers
mispredicts them as skipped (their config has no `access.token.claim`
key, so `== "true"` is false). Treat this class separately:

| Mapper | Provider id | Surface interfaces it implements | Fires on |
| --- | --- | --- | --- |
| `HardcodedRole` | `oidc-hardcoded-role-mapper` | `OIDCAccessTokenMapper`, `UserInfoTokenMapper`, `TokenIntrospectionTokenMapper` (**not** `OIDCIDTokenMapper`) | access, userinfo, introspection — unconditionally; **never** the ID token |
| `RoleNameMapper` | `oidc-role-name-mapper` | same three interfaces (not `OIDCIDTokenMapper`) | same — unconditionally; renames a resolved role in place |

For this class the only gate is the **surface-interface filter** (the
left column of the [five `transform<Surface>` table](#the-five-transformsurface-methods-on-tokenmanager)),
not any `*.token.claim` value. `HardcodedRole` not implementing
`OIDCIDTokenMapper` is the entire reason it has no direct effect on the ID
token.

**These mappers do not write a claim path.** `HardcodedRole.setClaim`
calls `RoleResolveUtil.getResolvedRealmRoles(...,true).addRole(role)` (or
`getResolvedClientRoles(...,client,true).addRole(role)`) — it appends the
role to the **resolved-roles cache**, a side `AccessToken` stored as a
session attribute keyed `RESOLVED_ROLES:<userSessionId>:<clientId>`,
built from `clientSessionCtx.getRolesStream()`. The role reaches a real
token only when a **consumer** mapper reads that cache:

- `UserRealmRoleMappingMapper` (priority 40) → `realm_access.roles`
- `UserClientRoleMappingMapper` (priority 40) → `resource_access.<client>.roles`
- `AudienceResolveProtocolMapper` (priority 30) → adds the owning client to `aud`

Each consumer is a normal gated mapper, so **the surface on which a
hardcoded role appears is governed by the consumer's toggles, not by
`HardcodedRole`**. A hardcoded realm role with `UserRealmRoleMappingMapper`
at `id.token.claim=true` appears in the ID token; a hardcoded client role
whose `UserClientRoleMappingMapper` has `id.token.claim` unset does not.
The priority chain
(`PRIORITY_HARDCODED_ROLE_MAPPER`=20 < `PRIORITY_AUDIENCE_RESOLVE_MAPPER`=30
< `PRIORITY_ROLE_MAPPER`=40) guarantees the injection lands in the cache
before every consumer reads it, so the routing is deterministic. The
cache is keyed by session, not by surface, so a role injected during the
access-token pass is still in the cache when the ID-token consumer runs —
even though `HardcodedRole` itself never runs on the ID surface. And
because the injection is appended *after* `getRolesStream()` resolved the
user's real roles, it **bypasses `fullScopeAllowed` and the role
allowlist**: the user need not hold the role. See SKILL.md invariant 14
and fixture `adversarial-7`.

## Claim-name routing inside `setClaim` (`mapClaim` reserved-name filter)

Once a gated mapper has cleared the toggle gate and `setClaim` is invoked,
most mappers ultimately call `OIDCAttributeMapperHelper.mapClaim(token,
mappingModel, value)` to write their value into the token. That helper does
**not** unconditionally place the value into `token.otherClaims`. It first
splits the configured claim path on `.` and looks up the leading segment in
a static `Map<String, PropertySetter<IDToken>> tokenPropertySetters`
(`OIDCAttributeMapperHelper.java`, declared near L300, populated in the
static initializer immediately below the declaration). The lookup has three
possible outcomes for a single-segment claim name `X`.

### (a) Modifiable — dedicated property setter, single JSON key

| `X` | Dispatched setter |
| --- | --- |
| `sub` | `token.setSubject(value.toString())` |
| `azp` | `token.issuedFor(value.toString())` |
| `acr` | `token.setAcr(value.toString())` |
| `auth_time` (`IDToken.AUTH_TIME`) | `token.setAuth_time(Long.parseLong(value.toString()))` — silently ignores `NumberFormatException` |
| `aud` | `token.audience(...)` — `Collection<?> → String[]` if value is a collection, else single string |

`mapClaim` returns after dispatching the setter; the value is **not** also
written to `otherClaims`. The dedicated `@JsonProperty`-annotated field is
the sole carrier on the wire, so exactly one JSON key is emitted and the
mapper's value replaces whatever `initToken` / `generateIDToken` wrote.
Behaviour confirmed empirically against KC 26.5.5: an
`oidc-hardcoded-claim-mapper` with `claim.name=azp`, `claim.value=X` on a
mapper with `access.token.claim=true` and `id.token.claim=true` produces
`"azp":"X"` exactly once on both the access token and the ID token, with
no log lines.

### (b) Non-modifiable — sentinel setter, WARN log, write dropped

| `X` | Reason claim is server-owned |
| --- | --- |
| `jti` | Token id; generated by server (access token: `TokenContextEncoderProvider.encodeTokenId`; ID token: `SecretGenerator.generateSecureID`). |
| `typ` | Token type (`"Bearer"` / `"ID"`); shape contract with the resource server. |
| `iat` | Issued-at timestamp; reset to `now()` on both surfaces. |
| `exp` | Expiry; governed by realm/client lifespan policy. |
| `iss` | Issuer; bound to the auth session note. |
| `scope` | Computed from `clientSessionCtx.getScopeString()`; see scope-resolution.md. |
| `nonce` (`IDToken.NONCE`) | Carried from the auth request via `clientSessionCtx`. |
| `session_state` (`IDToken.SESSION_STATE`) | OIDC session-state hash. |

`tokenPropertySetters` registers a shared sentinel `notAllowedInToken` for
each of these names. The sentinel logs

```
WARN  [org.keycloak.protocol.oidc.mappers.OIDCAttributeMapperHelper]
      Claim 'X' is non-modifiable in IDToken. Ignoring the assignment for mapper 'M'.
```

and returns without writing. The base value set by `initToken` /
`generateIDToken` therefore stands. **The WARN fires once per
`transform<Surface>` pass in which the mapper's toggle gate passed**, so a
mapper with `access.token.claim=true` and `id.token.claim=true` writing
`iss` produces *two* identical WARN lines per token mint (one for the
access-token pass, one for the ID-token pass). Despite the log message
saying "in IDToken", the protection applies to every surface that goes
through `mapClaim` — the message refers to the `IDToken` Java type
(superclass of `AccessToken`), not to the ID-token surface.

The `notAllowedInToken` logger is the OIDC-mappers helper logger, so it
appears at WARN regardless of the `org.keycloak.protocol.oidc.mappers` log
level (a category-level `INFO` is sufficient).

### (c) Collision — `otherClaims` write that shadows a dedicated `@JsonProperty`

If `X` is **not** in `tokenPropertySetters` but **is** a declared
`@JsonProperty` field on `JsonWebToken` / `IDToken` / `AccessToken`,
`mapClaim` falls through to writing `token.otherClaims[X] = value`. At
serialization Jackson emits **both**: the dedicated field via its
`@JsonProperty(X)` getter, then `otherClaims` via `@JsonAnyGetter`. The
JSON body contains two keys named `X`. No WARN.

Canonical case: `sid`. `JsonWebToken` has a `sid` field with
`@JsonProperty("sid")`, but `sid` is not registered in
`tokenPropertySetters` (and `IDToken.SESSION_STATE` is `"session_state"`,
not `"sid"`). Empirically against KC 26.5.5, a mapper writing
`claim.name=sid`, `claim.value=OVERRIDDEN-SID` produces a token body of
the shape:

```
{"...","sid":"<real-session-id>",...,"sid":"OVERRIDDEN-SID"}
```

— two `"sid":` keys, no log lines. Last-wins parsers (`json.loads`)
observe the mapper value; first-wins parsers observe the real session
id. RFC 8259 leaves the behaviour implementation-defined, so downstream
behaviour is environment-dependent. **Predict neither value as
authoritative; flag any mapper config that writes a base-claim name
outside the modifiable set as producing an ill-formed token.**

Other base-claim names that fall into this collision category by the same
analysis (declared on `JsonWebToken`/`IDToken`/`AccessToken`, absent from
both `tokenPropertySetters` branches): `nbf`, `sub_legacy`-style internal
fields, and a handful of OIDC standard claims that Keycloak surfaces as
dedicated getters (e.g. `name`, `given_name`, `family_name`,
`preferred_username`, `email`, `email_verified` — all live on `IDToken`).
The standard userinfo claims are normally only written by
`UserPropertyMapper` against the dedicated setters, so a hardcoded-claim
mapper writing the same names competes with `UserPropertyMapper` and
will produce duplicate keys for any user that has the property set.

### Custom (non-base) claim paths

Any other name routes cleanly into `otherClaims` as a single key — the
intended path for custom mappers. Multi-segment paths (`foo.bar.baz`)
also bypass `tokenPropertySetters` entirely; the helper recurses into
nested `HashMap` instances under `otherClaims` (L373-398). Therefore the
modifiable/non-modifiable/collision filter applies **only** to
single-segment top-level claim names.

### Predictor checklist

When validating a token against a mapper config that writes a
base-claim-shaped name:

1. Is the path a single segment? If no, behaviour is plain `otherClaims`
   nesting — no filter applies.
2. Is the leading segment in the modifiable set
   (`sub` / `azp` / `acr` / `auth_time` / `aud`)? If yes, predict the
   mapper's value at that key, exactly once, no log.
3. Is it in the non-modifiable set
   (`jti` / `typ` / `iat` / `exp` / `iss` / `scope` / `nonce` /
   `session_state`)? If yes, predict the base value at that key (mapper
   write dropped) and one WARN log line per surface the mapper's toggle
   gate passed.
4. Is the name a dedicated `@JsonProperty` field on
   `JsonWebToken`/`IDToken`/`AccessToken` outside either map (`sid`,
   userinfo standard claims, etc.)? Predict a duplicate JSON key. Flag
   as ill-formed; do not commit to either parser-wins ordering.
5. Otherwise: predict the mapper's value as a single key under that
   name, no log.

## Decision matrix per surface

Given a mapper config `{a, l, i, u, idt, atr}` standing for the six toggle
keys (each `true | false | unset`):

| Surface | Fires iff |
| --- | --- |
| Access token (standard) | `a == "true"` |
| Access token (lightweight) | `l == "true"` |
| ID token | `idt == "true"` |
| Userinfo | `u == "true"`, OR (`u` unset AND `idt == "true"`) |
| Introspection | `i == "true"`, OR (`i` unset AND `a == "true"`) — **regardless of lightweight** |
| AT response envelope | `atr == "true"` |

Common pitfalls:

- **Userinfo defaults to ID-token toggle**, not access-token toggle. A mapper
  that should be access-token-only must set `userinfo.token.claim=false`
  explicitly if `id.token.claim=true`.
- **Introspection's fallback ignores lightweight.** A mapper with
  `access.token.claim=true`, `lightweight.claim=false`,
  `introspection.token.claim` unset is **on for introspection** even when the
  client uses lightweight access tokens. To exclude it from introspection in
  that case, set `introspection.token.claim=false` explicitly.
- **Lightweight silently disables mappers.** A mapper with
  `access.token.claim=true` and `lightweight.claim=false` is on for normal
  access tokens but off for lightweight ones. The only signal is the client
  attribute `client.use.lightweight.access.token.enabled` or the session
  attribute `USE_LIGHTWEIGHT_ACCESS_TOKEN_ENABLED`.

## "Fires" is not "writes a non-null claim"

The toggle gates above decide whether `setClaim` is *invoked*. What `setClaim`
*writes* is a per-mapper decision, and several common mappers no-op (or write
nothing) when their source value is null. After the construction loop, the
`JsonInclude.NON_NULL` serializer drops any claim whose in-memory value is
null (see [inputs-and-outputs.md](inputs-and-outputs.md#wire-serialization--jsoninclude-non_null)).
Net effect: a mapper can fire on a surface and still produce **no claim on
the wire**.

Mappers known to no-op on null source values, exercised by the fixtures in
this skill:

| Mapper | No-op trigger |
| --- | --- |
| `UserPropertyMapper` | The named property accessor (`getEmail`, `getFirstName`, …) returns null. Drops `email`, `given_name`, `family_name`, etc. when the user has no value for the property. |
| `UserAttributeMapper` | The named user attribute is unset (or the multi-valued attribute is empty). Drops the configured claim path. |
| `UserSessionNoteMapper` | The named session note is unset. `auth_time` is the canonical case — the AUTH_TIME note isn't set on `client_credentials`, so the mapper fires but writes nothing. |
| `UserRealmRoleMappingMapper` / `UserClientRoleMappingMapper` | The role-allowlist intersection with the user's roles is empty. Drops `realm_access` / `resource_access.<client>` instead of writing an empty array. |
| `AudienceResolveProtocolMapper` | The user holds no client roles whose owning client should be added. Writes nothing rather than an empty `aud`. |

**Implication for verifiers.** When predicting a claim is absent from a
captured token, three explanations are possible: (a) the mapper isn't in the
set, (b) the toggle gate failed for this surface, or (c) the mapper fired
but wrote null. A claim-by-claim verifier must distinguish (b) from (c) —
they differ in whether the mapper appears in `getProtocolMappersStream()`
output but had its `setClaim` skipped vs. invoked. The fires-on-surface
predicate in the pseudocode below answers (b) only.

## Concrete `setClaim` overrides

`AbstractOIDCProtocolMapper.setClaim(IDToken, …)` is empty by default
(L156-160) and delegates to the deprecated 3-arg form (L143-145), also empty.
Concrete mappers extend `AbstractOIDCProtocolMapper` (often via
`AbstractPairwiseSubMapper` or `AbstractUserRoleMappingMapper`) and override
one of the `setClaim` overloads.

Notable concrete mappers (full catalog is [pending — Phase 3]; these are the
mappers exercised by the captured fixtures):

- `UserSessionNoteMapper` — surfaces `clientHost`, `clientAddress`, `client_id`
  from user-session notes set during client-credentials authentication.
- `UserPropertyMapper` — surfaces `preferred_username`, `email`,
  `email_verified` from user fields.
- `UserAttributeMapper` — surfaces a configurable user attribute under a
  configurable claim path.
- `UserRealmRoleMappingMapper` — populates `realm_access.roles` from the
  user's realm roles intersected with the role allowlist.
- `UserClientRoleMappingMapper` — populates `resource_access.<client>.roles`.
- `AllowedWebOriginsProtocolMapper` — populates `allowed-origins`.
- `AcrProtocolMapper` — populates `acr` when step-up authentication is on
  (otherwise `initToken` writes `acr` directly).
- `AudienceResolveProtocolMapper` — adds clientIds to `aud` for client roles
  the user holds whose owning client isn't already in `aud`.
- `AudienceProtocolMapper` — adds a configured clientId or custom audience
  string to `aud`. (The "Audience" mapper in the admin console.)
- `HardcodedClaim` — writes a configured constant to a configurable claim
  path. If configured against `aud`, it contributes there; otherwise it
  populates whatever path the operator chose.
- `HardcodedRole` (`oidc-hardcoded-role-mapper`) — injects a configured
  role into the resolved-roles cache unconditionally (no `*.token.claim`
  gate; overrides the transform methods). Surfaces only via the consumer
  role/audience mappers and their toggles; never runs on the ID token
  (no `OIDCIDTokenMapper`); bypasses `fullScopeAllowed`. See the
  [role-injection class](#mappers-that-override-the-gate-role-injection-class)
  section above and SKILL.md invariant 14.
- `RoleNameMapper` (`oidc-role-name-mapper`) — same override-the-gate
  class; renames a resolved role to a new realm/client position in place
  in the resolved-roles cache.
- `SubMapper` — populates `sub` from the user id (`initToken` only writes
  `sub` for TRANSIENT sessions).
- `SHA256PairwiseSubMapper` — concrete subclass of `AbstractPairwiseSubMapper`;
  populates `sub` with a per-sector pairwise pseudonym.
- `NonceBackwardsCompatibleMapper` — outlier: implements
  `OIDCAccessTokenMapper` and `ProtocolMapper` directly without extending
  `AbstractOIDCProtocolMapper`. Carries `nonce` through token refresh for
  pre-OIDC-1.0-final clients.

## Pseudocode for surface verification

> **Applies only to gated mappers.** This predicate assumes the mapper
> inherits `AbstractOIDCProtocolMapper`'s `transform<Surface>` gate. For
> the [role-injection class](#mappers-that-override-the-gate-role-injection-class)
> (`oidc-hardcoded-role-mapper`, `oidc-role-name-mapper`) it returns the
> wrong answer — those fire on every surface whose *interface* they
> implement, regardless of any `*.token.claim` value. Check the surface
> interfaces, not this predicate, for them.

```
fires_on_surface(mapper, surface, client, session):
    config ← mapper.config
    lightweight ← client.attr("client.use.lightweight.access.token.enabled") == "true"
                  OR session.attr("USE_LIGHTWEIGHT_ACCESS_TOKEN_ENABLED") == true
    match surface:
        access_token if lightweight   → config["lightweight.claim"]      == "true"
        access_token                  → config["access.token.claim"]     == "true"
        id_token                      → config["id.token.claim"]         == "true"
        userinfo:
            r ← config["userinfo.token.claim"]
            return r == "true" if r is set else config["id.token.claim"] == "true"
        introspection:
            r ← config["introspection.token.claim"]
            return r == "true" if r is set else config["access.token.claim"] == "true"
                                                       # NOT lightweight-aware
        access_token_response         → config["access.tokenResponse.claim"] == "true"
```

## See also

- [`TokenManager.java:793-841`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L793-L841) — the four access/userinfo/introspection/response transformers.
- [`TokenManager.java:973-981`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L973-L981) — `transformIDToken`.
- [`TokenManager.java:936-971`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L936-L971) — `TokenCollector` accumulator.
- [`AbstractOIDCProtocolMapper.java:73-160`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L73-L160) — toggle gates and `setClaim` defaults.
- [`OIDCAttributeMapperHelper.java:58-80`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L58-L80), [`387-427`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L387-L427) — config key constants and predicate implementations.
