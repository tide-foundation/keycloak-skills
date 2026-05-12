# Source pointers

> **All source paths in this document are remote URLs at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak) tag `26.5.5` — they are NOT files in this working directory.** Do not attempt to read them from the local filesystem; fetch with `WebFetch` if you need to inspect them. Shorthand references such as `TokenManager.L640` or `DCSC.L188-212` refer to the same upstream Java sources, not to local files. The base URL prefix for any path below is `https://github.com/keycloak/keycloak/blob/26.5.5/`.

All paths and line ranges are at tag **26.5.5**. The links below resolve to the
upstream Keycloak repository on GitHub.

## Class → file → line ranges

### `TokenManager`

[`services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java)

| Range | Symbol | Purpose |
| --- | --- | --- |
| [L525-535](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L525-L535) | `createClientAccessToken` | Top-level entry point. |
| [L605-635](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L605-L635) | `getAccess` | Role allowlist (full vs. role-intersection branch). TRACE log at L607 (full) and L621-622 (per-scope). |
| [L640-695](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L640-L695) | `getRequestedClientScopes` | Candidate scope set. Includes `tryResolveDynamicClientScope` at L679-695. |
| [L705-762](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L705-L762) | `isValidScope` | Pre-flight scope validation. Logs `Scopes to validate` at L745-748. Throws on unknown name path at L754-759. |
| [L781-790](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L781-L790) | `verifyConsentStillAvailable` | Silent unless `client.isConsentRequired()`. |
| [L793-810](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L793-L810) | `transformAccessToken` | Access-token mapper loop + `restrictRequestedAudience` call. |
| [L811-821](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L811-L821) | `transformAccessTokenResponse` | Response-envelope mapper loop. |
| [L823-832](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L823-L832) | `transformUserInfoAccessToken` | Userinfo mapper loop. Note: the leaf interface method is `transformUserInfoToken`. |
| [L834-843](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L834-L843) | `transformIntrospectionAccessToken` | Introspection mapper loop. |
| [L845-934](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L845-L934) | `generateUserInfoClaims` | Projection of AccessToken → flat userinfo map. `otherClaims` bulk copy at L914. |
| [L936-971](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L936-L971) | `TokenCollector<T>` | Sequential-only fold accumulator used by all five `transform<Surface>`. |
| [L973-981](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L973-L981) | `transformIDToken` | ID-token mapper loop. |
| [L983-1015](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L983-L1015) | `initToken` | Access-token base claims. |
| [L1010-1068](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1010-L1068) | `getTokenExpiration` | Lifespan policy. |
| [L1262-1295](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1262-L1295) | `AccessTokenResponseBuilder.generateIDToken` | ID-token construction (base + transform). |
| [L1310-1381](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1310-L1381) | `AccessTokenResponseBuilder.build` | Encodes tokens; computes `at_hash`/`c_hash`/`s_hash` post-encode at L1338-1341. Invokes `transformAccessTokenResponse` at L1372. |
| [L1397](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1397) | `formatTokenType` | Sets `typ`. |
| [L1406-1414](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L1406-L1414) | `restrictRequestedAudience` | Post-mapper audience prune. |

### `DefaultClientSessionContext` (DCSC)

[`services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java)

