# Mapper execution pipeline

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
- `SubMapper` — populates `sub` from the user id (`initToken` only writes
  `sub` for TRANSIENT sessions).
- `SHA256PairwiseSubMapper` — concrete subclass of `AbstractPairwiseSubMapper`;
  populates `sub` with a per-sector pairwise pseudonym.
- `NonceBackwardsCompatibleMapper` — outlier: implements
  `OIDCAccessTokenMapper` and `ProtocolMapper` directly without extending
  `AbstractOIDCProtocolMapper`. Carries `nonce` through token refresh for
  pre-OIDC-1.0-final clients.

## Pseudocode for surface verification

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

- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:793-841` — the four access/userinfo/introspection/response transformers.
- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:973-981` — `transformIDToken`.
- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:936-971` — `TokenCollector` accumulator.
- `services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java:73-160` — toggle gates and `setClaim` defaults.
- `services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java:58-80, 387-427` — config key constants and predicate implementations.
