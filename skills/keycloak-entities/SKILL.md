---
name: keycloak-entities
description: Use for any work touching Keycloak's database — writing JPQL or SQL against Keycloak entities, designing migrations, building extensions, debugging FK/cascade issues, or mapping Keycloak's domain model to its schema. Covers the Keycloak schema, ER diagram, entity classes, and migrations across ~90 tables including USER_ENTITY, KEYCLOAK_ROLE, KEYCLOAK_GROUP, CLIENT, USER_ROLE_MAPPING, USER_GROUP_MEMBERSHIP, COMPOSITE_ROLE, CLIENT_SCOPE_CLIENT, PROTOCOL_MAPPER, FEDERATED_IDENTITY, COMPONENT, fed_user_*, RESOURCE_SERVER, OFFLINE_USER_SESSION. Knows JpaEntityProvider, JPQL named queries, Liquibase changelogs, databasechangelog, KeycloakModelUtils, FK cascade behavior, attribute tables, federated user tables, UMA Authorization Services, and Keycloak migration patterns. Verified against Keycloak 26.5.5.
license: MIT
compatibility: Requires Keycloak 26.5.x. Some claims are version-specific (KC 25+, KC 26.0+, KC 26.2+, KC 26.3+).
metadata:
  author: Tide Foundation
  version: 0.1.0
  keycloak-version: 26.5.5
---

# Keycloak Entities — Reference Skill

Expert reference for Keycloak's JPA data model. The skill is structured so this file alone covers most needs (~80% of questions); read the reference files for deep dives.

Verified against Keycloak 26.5.5.

---

## Source Code Layout

Entity classes live under `model/jpa/src/main/java/`:

| Path | What's there |
|---|---|
| `org/keycloak/models/jpa/entities/` | Core entities: realm, user, client, role, group, scopes, mappings |
| `org/keycloak/storage/jpa/entity/` | Federated user entities (`FederatedUser*`) |
| `org/keycloak/authorization/jpa/entities/` | Authorization Services (UMA) entities |
| `org/keycloak/events/jpa/` | Event/audit log entities |
| `org/keycloak/models/jpa/entities/MigrationModelEntity.java` | Schema migration tracker |
| `org/keycloak/models/jpa/entities/Organization*Entity.java` | Organizations (Keycloak 25+). Adapters and the provider live separately at `org/keycloak/organization/jpa/`. |

Schema migrations: `model/jpa/src/main/resources/META-INF/jpa-changelog-*.xml` (Liquibase). Entity classes show JPA mapping; changelogs are authoritative for DB-side constraints/indexes.

Many tables are list-collection mappings (no dedicated entity class) — they back `@ElementCollection` fields on parent entities.

---

## Mental Model

1. **Realm is the container.** Almost every realm-scoped table FKs to `realm.id`.
2. **Three entity families**:
   - **Identity**: users, groups, credentials, federated_identity
   - **Authorization**: roles, composite_roles, scopes, Authorization Services
   - **Applications**: clients, scopes, protocol mappers, IDPs, auth flows
3. **Relationship tables are composite-PK and DON'T carry realm.** Always JOIN through the parent.
4. **Attributes are universal extensibility.** Every major entity has a sibling attribute table.
5. **Federation parallels mirror standard tables** with `Fed*` prefix and no FKs.
6. **Sessions are mostly NOT in DB anymore** — Infinispan only in 26+.
7. **Customize behavior** via JPA `*Provider` and `*Adapter` extension. Customize schema via your own `JpaEntityProvider` + Liquibase.
8. **Querying**: prefer named queries on entity classes; otherwise JPQL via `EntityManager`.
9. **Cascades are aggressive**: deleting a parent often nukes a tree of children.
10. **JPA field names ≠ FK column names** — `e.user.id` not `e.userId`.

---

## Schema at a Glance

