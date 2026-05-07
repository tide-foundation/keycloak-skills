# Base claims

Defines the claims placed on the token *before* any mapper runs, and where
each is sourced from. Two builders contribute base claims:

- **Access token**: `TokenManager.initToken` (L983-1015).
- **ID token**: `AccessTokenResponseBuilder.generateIDToken` (L1262-1295).

Both run *before* the corresponding `transform<Surface>` call, so mapper
output overrides base values for any claim that mappers also write. Userinfo
and introspection have **no base claims** of their own — they are decorations
on top of an already-built `AccessToken`.

## Access-token base claims (`initToken`)

```
initToken(session, realm, client, user, userSession, clientSessionCtx, uriInfo):
    token ← new AccessToken()
    token.id   ← TokenContextEncoderProvider.encodeTokenId(...)         # L987-989
    token.typ  ← formatTokenType(client, token)                         # L991  (delegates to L1397)
    if userSession.persistenceState == TRANSIENT:
        token.sub ← user.getId()                                        # L992-994
        # else: sub is left null, populated later by SubMapper
    token.iat  ← AccessToken.issuedNow()                                # L995
    token.azp  ← client.getClientId()                                   # L996  (issuedFor → "azp")
    token.iss  ← clientSession.getNote(OIDCLoginProtocol.ISSUER)        # L999
    token.scope ← clientSessionCtx.getScopeString()                     # L1000
    if NOT Feature.STEP_UP_AUTHENTICATION:
        token.acr ← AuthenticationManager.isSSOAuthentication(...) ? "0" : "1"
                                                                        # L1004-1007
        # If step-up is on, acr is left for AcrProtocolMapper to write.
    token.sid  ← userSession.getId()                                    # L1009
    token.exp  ← getTokenExpiration(realm, client, userSession, clientSession)
                                                                        # L1010-1013, L1027
    return token
```

| Claim | Source | Notes |
| --- | --- | --- |
| `jti` (`id` field) | `TokenContextEncoderProvider.encodeTokenId` | Includes a token-context prefix (e.g., `trrtcc:` for refresh-token-driven access tokens). |
| `typ` | `formatTokenType` (L1397-1404) | Returns `accessToken.getType()` if non-null, else `TokenUtil.TOKEN_TYPE_BEARER` ("Bearer"). Lowercased iff `OIDCAdvancedConfigWrapper.fromClientModel(client).isUseLowerCaseInTokenResponse()` is true. The accessToken passed in is the one being initialized — its type is null at this call site, so the default branch (`TOKEN_TYPE_BEARER`) is what `initToken` produces; non-default values (e.g., DPoP) come from later code paths that re-call `formatTokenType` with an already-typed token. |
| `sub` | `user.getId()` **only** if `userSession.persistenceState == TRANSIENT`. Otherwise null at this point — `SubMapper` writes it. | Pairwise sub mappers also write here. |
| `iat` | now | Always reset; never copied. |
| `azp` | `client.getClientId()` | The "issued for" / `azp` claim. |
| `iss` | `clientSession.getNote(OIDCLoginProtocol.ISSUER)` | Set during auth-session attach (upstream of post-auth). If the note is missing, `iss` is null. |
| `scope` | `clientSessionCtx.getScopeString()` | Names of allowed client scopes with `isIncludeInTokenScope=true` (default true), with `openid` re-attached if the original request was OIDC. See [scope-resolution.md](scope-resolution.md). |
| `acr` | `"0"` (SSO) or `"1"` (fresh auth) — only when `STEP_UP_AUTHENTICATION` is **off**. | When step-up is on, `acr` comes from `AcrProtocolMapper`. |
| `sid` | `userSession.getId()` | May be **subsequently nulled** by `OAuth2GrantTypeBase.java:132` on the transient branch — fires when the grant's `useRefreshToken()` returns false (default for `client_credentials`). See [post-mapper.md](post-mapper.md#access-token-transient-session-sid-nulling). |
| `exp` | `getTokenExpiration(...)` | Lifespan policy — out of model for claim shape, but included in the base set. |

Claims **not** set by `initToken` and therefore mapper-only:

- `aud` — populated by `AudienceResolveProtocolMapper` (role-driven) and
  `AudienceProtocolMapper` (operator-configured), then narrowed by
  `restrictRequestedAudience` (see [post-mapper.md](post-mapper.md)).
- `realm_access`, `resource_access` — `UserRealmRoleMappingMapper`,
  `UserClientRoleMappingMapper`.
- `preferred_username`, `email`, `email_verified`, `given_name`, `family_name`,
  etc. — `UserPropertyMapper`.
