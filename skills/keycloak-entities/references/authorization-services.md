# Authorization Services (UMA 2.0)

A separate sub-model only used if Authorization Services is enabled per client. Implements UMA 2.0 (User-Managed Access) — fine-grained, resource-based access control beyond simple role-mappings.

Entity classes live under `org/keycloak/authorization/jpa/entities/`.

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
| `resource_server` | `ResourceServerEntity` | id | client_id → client.id (unique) | One per UMA-enabled client |

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
| `scope_resource` | (no entity) | (scope_id, resource_id) | both | Reverse of above (used by some queries) |
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

`resource_scope` links them. `scope_resource` is the reverse mapping (for query convenience).

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

Aggregate policies reference children through `associated_policy`. The `decision_strategy` column on the parent controls how children combine:

| Strategy | Behavior |
|---|---|
| `UNANIMOUS` | All child policies must permit |
| `AFFIRMATIVE` | At least one child must permit |
| `CONSENSUS` | Majority must permit |

---

## Permission tickets

`resource_server_perm_ticket` is for UMA's "claim-pull" mechanism — a resource server issues a ticket saying "the user needs scope X on resource Y" and the user takes it to the authorization server to negotiate access.

**Schema**:
- `id` (UUID)
- `resource_server_id` (FK)
- `resource_id` (FK)
- `scope_id` (FK)
- `owner` (user ID — the resource owner)
- `requester` (user ID — who's asking)
- `granted_timestamp` (when permission granted)

Tickets are typically short-lived. UMA flow expects the requester to redeem them quickly.

---

## Common queries

```java
// All resources for a client
client.resources().getResourcesStream();   // authorization model API

// Find a resource by URI
client.resources().findByUri(uri);

// All policies on a resource
session.getProvider(AuthorizationProvider.class)
       .getStoreFactory()
       .getPolicyStore()
       .findByResource(resourceServer, resource);
```

---

## Gotchas

- **One `resource_server` per client max** — unique constraint on `client_id`. Enabling Authorization Services on a client creates the row.
- **Scopes are local to a resource server** — `resource_server_scope.resource_server_id` makes scopes scoped to one client. Two different resource servers can have a scope named "read" without collision.
- **Many-to-many tables don't have entity classes** — `resource_scope`, `resource_policy`, `scope_policy`, `associated_policy` are pure join tables managed via `@ElementCollection` or programmatic JPA.
- **Policy evaluation is expensive** — walks aggregate policies, multiple SQL lookups per request. Cache where possible.
- **Default Resource and Default Permission** auto-created when Authorization Services is enabled. Visible in admin UI.
- **Cascade on resource_server delete**: removes ALL Authorization Services data for the client (resources, scopes, policies, tickets). Heavy.

---

## Implementation reference

For implementing custom policy types, implement `org.keycloak.authorization.policy.provider.PolicyProvider` and register a `PolicyProviderFactory`. See `references/extension-patterns.md`.
