# Scope resolution

Defines how the `(client, scopeParam, user)` triple becomes the
`allowedClientScopes` set on `DefaultClientSessionContext` (DCSC), and how that
set projects into the `scope` claim. Two cooperating functions:
`TokenManager.getRequestedClientScopes` (the candidate set) and
`DefaultClientSessionContext.isAllowed` (the filter).

## Algorithm

```
# STEP 1 — candidate set    (TokenManager.java:640-677)
candidates ← values(client.getClientScopes(default=true))  ∪  { client }
            # `client` itself is in the set because ClientModel extends
            # ClientScopeModel — its own scope mappings participate
            # downstream. It is filtered out of the `scope` claim later
            # (DCSC.L200) but participates in mapper-set assembly.

if scopeParam == null:
    return candidates                                    # L650-652

# Drop default scopes whose name+":" appears as a dynamic-scope prefix in
# scopeParam AND which carry an OrganizationMembershipMapper. Deduplicates
# dynamic organization scopes.                          # L656-660
candidates ← { s ∈ candidates :
                 s == client
              ∨ NOT scopeParam.contains(s.name + ":")
              ∨ NO OrganizationMembershipMapper on s }

# Add OPTIONAL scopes that the param explicitly named.   # L662-676
optional ← client.getClientScopes(default=false)
for name in scopeParam.split(/\s+/).distinct():
    if name in optional:
        candidates.add(optional[name])
    elif Feature.ORGANIZATION enabled:
        s ← tryResolveDynamicClientScope(name, user, session)   # L679-695
        if s != null: candidates.add(s)
    else:
        skip                                # silently — pre-flight isValidScope
                                            # would already have rejected unknown names
return candidates.distinct()


# STEP 2 — filter to allowed   (DCSC.L130-137; lazy on first read)
allowed ← { s ∈ requestedScopes : isAllowed(s) }

isAllowed(s):                                           # DCSC.L252-267
    if restrictedScopes != null and s.name ∉ restrictedScopes:
        return false                                    # L253-256
    return isClientScopePermittedForUser(s)             # L258

isClientScopePermittedForUser(s):                       # DCSC.L270-300
    if s == null: return false
    if s instanceof ClientModel: return true            # the client always passes
    roles ← s.getScopeMappingsStream().collect(Set)
    if roles is empty: return true                      # no role mappings → universal
    roles ← RoleUtils.expandCompositeRoles(roles)
    if REQUESTED_AUDIENCE_CLIENTS attribute set:        # L290-295
        roles ← { r ∈ roles : NOT r.isClientRole()
                  ∨ r.getContainerId() ∈ requestedAudienceClientIds }
    return (roles ∩ getDeepUserRoleMappings(user)) is non-empty
```

`isAllowed` is called lazily by `getClientScopesStream` on first access
(DCSC.L131). The result is cached on the context — repeated calls are O(1).

## What `client.getClientScopes(true)` actually returns

The Step 1 candidate set seeds from `client.getClientScopes(default=true)`,
which returns only the scopes **actually attached** to the client. The
realm-level `defaultDefaultClientScopes` and `defaultOptionalClientScopes`
lists are templates: when a client is *created* (or via the admin API
`addDefaultClientScope`), Keycloak filters those templates by the client's
protocol and attaches the matching ones. SAML-only built-in scopes
(`role_list`, `saml_organization`) therefore never appear in the candidate
set for an OIDC client even though they are listed at the realm level. The
filter happens at attach time, not at scope-resolution time.

This matters when reading a realm export: `defaultDefaultClientScopes` shows
SAML names alongside OIDC names, but the OIDC client's own attached-scope
list will not contain them. The skill's algorithm is correct — it consumes
whatever `client.getClientScopes(true)` returns — but verifiers re-deriving
the candidate set from `defaultDefaultClientScopes` directly must apply the
protocol filter themselves.

## Pre-flight scope validation