```
Realm core ─────┬─ realm + realm_attribute + realm_smtp_config
                └─ realm-level lists (events listeners, supported locales, default groups, localizations)

Users ──────────┬─ user_entity + user_attribute + user_required_action
                ├─ user_role_mapping (→ keycloak_role)
                ├─ user_group_membership (→ keycloak_group)
                ├─ user_consent + user_consent_client_scope
                └─ credential

Roles ──────────┬─ keycloak_role (realm OR client-scoped)
                ├─ role_attribute (multi-valued)
                └─ composite_role (self-join: parent → child)

Groups ─────────┬─ keycloak_group (hierarchical via parent_group)
                ├─ group_attribute (multi-valued)
                └─ group_role_mapping

Clients ────────┬─ client + client_attributes
                ├─ list-tables: redirect_uris, web_origins, client_node_registrations
                └─ client_initial_access, client_auth_flow_bindings

Client scopes ──┬─ client_scope + client_scope_attributes
                ├─ client_scope_client (binding to clients)
                ├─ client_scope_role_mapping (allow-list)
                └─ default_client_scope (realm-level defaults)

Protocol mappers ── protocol_mapper (client OR scope) + protocol_mapper_config

IDPs ───────────┬─ identity_provider + identity_provider_config
                ├─ identity_provider_mapper + idp_mapper_config
                └─ federated_identity (link to users)

Auth flows ─────┬─ authentication_flow + authentication_execution
                ├─ authenticator_config + authenticator_config_entry
                └─ required_action_provider + required_action_config

Components ────── component + component_config (KeyProviders, UserStorage, etc.)

Federated users ─ fed_user_attribute, fed_user_credential, fed_user_*_mapping (NO FKs)

Authz Services ── (separate sub-model — see references/authorization-services.md)

Events ─────────── event_entity + admin_event_entity (optional, append-only)

Sessions ───────── offline_user_session + offline_client_session + revoked_token

Organizations ──── org + org_domain (KC 25+); org_invitation (KC 26.5+)

System ─────────── migration_model + databasechangelog + databasechangeloglock
```

---

## Schema Patterns

Keycloak's data model uses 7 recurring patterns. Recognizing them speeds up reading the schema.

### Pattern 1: Realm-scoped entity
- Has `realm_id` column FK to `realm.id`
- Examples: `user_entity`, `client`, `keycloak_role`, `keycloak_group`, `client_scope`, `component`, `identity_provider`

### Pattern 2: Composite-PK relationship table
- Two FKs as composite PK
- **Doesn't carry `realm_id`** — must JOIN through parent for realm filtering
- Uses JPA `@IdClass` (each entity has a public static `Key` inner class)
- Examples: `user_role_mapping`, `user_group_membership`, `group_role_mapping`, `composite_role`, `client_scope_role_mapping`, `client_scope_client`

### Pattern 3a: Multi-valued attribute (simple-ID PK)
- One `(parent, name)` can have multiple value rows
- Examples: `user_attribute`, `group_attribute`, `role_attribute`, `resource_attribute`

### Pattern 3b: Single-valued attribute (composite PK)
- One value per `(parent, name)`
- Examples: `client_attributes`, `client_scope_attributes`, `realm_attribute`

### Pattern 4: ElementCollection list-table
- No dedicated entity class
- Backs a `Set<X>` field on a parent entity
- Examples: `redirect_uris`, `web_origins`, `realm_supported_locales`, `realm_default_groups`, `protocol_mapper_config`, `identity_provider_config`

### Pattern 5: Hierarchical via self-FK
- A `parent_*` column references the same table's `id`
- `keycloak_group.parent_group` (top = `' '` single space, NOT null)
- `component.parent_id`
- `authentication_execution.flow_id` → `authentication_flow.id` (the parent flow); when `authenticator_flow = true`, also `authentication_execution.auth_flow_id` → the invoked sub-flow

### Pattern 6: Federated mirror (no FK)
- Tables prefixed `fed_*` for users in external storage
- Each row carries `user_id + realm_id + storage_provider_id` (no FKs)
- Mirrors of: user_attribute, credential, consent, group_membership, role_mapping, required_action

### Pattern 7: Provider with config
- Main row in entity table + multi-row config table
- `identity_provider` + `identity_provider_config`
- `protocol_mapper` + `protocol_mapper_config`
- `authenticator_config` + `authenticator_config_entry`
- `component` + `component_config`

---

## Common Gotchas

### 1. Inconsistent `realm_id` widths
Most tables: `VARCHAR(36)`. Some (`keycloak_role`, `event_entity`): `VARCHAR(255)`. Check the changelog for manual SQL.

