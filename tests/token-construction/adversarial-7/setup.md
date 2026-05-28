# Setup — adversarial-7: the `oidc-hardcoded-role-mapper`

> **Builder's view. Contains the expected answer. The predictor must NOT
> read this file.**

## Invariant under test

The target skill (as of the commit this fixture was built against) does
**not** document the `oidc-hardcoded-role-mapper` (`HardcodedRole`) at
all. Its mapper-execution model is toggle-gated: every surface decision
flows through `fires_on_surface`, which reads `access.token.claim` /
`id.token.claim` / etc. from the mapper config. `HardcodedRole` breaks
that model in four ways, none currently captured:

1. **No surface toggles.** `HardcodedRole`'s only config key is `role`.
   It overrides `transformAccessToken`, `transformUserInfoToken`, and
   `transformIntrospectionToken` directly and calls `setClaim`
   **unconditionally** — it never consults `OIDCAttributeMapperHelper`.
   So it "fires" on access / userinfo / introspection regardless of any
   `*.token.claim` value. The skill's pseudocode, applied literally,
   mispredicts it as skipped (its config has no `access.token.claim`
   key, so `== "true"` is false). This is trap 1.

2. **Not an `OIDCIDTokenMapper`.** It implements only
   `OIDCAccessTokenMapper`, `UserInfoTokenMapper`,
   `TokenIntrospectionTokenMapper`. It therefore never runs during
   `transformIDToken`.

3. **It does not write the token claim itself.** `setClaim` adds the role
   to the `RoleResolveUtil` *resolved-roles cache* — a side `AccessToken`
   stored in a session attribute keyed `RESOLVED_ROLES:<sessionId>:<clientId>`
   — via `getResolvedRealmRoles(...,true).addRole(role)` /
   `getResolvedClientRoles(...,client,true).addRole(role)`. The role only
   reaches a real token when a **consumer** role-list mapper
   (`UserRealmRoleMappingMapper` / `UserClientRoleMappingMapper`) reads
   that cache and copies it. Those consumers have their own per-surface
   toggles.

4. **It bypasses `fullScopeAllowed` and the role allowlist.** The cache
   is first built from `clientSessionCtx.getRolesStream()` (the user's
   roles ∩ allowlist, shaped by `fullScopeAllowed`); `HardcodedRole`
   *adds* to that cache afterward. So the injected role appears even
   though the user does not hold it and `fullScopeAllowed=false`.

## Priority chain (all source-derived, deterministic)

`ProtocolMapperUtils` (services, tag 26.5.5):

| Constant | Value | Mapper |
| --- | --- | --- |
| `PRIORITY_ROLE_NAMES_MAPPER` | 10 | `RoleNameMapper` |
| `PRIORITY_HARDCODED_ROLE_MAPPER` | **20** | `HardcodedRole` |
| `PRIORITY_AUDIENCE_RESOLVE_MAPPER` | **30** | `AudienceResolveProtocolMapper` |
| `PRIORITY_ROLE_MAPPER` | **40** | `UserRealmRoleMappingMapper`, `UserClientRoleMappingMapper` |
| `PRIORITY_SCRIPT_MAPPER` | 50 | script mappers |

Because 20 < 30 < 40, `HardcodedRole` populates the resolved-roles cache
**before** both `AudienceResolveProtocolMapper` (reads
`getAllResolvedClientRoles` → adds any client with non-empty roles to
`aud`) and the role-list mappers (copy the cache onto the token) read it.
This makes the outcome deterministic — there is no HashSet-tie ambiguity
between writer and readers.

## This realm's consumer toggles (from `realm-config.json`, `roles` scope)

| Mapper | access | id | userinfo | introspection |
| --- | --- | --- | --- | --- |
| `realm roles` (`UserRealmRoleMappingMapper`) | true | **true** | **true** | true |
| `client roles` (`UserClientRoleMappingMapper`) | true | absent→**false** | absent→**false** (fallback to id, also false) | true |
| `audience resolve` (`AudienceResolveProtocolMapper`) | true | absent→**false** | absent→false | true |