Before any post-auth code runs, `OAuth2GrantTypeBase.getRequestedScopes` calls
`TokenManager.isValidScope`
(`OAuth2GrantTypeBase.java:240-259`, `TokenManager.java:705-762`). If any token
in the param doesn't appear in the union of default + optional + dynamic
scopes registered for the client, the request is rejected with
`OAuthErrorException.INVALID_SCOPE` and the message
`"Invalid scopes: " + scope` (TokenManager.L755-759, throw at
OAuth2GrantTypeBase.L255). `event.error(Errors.INVALID_REQUEST)` produces a
`CLIENT_LOGIN_ERROR` WARN. Pre-flight rejection means **no token, no
clientSessionCtx, no mappers**.

## The `scope` claim

The claim is `DCSC.getScopeString()` (DCSC.L188-212), not the input param:

```
getScopeString(ignoreIncludeInTokenScope=false):
    s ← allowedClientScopes
        .filter(NOT instanceof ClientModel)             # DCSC.L200
        .filter(scope.isIncludeInTokenScope() ∨ ignoreIncludeInTokenScope)
        .map(name).join(" ")
    if TokenUtil.isOIDCRequest(clientSession.getNote(SCOPE)):  # original param had `openid`
        s ← TokenUtil.attachOIDCScope(s)                # prepends "openid" if absent
    return s
```

`ClientScopeModel.isIncludeInTokenScope()` defaults to **true** when the
`include.in.token.scope` attribute is missing
(`ClientScopeModel.java:109-112`). Most "this scope is appearing in the token
even though I didn't expect it" reports trace to this default. Built-in scopes
that are explicit `false` in the realm export (and therefore absent from the
`scope` claim despite being applied): `roles`, `web-origins`, `basic`, `acr`,
`service_account`. `email`, `profile`, `offline_access` have no
`include.in.token.scope` attribute set, so they appear.

## `service_account` auto-attachment

When `serviceAccountsEnabled=true` on the client, the realm's `service_account`
client scope is attached at runtime — it is **not** required to appear in the
client's default-scopes list in the realm export. The fixtures verify this:
`logs-openid-offline-access.log` shows `service_account` in the validation set
even though it is not in `defaultDefaultClientScopes`. The skill must include
`service_account` in the candidate set whenever
`client.serviceAccountsEnabled` is true. The mappers on this scope produce
`clientHost`, `clientAddress`, and `client_id`.

## `fullScopeAllowed` interaction (clarification)

`fullScopeAllowed` does **not** affect scope resolution. It controls
`TokenManager.getAccess` (L605-635), which produces the *role allowlist* used
by role mappers and `restrictRequestedAudience`. The scope set, mapper set,
and `scope` claim are identical for full-scope and restricted clients with
the same scope param. The empirical token-body diff (missing
`realm_access`, `resource_access`, `aud`) on the restricted fixture is driven
by role mappers seeing an empty role set, not by scope resolution. See
[base-claims.md](base-claims.md) and [post-mapper.md](post-mapper.md).

## Edge cases

- **Empty `scopeParam`** vs **null `scopeParam`**: a non-null empty/whitespace
  param still passes through `isValidScope` (which short-circuits at L723-725
  after stripping `openid`). The candidate set ends up identical to the
  null-param case (default scopes + client). Behavior diverges only in whether
  the `Scopes to validate` TRACE pair fires.
- **`openid` in the param**: stripped from the iteration set in `isValidScope`
  at L719-721 (`TokenUtil.isOIDCRequest` is true → remove). It never needs to
  be a registered client scope; it is a *protocol marker* read directly off
  the auth-session note.
- **Duplicate names in the param**: deduped by `.distinct()` at L666.
- **Dynamic scope rejected by `tryResolveDynamicClientScope`**: silently
  skipped by Step 1. If the name is otherwise unknown, pre-flight
  `isValidScope` still rejects.

## See also

- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:640-695` — candidate-set assembly.
- `services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java:705-762` — pre-flight validation.
- `services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java:130-145` — `getClientScopesStream` (lazy filter).
- `services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java:188-212` — `getScopeString` (`scope` claim).
- `services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java:252-300` — `isAllowed` and `isClientScopePermittedForUser`.
- `server-spi/src/main/java/org/keycloak/models/ClientScopeModel.java:109-112` — `isIncludeInTokenScope` default.
- `services/src/main/java/org/keycloak/protocol/oidc/grants/OAuth2GrantTypeBase.java:240-259` — pre-flight call site.