### 2. Top-level groups have `parent_group = ' '`, not NULL
`GroupEntity.TOP_PARENT_ID = " "` (single space). Top-level group queries must use `WHERE parent_group = ' '`. NULL won't match.

### 3. Composite roles compose to arbitrary depth
Granting one composite role grants all transitively-composed children. Always use:
```java
RoleUtils.expandCompositeRoles(roles)
RoleUtils.getDeepUserRoleMappings(user)
```

### 4. Realm vs client roles share `keycloak_role`
Boolean `client_role` distinguishes:
- Realm role: `client_role = false`, `realm_id` set, `client` null
- Client role: `client_role = true`, `client` set, `realm_id` set
- `client_realm_constraint` powers the unique-name-per-scope constraint

### 5. `protocol_mapper` has TWO possible parents
`client_id` set OR `client_scope_id` set, never both. To list all mappers for a token request: (mappers with client_id = X) UNION (mappers from each scope the client uses). The model API handles this.

### 6. Multi-valued vs single-valued attributes

| Table | Multi-valued? |
|---|---|
| `user_attribute`, `group_attribute`, `role_attribute`, `resource_attribute` | YES (multiple rows per name) |
| `client_attributes`, `client_scope_attributes`, `realm_attribute` | NO (one value per name) |

Setter behavior:
- Multi-valued: `setAttribute(name, List)` writes N rows; `setSingleAttribute(name, val)` deletes existing then writes 1
- Single-valued: `setAttribute(name, val)` does INSERT or UPDATE

### 7. Realm config lives in 2 places
Some realm settings are columns on `realm` (name, enabled, password_policy, ssl_required). Others are in `realm_attribute` rows. Model API `realm.getAttribute(name)` reads from the attribute table; column-backed settings have dedicated getters.

### 8. The `default-roles-<realm>` role
Every realm has an auto-generated composite role containing all realm-default + client-default roles. Granted to all users by default. Composite expansion delivers the defaults.

**The realm name is lowercased** in the role name: `Constants.DEFAULT_ROLES_ROLE_PREFIX + "-" + realm.getName().toLowerCase()`. So a realm `"MyRealm"` has role `default-roles-myrealm`, not `default-roles-MyRealm`. Querying by the raw realm name will miss.

### 9. Service-account users
When `client.service_accounts_enabled = true`, Keycloak creates a system user with `username = "service-account-<clientId>"` and `service_account_client_link = <client_id>`. They behave like regular users for role-mapping.

### 10. Sessions are NOT in the database (KC 22+, fully removed in 26.0)
`user_session`, `client_session`, etc. are now in **Infinispan**. Only `offline_user_session`, `offline_client_session`, `revoked_token` are persisted in DB.

### 11. `event_entity` and `admin_event_entity` are append-only
Optional — only populated if event listeners enabled. No FKs to other domain tables (events survive entity deletion for audit). Heavy realms produce huge volumes; configure retention.

### 12. JPA `@ManyToOne` field names ≠ FK column names
`UserAttributeEntity.user` (JPA field, type `UserEntity`) maps to `USER_ID` column. JPQL is `e.user.id` not `e.userId`. Common JPQL writer trap.

```java
// CORRECT
"SELECT e FROM UserAttributeEntity e WHERE e.user.id = :uid"

// WRONG — field 'userId' doesn't exist
"SELECT e FROM UserAttributeEntity e WHERE e.userId = :uid"
```

### 13. `LONG_VALUE` and the hash index columns on user/fed user attributes (KC 24+)
`user_attribute.value` is `VARCHAR(255)`. Longer values spill into `LONG_VALUE` (NCLOB, added 24.0.0). Querying just `VALUE` will miss long attribute values. Use the entity's `getValue()` getter or join with `LONG_VALUE`.

KC 24.0.0 also added two hash index columns to support indexed search of long values:
- `LONG_VALUE_HASH BINARY(64)` — SHA-256 of the long value, case-sensitive
- `LONG_VALUE_HASH_LOWER_CASE BINARY(64)` — SHA-256 of the lowercased long value, for case-insensitive search

