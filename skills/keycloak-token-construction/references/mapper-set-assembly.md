# Mapper-set assembly

Defines how the mapper set is gathered from the client + allowed scopes,
deduplicated, and ordered for execution. The set is identical across all five
surfaces; the *surface* filter is applied later by `transform<Surface>` (see
[mapper-execution.md](mapper-execution.md)).

## Where the mapper set lives

`DefaultClientSessionContext.protocolMappers` —
`Set<ProtocolMapperModel>`, lazy. Computed on first call to
`getProtocolMappersStream()` (DCSC.L161-167) by `loadProtocolMappers`
(DCSC.L310-326).

## Algorithm

```
loadProtocolMappers(allowedClientScopes, client):           # DCSC.L310-326
    if client.getProtocol() == null:
        warn "Client doesn't have protocol set"             # DCSC.L315
        return ∅

    return ⋃ { s.getProtocolMappersStream() : s ∈ allowedClientScopes }
           .filter(m -> m.getProtocol() == client.getProtocol())
           .filter(m -> ProtocolMapperUtils.isEnabled(session, m))
           .collect(toSet())                                # DCSC.L321-325
```

The fold is over **`allowedClientScopes`** — the same set produced by scope
resolution, including the client itself (because `ClientModel extends
ClientScopeModel`). The client's own scope-mapper attachments participate.

## Deduplication semantics

Collected to `Set<ProtocolMapperModel>`. Equality on `ProtocolMapperModel` is
identity-on-id (in the JPA model). Therefore:

- The **same** `ProtocolMapperModel` instance attached to two different scopes
  appears once in the set.
- Two **different** `ProtocolMapperModel` instances with the same *name* (e.g.,
  two "username" mappers attached to two different scopes) appear as **two
  distinct entries**.

A verifier that deduplicates by claim name will under-count the second case.
Trust the source's identity-based dedup; check by mapper id, not name.

## Sort order

Done at use time, by `ProtocolMapperUtils.getSortedProtocolMappers`
(`services/.../protocol/ProtocolMapperUtils.java:150-175`):

```
getSortedProtocolMappers(session, ctx, predicate):           # PMU.L150
    pairs ← ctx.getProtocolMappersStream()                  # the dedup'd set
            .map(m -> (m, ProtocolMapperFactory.lookup(m)))
            .filter(pair -> pair.factory != null)           # drop unregistered
            .filter(pair -> predicate.test(pair))           # surface filter
            .toList()
    if client.getProtocol() == "openid-connect":
        pairs.add(DPoPUtil.getTransientProtocolMapper())    # PMU.L165-167
    return pairs.stream().sorted(byPriorityAsc)             # PMU.L169, L172-175
```

The `predicate` is the surface filter. Examples:

- Access token: `pair -> pair.factory instanceof OIDCAccessTokenMapper`
- ID token: `pair -> pair.factory instanceof OIDCIDTokenMapper`
- Userinfo: `pair -> pair.factory instanceof UserInfoTokenMapper`
- Introspection: `pair -> pair.factory instanceof TokenIntrospectionTokenMapper`
- Response envelope: `pair -> pair.factory instanceof OIDCAccessTokenResponseMapper`

A factory may implement multiple surface interfaces — most do. The toggle
check inside `transform<Surface>` decides whether the mapper *fires* on this
specific surface. The interface check decides whether the mapper *sees* this
surface at all.

### Tie-breaking is non-deterministic

`ProtocolMapperUtils.compare` returns only priority (PMU.L172-175).
`Stream.sorted` is stable, but the upstream is a `HashSet` — input order is
not specified. For two mappers with equal priority writing the same claim
path, the winner depends on `HashSet` iteration order. **If this matters,
require distinct priorities** or flag the case as unverifiable.

## The transient DPoP mapper

For OIDC clients, `DPoPUtil.getTransientProtocolMapper()` is appended at
PMU.L165-167. It is not stored in the realm; it is constructed per request.
Its surface dispatch follows the same toggle logic. Treat it as a member of
the set even though it does not appear in `realm-export.json`.

## Inputs that quietly change the set

- **`fullScopeAllowed`** does **not** change this set. It changes the role
  allowlist input to role mappers; the mapper set itself is unaffected.
- **`restrictedScopes` (token exchange)** changes which scopes pass `isAllowed`,
  which changes which mappers are pulled into the union. Token exchange can
  therefore see a strictly smaller mapper set than the unrestricted issuance.
- **`Constants.REQUESTED_AUDIENCE_CLIENTS`** does not change the set, but it
  changes the role allowlist (DCSC.L290-295) and triggers
  `restrictRequestedAudience` post-mapper.
- **`ProtocolMapperUtils.isEnabled(session, mapper)`** at PMU.L177-179 —
  returns `true` iff the `ProtocolMapper` provider factory keyed by
  `mapper.getProtocolMapper()` is registered on the `KeycloakSessionFactory`.
  It is **not** a feature-flag check or a config-aware gate: it simply drops
  mappers whose provider class isn't loaded in this server (e.g., a mapper
  whose providing extension is missing or whose feature-gated factory wasn't
  initialized). Verifiers can model this by maintaining a known-providers set
  and dropping any mapper whose `protocolMapper` id isn't in it.

## Pseudocode summary for verifiers

```
mapperSet(client, allowedScopes, session, surface):
    raw ← ⋃ { s.getProtocolMappersStream() : s ∈ allowedScopes }
    raw ← raw.filter(m -> m.protocol == client.protocol)
    raw ← raw.filter(m -> ProtocolMapperUtils.isEnabled(session, m))
    raw ← dedup_by_id(raw)                                 # Set semantics

    pairs ← [ (m, factory(m)) for m in raw if factory(m) ≠ null ]
    pairs ← pairs.filter(surface_interface_test)
    if client.protocol == "openid-connect":
        pairs ← pairs ++ [DPoPUtil.transientMapper]
    return stableSort(pairs, key = factory.getPriority())
```

## See also

- `services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java:161-167` — `getProtocolMappersStream`.
- `services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java:310-326` — `loadProtocolMappers`.
- `services/src/main/java/org/keycloak/protocol/ProtocolMapperUtils.java:150-175` — sort + surface filter.
- `services/src/main/java/org/keycloak/protocol/oidc/utils/DPoPUtil.java` — transient DPoP mapper.
