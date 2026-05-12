# Authorization Services (UMA 2.0)

A separate sub-model only used if Authorization Services is enabled per client. Implements UMA 2.0 (User-Managed Access) — fine-grained, resource-based access control beyond simple role-mappings.

Entity classes live in the upstream Keycloak repo: https://github.com/keycloak/keycloak/tree/26.5.5/model/jpa/src/main/java/org/keycloak/authorization/jpa/entities (remote URL — not a path in this working directory).

Version pinning: see `../SKILL.md`.

---

## Concepts

UMA 2.0 has 4 core concepts:
1. **Resource server** — the client offering protected resources
2. **Resources** — things being protected (URIs, IDs, etc.)
3. **Scopes** — actions on resources (e.g., "view", "edit", "delete")
4. **Policies** — who can do what

Resources have URIs and types. Scopes are actions. Policies say things like "alice can view" or "users with role admin can do anything."

---

## Tables

### Top-level

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `resource_server` | `ResourceServerEntity` | id (= client.id) | (no FK; the PK value IS the client's UUID) | One per UMA-enabled client |

**`resource_server.id == client.id`**: in authz-3.4.0.CR1 the schema was migrated so `RESOURCE_SERVER.ID` holds what used to be in `CLIENT_ID` — the original `ID` column was dropped and `CLIENT_ID` was renamed to `ID`. So `ResourceServerStore.findByClient(client)` is just `findById(client.getId())`. There is no separate `client_id` column anymore.

**Other columns**: `ALLOW_RS_REMOTE_MGMT BOOLEAN`, `POLICY_ENFORCE_MODE TINYINT` (was VARCHAR until 21.1.0), `DECISION_STRATEGY TINYINT` (added in authz-7.0.0, default 1 = `UNANIMOUS`).

### Resources

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `resource_server_resource` | `ResourceEntity` | id | resource_server_id → resource_server.id, owner | A protected resource |
| `resource_attribute` | `ResourceAttributeEntity` | id (simple) | resource_id → resource_server_resource.id | Resource attributes (multi-valued) |
| `resource_uris` | (no entity) | (resource_id, value) | resource_id → resource_server_resource.id | URIs of a resource |

### Scopes

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `resource_server_scope` | `ScopeEntity` | id | resource_server_id → resource_server.id | An action scope |

### Policies

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `resource_server_policy` | `PolicyEntity` | id | resource_server_id → resource_server.id | A policy definition |
| `policy_config` | (no entity) | (policy_id, name) | policy_id → resource_server_policy.id | Policy parameters (single-valued) |
| `associated_policy` | (no entity) | (policy_id, associated_policy_id) | both | Policy composition (aggregate policies) |

### Many-to-many bindings

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `resource_scope` | (no entity) | (resource_id, scope_id) | both | What scopes apply to a resource |
| `resource_policy` | (no entity) | (resource_id, policy_id) | both | Policies guarding a resource |
| `scope_policy` | (no entity) | (scope_id, policy_id) | both | Policies guarding a scope |

### Permission tickets

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `resource_server_perm_ticket` | `PermissionTicketEntity` | id | resource_server_id, resource_id, scope_id, owner, requester | UMA permission tickets (access requests) |

---

## Resource → scope binding

A resource can have multiple scopes:
```
resource: /api/users/123
  ├── scope: read
  ├── scope: write
  └── scope: delete
```

`resource_scope` is the only join table — there is no separate `scope_resource` reverse mapping; queries traverse the same table from either side.

---

## Policy types

`resource_server_policy.type` values:
- `role` — based on Keycloak realm/client roles
- `user` — specific users
- `client` — specific clients
- `group` — group membership
- `time` — time-based (only valid in a window)
- `js` — JavaScript expression (deprecated for security; disabled by default)
- `aggregate` — combines other policies via `associated_policy`
- `regex` — claim regex match
- `client-scope` — client scope membership

---

## Policy composition (aggregate policies)

Aggregate policies reference children through `associated_policy`. The `decision_strategy` column on the parent controls how children combine.

**Storage type at 26.5.5**: `resource_server_policy.decision_strategy` and `resource_server_policy.logic` are both `TINYINT` (since 21.1.0; previously `VARCHAR`). The numeric values come from the `DecisionStrategy` and `Logic` enums' `getStableIndex()`:

| Numeric | `DecisionStrategy` | Behavior |
|---|---|---|
| `0` | `AFFIRMATIVE` | At least one child must permit |
| `1` | `UNANIMOUS` | All child policies must permit |
| `2` | `CONSENSUS` | Majority must permit |

The `resource_server.decision_strategy` column (added authz-7.0.0) is the realm-default fallback used when a permission has no explicit decision strategy.

---

## Permission tickets

`resource_server_perm_ticket` is for UMA's "claim-pull" mechanism — a resource server issues a ticket saying "the user needs scope X on resource Y" and the user takes it to the authorization server to negotiate access.

**Schema**:
- `id` (UUID)
- `owner` (NOT NULL, user ID — the resource owner)
- `requester` (NOT NULL, user ID — who's asking)
- `resource_server_id` (NOT NULL, FK → `resource_server.id`)
- `resource_id` (NOT NULL, FK → `resource_server_resource.id`)
- `scope_id` (nullable, FK → `resource_server_scope.id`)
- `created_timestamp` (NOT NULL, BIGINT — when the ticket was issued)
- `granted_timestamp` (nullable, BIGINT — populated only when permission is granted)
- `policy_id` (nullable, FK → `resource_server_policy.id` — populated when granted; the policy that authorizes the request)

**Unique constraint** on `(owner, requester, resource_server_id, resource_id, scope_id)` — at most one ticket per (owner, requester, server, resource, scope). Re-requesting overwrites rather than duplicating.

Tickets are typically short-lived. UMA flow expects the requester to redeem them quickly.

---

## Common queries

Authorization data is reached through `AuthorizationProvider` and its `StoreFactory`. There is no `client.resources()` accessor on `ClientModel`.

```java
AuthorizationProvider authz = session.getProvider(AuthorizationProvider.class);
StoreFactory stores = authz.getStoreFactory();

// Resolve the ResourceServer for a client (one per client max)
ResourceServer rs = stores.getResourceServerStore().findByClient(client);

// All resources for that resource server
List<Resource> resources = stores.getResourceStore().findByResourceServer(rs);

// Find resources by URI (use the FilterOption map)
Map<Resource.FilterOption, String[]> filters = new HashMap<>();
filters.put(Resource.FilterOption.URI, new String[] { uri });
List<Resource> byUri = stores.getResourceStore().find(rs, filters, null, null);

// All policies on a resource
List<Policy> policies = stores.getPolicyStore().findByResource(rs, resource);
```

---

## Gotchas

- **One `resource_server` per client max** — guaranteed by the PK (since 3.4.0, `resource_server.id` is the client's UUID, so creating a second resource_server for the same client would PK-conflict). Enabling Authorization Services on a client creates the row with id = client.id.
- **Scopes are local to a resource server** — `resource_server_scope.resource_server_id` makes scopes scoped to one client. Two different resource servers can have a scope named "read" without collision.
- **Many-to-many tables don't have entity classes** — `resource_scope`, `resource_policy`, `scope_policy`, `associated_policy` are pure join tables managed via `@ElementCollection` or programmatic JPA.
- **Policy evaluation is expensive** — walks aggregate policies, multiple SQL lookups per request. Cache where possible.
- **Default Resource and Default Permission** auto-created when Authorization Services is enabled. Visible in admin UI.
- **Cascade on resource_server delete**: removes ALL Authorization Services data for the client (resources, scopes, policies, tickets). Heavy.

---

## Implementation reference

For implementing custom policy types, implement `org.keycloak.authorization.policy.provider.PolicyProvider` and register a `PolicyProviderFactory`. See `references/extension-patterns.md`.