Custom JPQL searching by long-value content should compute the hash on the input and match the appropriate hash column rather than full-scanning the NCLOB. The same three columns exist on `FED_USER_ATTRIBUTE`.

### 14. `fed_user_*` tables have no FKs
Federated users live outside Keycloak's `user_entity`. Tables denormalize with `user_id + realm_id + storage_provider_id` columns. No referential integrity to the external store.

### 15. Brute-force tracking is no longer in the database (KC 26.1+)
The `username_login_failure` table was **dropped in 26.1.0** (`<dropTable tableName="USERNAME_LOGIN_FAILURE"/>` in `jpa-changelog-26.1.0.xml`). Brute-force/login-failure state is now Infinispan-only — the same migration applied to live sessions in 26.0. The previous table was keyed by `(realm_id, username)` so tracking worked even before a matching user existed (defeating username enumeration); the in-memory replacement preserves that semantic but means raw SQL/JPQL can no longer read or mutate the state. Use `BruteForceProtector` (SPI) or the admin REST `/admin/realms/{realm}/attack-detection/brute-force/users/{user-id}` endpoints.

### 16. Composite PKs are `@IdClass`, not `@EmbeddedId`
Each composite-PK entity has a public static inner `Key` class:
```java
em.find(UserRoleMappingEntity.class, new UserRoleMappingEntity.Key(userId, roleId));
```

### 17. Relationship tables don't carry `realm_id`
`user_role_mapping`, `group_role_mapping`, `composite_role`, `client_scope_role_mapping`, `client_scope_client` — none have a direct realm column. Filter by JOIN through the parent:

```sql
SELECT urm.* FROM user_role_mapping urm
JOIN user_entity u ON urm.user_id = u.id
WHERE u.realm_id = ?
```

This is a top source of bugs.

### 18. `master` realm is special
The realm named `master` has admin authority over all other realms. Many extensions skip it:
```java
if ("master".equals(realm.getName())) return;
```

### 19. Not every entity has `@NamedQuery` annotations
`UserEntity`, `RoleEntity`, `GroupEntity`, `ClientEntity`, `CredentialEntity`, and `ClientScopeEntity` define named queries. **`ComponentEntity` and `IdentityProviderEntity` do not** — they have zero `@NamedQuery` declarations on the class. Calling `em.createNamedQuery("getComponents", ComponentEntity.class)` throws `IllegalArgumentException` at runtime.

For those entities, use the model API (`realm.getComponentsStream(...)`, `realm.getIdentityProvidersStream()`, etc.) or write inline JPQL / Criteria against the entity directly. See [references/entities.md](./references/entities.md) for the authoritative list of named queries per entity.

### 20. `keycloak_group.type` and `user_group_membership.membership_type` separate regular groups from organizations (KC 26.0+)
Since 26.0.0, two related columns were added to support organizations:

**`KEYCLOAK_GROUP.TYPE` (INT NOT NULL, default 0)** — values from `GroupModel.Type`:
- `0` = `REALM` — regular group
- `1` = `ORGANIZATION` — backs an organization (referenced from `org.group_id`)

**`USER_GROUP_MEMBERSHIP.MEMBERSHIP_TYPE` (VARCHAR)** — values from `org.keycloak.representations.idm.MembershipType`:
- `UNMANAGED` — member can exist without the group/org (default for regular groups)
- `MANAGED` — member cannot exist without the group/org (typical for org memberships)

A bare `SELECT ... FROM keycloak_group WHERE realm_id = ?` returns **both kinds** of groups, and org-backed memberships appear in `user_group_membership` alongside regular memberships. Naive queries silently include organizations.

Filter on `keycloak_group.type = 0` for regular groups, or use `JpaRealmProvider.getGroupsStream(realm)` which adds the type predicate automatically. The named queries `getGroupsByMember` / `getGroupsByFederatedMember` filter on `g.type = 1` to enumerate a user's organizations. For membership semantics, `MANAGED` rows imply the user lifecycle is tied to the parent org.

---

## Cascading Deletes

Keycloak relies on a mix of DB-level FK cascades AND application-level cleanup.