(The `realm roles` mapper's `id.token.claim` was flipped to `true` for
this fixture; flipping it also set `userinfo.token.claim=true`. `client
roles` and `audience resolve` are left at defaults.)

## Expected result (the marked answer)

The resolved-roles cache after `HardcodedRole` (prio 20) runs on the
access-token pass contains: realm role `unassigned-realm-role`, and
client `adv7-resource` → `resource-reader`. That cache persists in the
session for the whole response build (access token, then ID token, then
userinfo all reuse it).

| Surface | Claim | Expected | Why |
| --- | --- | --- | --- |
| Access | `realm_access.roles ⊇ {unassigned-realm-role}` | **present** | `realm roles` consumer access=true reads warm cache |
| Access | `resource_access["adv7-resource"].roles ⊇ {resource-reader}` | **present** | `client roles` consumer access=true |
| Access | `aud ⊇ {adv7-resource}` | **present** | `AudienceResolve` (30) sees client role injected at 20 |
| ID | `realm_access.roles ⊇ {unassigned-realm-role}` | **present** | `realm roles` consumer id=true; reads same warm cache even though `HardcodedRole` itself isn't an ID-token mapper |
| ID | `resource_access["adv7-resource"]` exists | **absent** | `client roles` consumer id=false → no consumer on ID surface |
| ID | `aud ⊇ {adv7-resource}` | **absent** | `AudienceResolve` id=false; ID `aud` = `["adv7-client"]` (issuedFor) |
| Userinfo | `realm_access.roles ⊇ {unassigned-realm-role}` | **present** | `realm roles` consumer userinfo=true |
| Userinfo | `resource_access["adv7-resource"]` exists | **absent** | `client roles` userinfo absent → fallback to id=false (invariant 5) |
| Cross | user lacking role + `fullScopeAllowed=false` | **irrelevant** | `HardcodedRole` injects post-allowlist; bypasses both |

The headline contrast that defeats the naive readings: the realm
hardcoded role appears on **all three** surfaces, while the client
hardcoded role appears **only on the access token** — same injection,
different consumer toggles. And the ID token carries `realm_access`
despite `HardcodedRole` never running on the ID surface, because the
*consumer* (not the hardcoded mapper) runs on the ID surface and reads
the cross-surface-persistent cache.

## Trap menu (builder's copy — correct entry marked)

1. Everything absent (literal toggle pseudocode on the hardcoded mapper). WRONG.
2. Everything absent (user lacks roles + fullScopeAllowed=false). WRONG.
3. All effects present uniformly on all surfaces. WRONG (ID client_role / aud, userinfo client_role are absent).
4. Roles present everywhere but `aud` never has adv7-resource. WRONG (access aud present).
5. Access present; ID + userinfo all absent. WRONG (ID + userinfo realm_role are present).
6. **CORRECT — the mixed combination in the table above:** access {realm present, client present, aud present}; ID {realm present, client absent, aud absent}; userinfo {realm present, client absent}; bypass irrelevant.

## Sources (tag 26.5.5)

- `services/.../protocol/oidc/mappers/HardcodedRole.java` — unconditional `setClaim`, interfaces, `PRIORITY_HARDCODED_ROLE_MAPPER`.
- `services/.../utils/RoleResolveUtil.java` — `getResolvedRealmRoles`/`getResolvedClientRoles`/`getAllResolvedClientRoles`, session-attr cache, `getAndCacheResolvedRoles` built from `clientSessionCtx.getRolesStream()`.
- `services/.../protocol/oidc/mappers/UserRealmRoleMappingMapper.java` / `UserClientRoleMappingMapper.java` — read the cache with `createIfMissing=false`, copy onto token.
- `services/.../protocol/oidc/mappers/AudienceResolveProtocolMapper.java` — `getAllResolvedClientRoles` → `aud`, priority 30.
- `services/.../protocol/ProtocolMapperUtils.java` — priority constants.
- `services/.../protocol/oidc/TokenManager.java` `generateIDToken` — `new IDToken()` copies only scalar fields, not `realm_access`/`resource_access`.