- `clientHost`, `clientAddress`, `client_id` — `UserSessionNoteMapper` on the
  `service_account` scope.
- `allowed-origins` — `AllowedWebOriginsProtocolMapper`.
- `nonce` — see ID-token base claims; on the access token only if a mapper
  writes it.

## ID-token base claims (`generateIDToken`)

`generateIDToken` requires a non-null *transformed* access token
(L1263-1265). The ID token is **not** a copy of the access token; only some
fields carry over.

```
generateIDToken(isIdTokenAsDetachedSignature):
    idToken ← new IDToken()
    idToken.id    ← SecretGenerator.generateSecureID()                  # L1266-1267
    idToken.typ   ← TokenUtil.TOKEN_TYPE_ID                             # L1268
    idToken.sub   ← userSession.getUser().getId()                       # L1269  (NOT copied from accessToken)
    idToken.aud   ← client.getClientId()                                # L1270  (NOT copied)
    idToken.iat   ← idToken.issuedNow()                                 # L1271  (fresh, NOT copied)
    idToken.azp   ← accessToken.getIssuedFor()                          # L1272
    idToken.iss   ← accessToken.getIssuer()                             # L1273
    idToken.nonce ← clientSessionCtx.getAttribute(NONCE_PARAM)          # L1274
    idToken.sid   ← accessToken.getSessionId()                          # L1275
    idToken.exp   ← accessToken.getExp()                                # L1276
    if NOT Feature.STEP_UP_AUTHENTICATION:
        idToken.acr ← accessToken.acr                                   # L1279-1281
    if NOT detached-signature mode:
        transformIDToken(session, idToken, userSession, clientSessionCtx)  # L1284 → L973
    return idToken
```

| ID-token claim | Source | Inherits from access token? |
| --- | --- | --- |
| `jti` | `SecretGenerator.generateSecureID()` | No — fresh. |
| `typ` | `TOKEN_TYPE_ID` constant | No. |
| `sub` | `userSession.getUser().getId()` | **No** — direct from user, not from accessToken. So a `SubMapper`-driven pairwise sub on the access token does **not** carry into the base ID token; the ID-token side `SubMapper` writes it again on the ID token. |
| `aud` | `client.getClientId()` | **No** — the ID token starts with a single-element `aud` of the requesting client, distinct from the access token's `aud`. ID-token mappers can extend it. |
| `iat` | now | No — fresh. **Note:** `iat` is reset via `idToken.issuedNow()` (second precision); when the ID-token call follows the access-token call inside the same second, the two values collide numerically. Verifiers should not treat the equality as evidence that `iat` was copied. |
| `azp` | `accessToken.getIssuedFor()` | Yes (transitively). |
| `iss` | `accessToken.getIssuer()` | Yes. |
| `nonce` | `clientSessionCtx.getAttribute(NONCE_PARAM)` | No — direct from session ctx. Null if no nonce was sent. |
| `sid` | `accessToken.getSessionId()` | Yes — including any post-`transformAccessToken` mutation. If the access token's `sid` was nulled on the transient branch (`OAuth2GrantTypeBase.java:132`), the ID token inherits `null` here. See [post-mapper.md](post-mapper.md#access-token-transient-session-sid-nulling). |
| `exp` | `accessToken.getExp()` | Yes. |
| `acr` | `accessToken.acr` (only when step-up is off) | Yes. |

Implication: any access-token mapper that mutates `iss`, `sid`, `exp`, `azp`,
or `acr` (when step-up is off) **changes the ID token's base** unless an
ID-token mapper rewrites the field.

## Userinfo "base claims"

Userinfo has none. `transformUserInfoAccessToken` (L823) is invoked with the
already-built `AccessToken` as input; userinfo mappers decorate it. Then
`generateUserInfoClaims` (L845-934) projects to a flat map. The projection
pulls `sub` from the AccessToken, copies `otherClaims` in bulk at L914, and
adds a few standard userinfo wire fields outside the claims map.

## Introspection "base claims"

Same shape as userinfo: the input is the (separately built) AccessToken;
introspection mappers decorate it; `active: true` and a few wire-level
introspection fields are added outside this skill's scope.

## See also

- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:983-1015` — `initToken`.
- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:1262-1295` — `generateIDToken`.
- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:1397` — `formatTokenType`.
- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:845-934` — `generateUserInfoClaims`.
- `core/src/main/java/org/keycloak/representations/AccessToken.java` — claim field declarations.
- `core/src/main/java/org/keycloak/representations/IDToken.java` — claim field declarations (superclass).