| Parent deleted | Cascades to (~main ones) |
|---|---|
| `realm` | Almost everything in the realm — heavy operation |
| `user_entity` | `user_attribute`, `user_role_mapping`, `user_group_membership`, `credential`, `user_required_action`, `user_consent`, `federated_identity` |
| `keycloak_role` | `user_role_mapping`, `group_role_mapping`, `composite_role` (both as parent and child), `role_attribute`, `client_scope_role_mapping`, `scope_mapping` |
| `keycloak_group` | `group_attribute`, `user_group_membership`, `group_role_mapping`, `keycloak_group` (children recursively), `realm_default_groups` |
| `client` | `client_attributes`, `client_scope_client`, `protocol_mapper` (where client_id matches), `keycloak_role` (client roles), `redirect_uris`, `web_origins`, `client_auth_flow_bindings`, `user_consent` + `user_consent_client_scope` (via `JpaUserProvider.preRemove`), Authorization Services data |
| `client_scope` | `client_scope_attributes`, `client_scope_client`, `client_scope_role_mapping`, `protocol_mapper` (where client_scope_id matches), `default_client_scope` |
| `component` | `component_config`, child `component` rows recursively |
| `authentication_flow` | `authentication_execution` (where `flow_id` matches — JPA cascade). **Removal blocked** by `KeycloakModelUtils.isFlowUsed` if any execution references this flow via `auth_flow_id` (i.e., it's invoked as a sub-flow elsewhere) — operation throws `ModelException("Cannot remove authentication flow, it is currently in use")` rather than cascading. |
| `identity_provider` | `identity_provider_config` (JPA `@ElementCollection`), `identity_provider_mapper` + `idp_mapper_config` (provider-level via `getMappersByAliasStream`). **Not cascaded**: `federated_identity` rows referencing this IDP — its `IDENTITY_PROVIDER` column is a plain `VARCHAR(255)` alias with no FK constraint, so the rows persist (intentionally — re-creating an IDP with the same alias resumes linkage). |
| `resource_server` | All Authorization Services data (resources, scopes, policies, perm tickets) |

**Implication for extensions**: if you intercept delete on a parent and want to defer it for approval workflow, you must also block the cascade. Either intercept at the REST layer (return 409 before model.removeX runs), or throw an exception in your provider's removeX override (causes transaction rollback).

Audit log preservation: `event_entity` and `admin_event_entity` deliberately have NO FK to domain tables — events survive entity deletion. Intentional for compliance.

---

## Common Tables Cheat Sheet

| If you need... | Look at... |
|---|---|
| Users in a realm | `user_entity` WHERE `realm_id = ?` |
| User's roles | `user_role_mapping` JOIN `keycloak_role` (or `RoleUtils.getDeepUserRoleMappings`) |
| User's groups | `user_group_membership` JOIN `keycloak_group` |
| User's attributes | `user_attribute` (multi-valued; check `LONG_VALUE` for >255 char values) |
| User's credentials | `credential` (typed by `type` column: password, otp, webauthn) |
| User's consents | `user_consent` + `user_consent_client_scope` |
| User's pending actions | `user_required_action` |
| User's IDP links | `federated_identity` |
| Federated user data | `fed_user_*` (no FK; key on user_id + realm_id + storage_provider_id) |
| Members of a group | `user_group_membership` WHERE `group_id = ?` |
| Group's roles | `group_role_mapping` |
| Group hierarchy | `keycloak_group.parent_group` (top = `' '`, NOT NULL) |
| Realm-level config | `realm` columns + `realm_attribute` rows |
| Brute-force state | Not in DB since KC 26.1 (Infinispan-only). Use `BruteForceProtector` SPI or admin REST `/attack-detection/brute-force/users/{id}`. |
| Clients in realm | `client` WHERE `realm_id = ?` |
| Client's protocol mappers | `protocol_mapper` WHERE `client_id = ?` UNION mappers from default scopes |
| Client's redirect URIs | `redirect_uris` |
| Client's default scopes | `client_scope_client` WHERE `client_id = ? AND default_scope = true` |
| Service-account user | `user_entity` WHERE `service_account_client_link = ?` |
| Realm role by name | `keycloak_role` WHERE `realm_id = ? AND client_role = false AND name = ?` |
| Client role by name | `keycloak_role` WHERE `client = ? AND client_role = true AND name = ?` |
| Composite role children | `composite_role` WHERE `composite = ?` |
| Composite role parents | `composite_role` WHERE `child_role = ?` |
| Identity providers | `identity_provider` + `identity_provider_config` |
| Auth flows | `authentication_flow` + `authentication_execution` (hierarchical via `flow_id`; sub-flow link via `auth_flow_id` when `authenticator_flow = true`) |
| User storage providers (LDAP) | `component` WHERE `provider_type = 'org.keycloak.storage.UserStorageProvider'` + `component_config` |
| Realm key providers | `component` WHERE `provider_type = 'org.keycloak.keys.KeyProvider'` |
| Authorization Services | See `references/authorization-services.md` |
| Login events | `event_entity` (only if enabled) |
| Admin actions audit | `admin_event_entity` (only if enabled) |
| Persistent sessions | `offline_user_session`, `offline_client_session` |
| Schema version | `migration_model` |
| Organizations | `org`, `org_domain`, `org_invitation` |

---

## Common JPQL Patterns

### Get the EntityManager
```java
EntityManager em = session.getProvider(JpaConnectionProvider.class).getEntityManager();
```

### Prefer named queries when one exists
Many entities define them with `@NamedQueries(...)`, but **not all do**. Verify the name in the entity class before using it. Real names at 26.5.5:

- `UserEntity`: `getRealmUserByUsername`, `getRealmUserByEmail`, `getRealmUserByLastName`, `getRealmUserByFirstLastName`, `getRealmUserByServiceAccount`, `getRealmUsersByAttributeNameAndValue`, `getRealmUsersByAttributeNameAndLongValue`, `deleteUsersByRealm`, `deleteUsersByRealmAndLink`, `unlinkUsers`
- `RoleEntity`: `getRealmRoleByName`, `getRealmRoleIdByName`, `getClientRoleByName`, `getClientRoleIdByName`, `getRealmRoles`, `getClientRoles`, `getRealmRoleIds`, `getClientRoleIds`, `getRoleIdsFromIdList`, `getRoleIdsByNameContainingFromIdList`, `getChildRoles`, `searchForRealmRoles`, `searchForClientRoles`
- `GroupEntity`: `getGroupIdsByParent`, `deleteGroupsByRealm` (no `getTopLevelGroups` query — use `JpaRealmProvider.getTopLevelGroupsStream` or filter on `parentId = ' '`)
- `ClientEntity`: `getClientById`, `findClientByClientId`, `findClientIdByClientId`, `getAllRedirectUrisOfEnabledClients`, `getAlwaysDisplayInConsoleClients`
- `CredentialEntity`: `credentialByUser`, `deleteCredentialsByRealm`, `deleteCredentialsByRealmAndLink`
- `ComponentEntity`: **none** — no `@NamedQuery` on the entity. Use `KeycloakSession.realms().getProvider(JpaRealmProvider.class)` methods or write inline JPQL / Criteria.
- `IdentityProviderEntity`: **none** — same. Use the provider API.

If you remember a name from training data and it isn't in the entity class, it doesn't exist. Don't `em.createNamedQuery(...)` blind.

### Filtering relationship tables by realm (JOIN through parent)
`UserRoleMappingEntity` does NOT have a `RoleEntity` reference — its role link is the plain string column `roleId`. And `UserEntity` has no `roleMappings` collection (its `@OneToMany` collections are only `attributes`, `requiredActions`, `credentials`, `federatedIdentities`). Query through the relationship entity directly:

```java
// Users with role X in realm Y
"SELECT urm.user FROM UserRoleMappingEntity urm " +
"WHERE urm.user.realmId = :rid AND urm.roleId = :roleId"
```

### Composite role expansion
Don't write recursive JPQL. Use `RoleUtils.getDeepUserRoleMappings(user)`.

### Composite role children/parents
```java
"SELECT cr FROM CompositeRoleEntity cr WHERE cr.parentRole = :role"   // children (NOTE: JPA field is 'parentRole', column is 'COMPOSITE' — gotcha #12)
"SELECT cr FROM CompositeRoleEntity cr WHERE cr.childRole = :role"   // parents
```

### Avoid `EntityManager.persist()` for top-level entities
```java
// Don't:
em.persist(new UserEntity(...));

// Do:
session.users().addUser(realm, username);
```

The model API handles ID generation, default attributes, default-roles assignment, event firing, and provider chain dispatch.

### `runJobInTransaction` for separate transactions
```java
KeycloakModelUtils.runJobInTransaction(sessionFactory, newSession -> {
    EntityManager newEm = newSession.getProvider(JpaConnectionProvider.class).getEntityManager();
    // runs in a fresh KeycloakSession + new JTA transaction
    // commits independently of the calling one
});
```

---

## Auto-Routing — read references PROACTIVELY without being asked

When the user's question matches a trigger below, **read the corresponding reference file before answering**. Don't ask permission; the references exist to be consulted. SKILL.md alone is correct for ~80% of questions, but for the cases below the reference has the authoritative info.

### Read `references/entities.md` when ANY of:

- User asks about a **specific table** not in the schema diagram above (e.g., `realm_smtp_config`, `client_node_registrations`, `idp_mapper_config`, `authenticator_config_entry`)
- User asks for the **full column list** of an entity
- User asks about a **specific named query** by name (e.g., "what does `getRealmUserByServiceAccount` do?")
- User mentions a specific entity by **Java class name** (`UserEntity`, `RoleEntity`, `ClientEntity`, `FederatedUserAttributeEntity`, etc.) and wants details
- User asks "**what's in column X**?" or "**what does table Y store**?"
- User is writing **JPQL or SQL with specific column names** and needs to verify the schema
- User asks about **organizations** (`org`, `org_domain`, `org_invitation`) — KC 25+ feature only briefly mentioned in SKILL.md
- User asks about **events** (`event_entity`, `admin_event_entity`) details
- User asks about **components / SPI plugin storage** (`component`, `component_config`)
- User asks about **federated users** (`fed_user_*` tables) details

### Read `references/authorization-services.md` when ANY of:

- User mentions **UMA**, **Authorization Services**, **fine-grained permissions**, or **policy-based access**
- User mentions any of: **resource_server**, **resource_server_resource**, **resource_server_scope**, **resource_server_policy**, **resource_server_perm_ticket**, **policy_config**, **associated_policy**
- User talks about **resources** + **scopes** in the authorization sense (not "client scopes" which are different)
- User mentions **permission tickets** or **claim-pull** flows
- User is **enabling Authorization Services on a client** or asks about the client's `authorization_services_enabled` flag
- User asks about **custom policy types** or **PolicyProvider** SPI

### Read `references/extension-patterns.md` when ANY of:

- User wants to **build / write / extend** anything in Keycloak (custom user storage, mapper, provider, listener, REST endpoint)
- User mentions **JpaEntityProvider**, **UserStorageProviderFactory**, **EventListenerProviderFactory**, **CredentialProviderFactory**, **ProtocolMapper** SPI, **AdminRealmResourceProvider**
- User wants to **add new tables or columns** via Liquibase
- User wants to **intercept writes** (override `addUser`, `grantRole`, `joinGroup`, etc.)
- User asks about **wrapping models** / writing custom **adapters** (extending `UserAdapter`, `RoleAdapter`, etc.)
- User asks about **transaction handling**, especially `runJobInTransaction` or "how do I write something that survives a rollback"
- User asks about **Liquibase changelogs** — writing them, idempotency, preconditions, stale lock recovery
- User says "**how do I add X to Keycloak**" where X is a custom feature
- User mentions **`@Vetoed`** or Quarkus CDI conflicts in JAX-RS resources

### Combined triggers

If a question matches multiple categories, read all relevant references. Examples:
- "I want to build a custom UMA policy type" → both `extension-patterns.md` AND `authorization-services.md`
- "Show me the full schema of `event_entity` and how to write a custom event listener" → both `entities.md` AND `extension-patterns.md`

### When SKILL.md alone is sufficient

Don't read references for these — SKILL.md has them:
- The 18 gotchas listed above
- The 7 schema patterns
- High-level mental model and category overview
- Common JPQL traps (field-name vs column-name)
- The cheat sheet of "if I need X, look at table Y"
- The cascade overview (`Cascading Deletes` section)
- The 10 short JPQL examples in `Common JPQL Patterns`

If the question is about any of the above, answer directly from SKILL.md.