| Range | Symbol | Purpose |
| --- | --- | --- |
| [L60-145](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L60-L145) | fields, constructor, `getClientScopesStream` | Lazy `allowedClientScopes` filter (L130-137). |
| [L161-167](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L161-L167) | `getProtocolMappersStream` | Returns the cached set; calls `loadProtocolMappers` on first access. |
| [L188-212](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L188-L212) | `getScopeString` | Projects allowed scopes to the `scope` claim. Filters out `ClientModel` at L200; `attachOIDCScope` at L207-209. |
| [L252-267](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L252-L267) | `isAllowed` | Restricted-scope filter + delegate to `isClientScopePermittedForUser`. |
| [L270-300](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L270-L300) | `isClientScopePermittedForUser` | Role-intersection check; `REQUESTED_AUDIENCE_CLIENTS` filter at L290-295. |
| [L303-307](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L303-L307) | `loadRoles` | Caches `getAccess` result; this is what triggers the `Using full scope` TRACE. |
| [L310-326](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java#L310-L326) | `loadProtocolMappers` | Mapper-set assembly: union, protocol filter, `isEnabled` filter, dedup-to-Set. Warn at L315 if client has no protocol. |

### `ProtocolMapperUtils`

[`services/src/main/java/org/keycloak/protocol/ProtocolMapperUtils.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/ProtocolMapperUtils.java)

| Range | Symbol | Purpose |
| --- | --- | --- |
| [L150-175](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/ProtocolMapperUtils.java#L150-L175) | `getSortedProtocolMappers` | Hydrate-and-filter pairs, append DPoP transient (L165-167) for OIDC, sort by priority ASC (L169, L172-175). |

### `AbstractOIDCProtocolMapper`

[`services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java)

(Note: this file is at `services/.../mappers/` at this tag, not at
`server-spi-private/...` as some older docs suggest.)

| Range | Symbol | Purpose |
| --- | --- | --- |
| [L73-82](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L73-L82) | `transformUserInfoToken` | Userinfo toggle gate. |
| [L84-87](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L84-L87) | `getShouldUseLightweightToken` | Reads client/session attribute. |
| [L89-99](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L89-L99) | `transformAccessToken` | Access-token toggle gate; lightweight-aware. |
| [L101-110](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L101-L110) | `transformIDToken` | ID-token toggle gate. |
| [L112-122](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L112-L122) | `transformAccessTokenResponse` | Response-envelope toggle gate. |
| [L124-133](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L124-L133) | `transformIntrospectionToken` | Introspection toggle gate. |
| [L143-145](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L143-L145) | `setClaim(IDToken, model, userSession)` (deprecated) | Default empty. |
| [L156-160](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java#L156-L160) | `setClaim(IDToken, model, userSession, session, ctx)` | Default empty; delegates to L143-145. |

### `OIDCAttributeMapperHelper`

[`services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java)

| Range | Symbol | Purpose |
| --- | --- | --- |
| [L58-80](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L58-L80) | Constants | Config-key string constants. |
| [L387-389](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L387-L389) | `includeInIDToken` | `id.token.claim == "true"`. |
| [L391-393](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L391-L393) | `includeInAccessToken` | `access.token.claim == "true"`. |
| [L395-397](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L395-L397) | `includeInAccessTokenResponse` | `access.tokenResponse.claim == "true"`. |
| [L403-411](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L403-L411) | `includeInUserInfo` | `userinfo.token.claim`, fallback to `id.token.claim`. |
| [L414-422](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L414-L422) | `includeInIntrospection` | `introspection.token.claim`, fallback to `includeInAccessToken` (lightweight-unaware). |
| [L425-427](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAttributeMapperHelper.java#L425-L427) | `includeInLightweightAccessToken` | `lightweight.claim == "true"`. |

### Surface interfaces

[`services/src/main/java/org/keycloak/protocol/oidc/mappers/`](https://github.com/keycloak/keycloak/tree/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers)

| File | Interface method |
| --- | --- |
| [`OIDCAccessTokenMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAccessTokenMapper.java) | `transformAccessToken(AccessToken, …)` |
| [`OIDCIDTokenMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCIDTokenMapper.java) | `transformIDToken(IDToken, …)` |
| [`UserInfoTokenMapper.java:31`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/UserInfoTokenMapper.java#L31) | `transformUserInfoToken(AccessToken, …)` |
| [`TokenIntrospectionTokenMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/TokenIntrospectionTokenMapper.java) | `transformIntrospectionToken(AccessToken, …)` |
| [`OIDCAccessTokenResponseMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/OIDCAccessTokenResponseMapper.java) | `transformAccessTokenResponse(AccessTokenResponse, …)` |
| [`LogoutTokenMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/LogoutTokenMapper.java) | `transformLogoutToken(LogoutToken, …)` (out of scope for this skill) |

### Pre-flight (only for completing the loop with the WARN log line)

| File | Lines | Purpose |
| --- | --- | --- |
| [`services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java) | [L240-259](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java#L240-L259) | Calls `isValidScope`; throws `CorsErrorResponseException` with `INVALID_SCOPE` at L255; `event.error(INVALID_REQUEST)` at L254. |

### Token representation

| File | Purpose |
| --- | --- |
| [`core/src/main/java/org/keycloak/representations/AccessToken.java`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/representations/AccessToken.java) | Claim field declarations. |
| [`core/src/main/java/org/keycloak/representations/IDToken.java`](https://github.com/keycloak/keycloak/blob/26.5.5/core/src/main/java/org/keycloak/representations/IDToken.java) | Claim field declarations (superclass). |

### Default-true scope flag

| File | Lines | Purpose |
| --- | --- | --- |
| [`server-spi/src/main/java/org/keycloak/models/ClientScopeModel.java`](https://github.com/keycloak/keycloak/blob/26.5.5/server-spi/src/main/java/org/keycloak/models/ClientScopeModel.java) | [L109-112](https://github.com/keycloak/keycloak/blob/26.5.5/server-spi/src/main/java/org/keycloak/models/ClientScopeModel.java#L109-L112) | `isIncludeInTokenScope()` defaults to `true` when the attribute is missing. Source of the most common "why is this scope appearing in `scope`?" question. |

## Mapper directory inventory

[`services/src/main/java/org/keycloak/protocol/oidc/mappers/`](https://github.com/keycloak/keycloak/tree/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers) contains **35**
.java files at this tag:

- **24 concrete mapper classes** — leaves of the call tree. Most extend
  `AbstractOIDCProtocolMapper` directly; some via `AbstractPairwiseSubMapper`
  or `AbstractUserRoleMappingMapper`. One outlier — `NonceBackwardsCompatibleMapper`
  — implements `OIDCAccessTokenMapper` and `ProtocolMapper` directly without
  extending `AbstractOIDCProtocolMapper`.
- **6 surface interfaces**: `OIDCAccessTokenMapper`, `OIDCIDTokenMapper`,
  `UserInfoTokenMapper`, `TokenIntrospectionTokenMapper`,
  `OIDCAccessTokenResponseMapper`, `LogoutTokenMapper`.
- **3 abstract bases**: `AbstractOIDCProtocolMapper`, `AbstractPairwiseSubMapper`,
  `AbstractUserRoleMappingMapper`.
- **2 helpers**: `OIDCAttributeMapperHelper`, `PairwiseSubMapperHelper`.

A per-mapper catalog (claim path written, surface defaults, edge cases) is the
next research phase and is not yet part of this skill.

## Path corrections relative to common mistakes

| What you might grep for | What's actually at 26.5.5 |
| --- | --- |
| `server-spi-private/.../mappers/AbstractOIDCProtocolMapper.java` | [`services/.../mappers/AbstractOIDCProtocolMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/mappers/AbstractOIDCProtocolMapper.java) |
| `protocol/oidc/DefaultClientSessionContext.java` | [`services/util/DefaultClientSessionContext.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java) |
| `TokenManager.transformUserInfoToken` | `TokenManager.transformUserInfoAccessToken` (the interface method on `UserInfoTokenMapper` is `transformUserInfoToken`) |
