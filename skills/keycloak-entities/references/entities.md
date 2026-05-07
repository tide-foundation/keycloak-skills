# Keycloak Entity Catalog

Comprehensive table reference for all categories. Authorization Services (UMA) lives in `references/authorization-services.md`.

Version pinning: see `../SKILL.md`.

---

## 1. Realm core

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `realm` | `RealmEntity` | id | master_admin_client → client.id | The realm itself; columns hold most realm config (name, theme, password policy, token lifetimes, etc.) |
| `realm_attribute` | `RealmAttributeEntity` | (name, realm_id) | realm_id → realm.id | Custom realm attributes (single-valued extensibility) |
| `realm_smtp_config` | (no entity) | (realm_id, name) | realm_id → realm.id | SMTP server configuration |
| `realm_required_credential` | `RequiredCredentialEntity` | (realm_id, type) | realm_id → realm.id | Required credential types (password, OTP) |
| `realm_events_listeners` | (no entity) | (realm_id, value) | realm_id → realm.id | Enabled event listener IDs |
| `realm_enabled_event_types` | (no entity) | (realm_id, value) | realm_id → realm.id | Event types to record |
| `realm_supported_locales` | (no entity) | (realm_id, value) | realm_id → realm.id | Supported UI locales |
| `realm_default_groups` | (no entity) | (realm_id, group_id) | realm_id → realm.id, group_id → keycloak_group.id | Groups joined automatically by new users |
| `realm_localizations` | `RealmLocalizationTextsEntity` | (realm_id, locale) | realm_id → realm.id | One row per (realm, locale); the `texts` column is a `CLOB` holding a JSON-serialized `Map<String,String>` of all keys for that locale. There is no per-key column. |

**Key behavior**: Realm config lives in 2 places — columns on `realm` (`name`, `enabled`, `password_policy`, `ssl_required`, etc.) AND `realm_attribute` rows (theme overrides, custom feature toggles). The model API `realm.getAttribute(name)` reads from the attribute table.

**Master realm** is special — has admin authority over all other realms. Many extensions skip it: `if ("master".equals(realm.getName())) return;`

**Realm deletion is heavy** — cascades to nearly everything (users, clients, roles, groups, scopes, components, sessions, events).

---

## 2. Users

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `user_entity` | `UserEntity` | id | realm_id → realm.id | A user account |
| `user_attribute` | `UserAttributeEntity` | id (simple) | user_id → user_entity.id | Custom user attributes (multi-valued) |
| `user_required_action` | `UserRequiredActionEntity` | (required_action, user_id) | user_id → user_entity.id | Pending required actions. The original `ACTION` column was dropped in KC 1.3.0 and replaced by `REQUIRED_ACTION VARCHAR(255)`. |
| `user_role_mapping` | `UserRoleMappingEntity` | (role_id, user_id) | user_id → user_entity.id, role_id → keycloak_role.id | User → role assignments |
| `user_group_membership` | `UserGroupMembershipEntity` | (group_id, user_id) | user_id → user_entity.id, group_id → keycloak_group.id | User → group memberships. `membership_type` column (KC 26+) is not part of the PK; see gotcha #20 in SKILL.md. |
| `user_consent` | `UserConsentEntity` | id | user_id → user_entity.id, client_id → client.id | OAuth2 consent grants |
| `user_consent_client_scope` | `UserConsentClientScopeEntity` | (user_consent_id, scope_id) | both | Scopes granted in a consent |
| ~~`username_login_failure`~~ | — | — | — | **Removed in KC 26.1.0**. Brute-force state is now Infinispan-only; use `BruteForceProtector` SPI or admin REST `/attack-detection/brute-force/users/{id}`. |

**`user_entity` key columns**: `id`, `realm_id`, `username`, `email`, `email_verified`, `email_constraint` (dynamic unique-email handle), `enabled`, `created_timestamp`, `federation_link` (FK to component when federated), `service_account_client_link` (FK to client when this user is a service account), `not_before` (token revocation timestamp).

**`user_attribute` is multi-valued** — same `(user_id, name)` can have multiple rows.

**LONG_VALUE quirk**: short values ≤255 chars go in `VALUE`; longer values spill into `LONG_VALUE` (CLOB). Querying just `VALUE` misses long attribute values. Use entity's `getValue()` getter.

**Service accounts**: when `client.service_accounts_enabled = true`, Keycloak creates `user_entity` row with `username = "service-account-<clientId>"` and `service_account_client_link = <client_id>`. Real users with normal role mappings.

**Brute-force tracking moved to Infinispan in KC 26.1**: the old `username_login_failure` table (PK `(realm_id, username)`) was dropped in `jpa-changelog-26.1.0.xml`. The username-keyed semantic is preserved in memory so tracking still works before a matching user exists, but raw SQL/JPQL can no longer read or mutate the state — use the `BruteForceProtector` SPI.

---

## 3. Credentials

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `credential` | `CredentialEntity` | id | user_id → user_entity.id | All credential types: password, OTP, WebAuthn, recovery codes |

**Schema**: `id`, `user_id`, `type` (`password`, `otp`, `totp`, `webauthn`, `recovery-authn-codes`), `created_date`, `user_label`, `secret_data` (JSON, hashed), `credential_data` (JSON, type-specific config), `priority` (ordering for multiple credentials of same type), `version` (KC 26.2+, INT, `@Version` optimistic-lock counter incremented on every update — `OptimisticLockException` on stale write).

**Type-specific JSON** in `secret_data` / `credential_data`:
- Password: `secret_data` = `{value, salt}`; `credential_data` = `{algorithm, hashIterations}`
- OTP/TOTP: `secret_data` = `{value}`; `credential_data` = `{subType, digits, counter, period, algorithm}`
- WebAuthn: `secret_data` = `{credentialId, attestationStatement, credentialPublicKey}`; `credential_data` = `{aaguid, counter, userVerification}`

**Never read/write `credential` directly for password operations** — use `user.credentialManager()`. Direct inserts skip realm password policy validation, hash algorithm selection, and audit events.

**Multiple credentials per type allowed** — one user can have multiple OTP devices, multiple WebAuthn keys. `priority` controls which is default.

---

## 4. Roles

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `keycloak_role` | `RoleEntity` | id | client → client.id (nullable) | Realm-scoped or client-scoped role |
| `role_attribute` | `RoleAttributeEntity` | id (simple) | role_id → keycloak_role.id | Custom role attributes (multi-valued) |
| `composite_role` | `CompositeRoleEntity` | (composite, child_role) | both → keycloak_role.id | Self-join: parent role includes child role |

**Realm vs client roles share `keycloak_role`.** Boolean `client_role` discriminates:
- Realm role: `client_role = false`, `realm_id` set, `client` null
- Client role: `client_role = true`, `client` set, `realm_id` set
- `client_realm_constraint` = realm_id (realm role) or client_id (client role) — powers `UNIQUE (NAME, CLIENT_REALM_CONSTRAINT)` for unique-name-per-scope

**`keycloak_role.realm_id` is `VARCHAR(255)`** while most realm_id columns are `VARCHAR(36)`. Inconsistency.

**Composite roles** form a directed graph via `composite_role` self-join. Granting one composite grants all transitively-composed children. Always use `RoleUtils.expandCompositeRoles(...)` and `RoleUtils.getDeepUserRoleMappings(user)` instead of writing recursive JPQL.

**`default-roles-<realm>` role**: every realm has an auto-generated composite role with this name. Contains all realm-default + client-default roles via `composite_role` children. Granted to all users by default.

**Composite-membership cleanup on role delete**: the model API (`session.roles().removeRole(role)`) calls the `deleteRoleFromComposites` named query first, which removes the role from `composite_role` as both `parentRole` AND `childRole` before the JPA delete. Raw SQL `DELETE FROM keycloak_role` will FK-violate against `composite_role` — clean it manually first or stick to the provider API.

Common JPQL:
```java
// Children of a role (NOTE: JPA field is 'parentRole', column is 'COMPOSITE' — gotcha #12)
"SELECT cr FROM CompositeRoleEntity cr WHERE cr.parentRole = :role"
// Parents of a role
"SELECT cr FROM CompositeRoleEntity cr WHERE cr.childRole = :role"
// Realm roles
"SELECT r FROM RoleEntity r WHERE r.realmId = :rid AND r.clientRole = false"
// Client roles for client C
"SELECT r FROM RoleEntity r WHERE r.clientId = :cid AND r.clientRole = true"
```

---

## 5. Groups

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `keycloak_group` | `GroupEntity` | id | realm_id → realm.id, parent_group → keycloak_group.id (self-FK) | Hierarchical groups |
| `group_attribute` | `GroupAttributeEntity` | id (simple) | group_id → keycloak_group.id | Custom group attributes (multi-valued) |
| `group_role_mapping` | `GroupRoleMappingEntity` | (role_id, group_id) | both | Group → role assignments (members inherit) |

**Top-level groups**: `parent_group = ' '` (single space). `GroupEntity.TOP_PARENT_ID = " "`. Queries for top-level groups need `WHERE parent_group = ' '` — NULL won't match.

**Path** is computed (e.g., `/HR/Recruitment/Senior`) — not stored.

**Unique constraint** `(realm_id, parent_group, name)` — same name allowed in different parents.

**Members inherit roles** through `group_role_mapping` recursively up the hierarchy. Use `user.getGroupsStream().flatMap(g -> g.getRoleMappingsStream())` for effective roles via groups.

**`TYPE` column (KC 26.0+)**: distinguishes regular groups from organization-backing groups.

| `TYPE` value | `GroupModel.Type` | Meaning |
|---|---|---|
| `0` | `REALM` | Regular group |
| `1` | `ORGANIZATION` | Backs an organization (referenced from `org.group_id`) |

A naive query like `SELECT * FROM keycloak_group WHERE realm_id = ?` returns **both kinds**. Org-groups also appear in `user_group_membership` for org members. Filter on `TYPE = 0` for "real" groups, or use `JpaRealmProvider.getGroupsStream` which only returns `TYPE = 0`. The named queries `getGroupsByMember` and `getGroupsByFederatedMember` filter on `g.type = 1` to find a user's organizations.

**`DESCRIPTION` column (KC 26.3+)**: `NVARCHAR(255)`, nullable. Free-text group description.

---

## 6. Clients

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `client` | `ClientEntity` | id | realm_id → realm.id | OAuth2/OIDC/SAML client app |
| `client_attributes` | `ClientAttributeEntity` | (client_id, name) | client_id → client.id | Custom client attributes (single-valued) |
| `redirect_uris` | (no entity) | (client_id, value) | client_id → client.id | Allowed redirect URIs |
| `web_origins` | (no entity) | (client_id, value) | client_id → client.id | CORS-allowed origins |
| `client_node_registrations` | (no entity) | (client_id, name) | client_id → client.id | Cluster nodes registered for the client |
| `client_initial_access` | `ClientInitialAccessEntity` | id | realm_id → realm.id | One-time tokens for dynamic client registration |
| `client_auth_flow_bindings` | (no entity) | (client_id, binding_name) | client_id → client.id | Per-client overrides of auth flows |
| `scope_mapping` | (no entity) | (client_id, role_id) | client_id → client.id, role_id → keycloak_role.id | Per-client role allow-list ("Scope Mappings" tab in admin UI). Distinct from `client_scope_role_mapping` (which scopes roles to a client-scope) and `client_scope_client` (which binds client-scopes to a client). |

**Two IDs**: `id` = internal UUID (PK, used in FKs), `client_id` = public OAuth2 identifier (what admins know, e.g., `account-console`). Unique on `(realm_id, client_id)`.

**Many flag columns**: `enabled`, `public_client`, `bearer_only`, `consent_required`, `standard_flow_enabled`, `implicit_flow_enabled`, `direct_access_grants_enabled`, `service_accounts_enabled`, `frontchannel_logout`, `full_scope_allowed`, `surrogate_auth_required`.

**`full_scope_allowed = true`** means scope-mapping is bypassed entirely — client gets all the user's roles. Common security footgun.

**`client_initial_access` tokens are one-shot** — each row has `count` and `remaining_count`. When `remaining_count = 0`, dead but row stays.

---

## 7. Client scopes

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `client_scope` | `ClientScopeEntity` | id | realm_id → realm.id | Reusable scope (profile, email, custom) |
| `client_scope_attributes` | `ClientScopeAttributeEntity` | (scope_id, name) | scope_id → client_scope.id | Scope attributes |
| `client_scope_client` | `ClientScopeClientMappingEntity` | (client_id, scope_id) | both | Scope assigned to client. Discriminator column `default_scope BOOLEAN` distinguishes default vs optional. |
| `client_scope_role_mapping` | `ClientScopeRoleMappingEntity` | (scope_id, role_id) | both | Scope's role allow-list |
| `default_client_scope` | `DefaultClientScopeRealmMappingEntity` | (realm_id, scope_id) | both | Realm-level default/optional scopes (apply to new clients). Discriminator `default_scope BOOLEAN` distinguishes default vs optional. |

**Default vs Optional**: `default_scope` boolean controls whether scope is auto-included or only when requested via `scope=` param.

**Built-in scopes** auto-created with realm: `profile`, `email`, `address`, `phone`, `roles`, `web-origins`, `microprofile-jwt`, `offline_access`.

**Effective tokens** combine: client's own role mappings + default scopes + requested optional scopes. `client_scope_role_mapping` is the role allow-list within a scope.

**Realm default `default_client_scope`** applies to NEW clients only. Existing clients aren't auto-migrated when realm defaults change.

---

## 8. Protocol mappers

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `protocol_mapper` | `ProtocolMapperEntity` | id | client_id → client.id (nullable), client_scope_id → client_scope.id (nullable) | Token claim mapper |
| `protocol_mapper_config` | (no entity) | (protocol_mapper_id, name) | protocol_mapper_id → protocol_mapper.id | Per-mapper config |

**Two possible parents — never both**: each mapper has either `client_id` or `client_scope_id` set. Listing all mappers for a token = (mappers on client) UNION (mappers on each requested scope).

**JPQL field names** (note `@ManyToOne` mapping):
```java
"SELECT pm FROM ProtocolMapperEntity pm WHERE pm.client.id = :cid"      // pm.client.id NOT pm.clientId
"SELECT pm FROM ProtocolMapperEntity pm WHERE pm.clientScope.id = :sid"
```

**Common mapper types** (`protocol_mapper_name`):
- `oidc-usermodel-property-mapper` — user property → claim
- `oidc-usermodel-attribute-mapper` — user attribute → claim
- `oidc-group-membership-mapper`
- `oidc-role-name-mapper`
- `oidc-hardcoded-claim-mapper`
- `oidc-hardcoded-role-mapper`
- `oidc-audience-mapper`
- `oidc-allowed-origins-mapper`

**Common config keys** (`protocol_mapper_config`):
- `claim.name` — JSON path in token (e.g. `realm_access.roles`)
- `id.token.claim`, `access.token.claim`, `userinfo.token.claim` — `true`/`false`
- `multivalued` — for arrays
- `jsonType.label` — data type

---

## 9. Identity providers

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `identity_provider` | `IdentityProviderEntity` | internal_id | realm_id → realm.id | External IDP (OIDC/SAML/social) |
| `identity_provider_config` | (no entity) | (identity_provider_id, name) | identity_provider_id → identity_provider.internal_id | IDP config (URLs, secrets) |
| `identity_provider_mapper` | `IdentityProviderMapperEntity` | id | realm_id → realm.id | Maps IDP claims to Keycloak attributes/roles |
| `idp_mapper_config` | (no entity) | (idp_mapper_id, name) | idp_mapper_id → identity_provider_mapper.id | Mapper config |
| `federated_identity` | `FederatedIdentityEntity` | (identity_provider, user_id) | user_id → user_entity.id, realm_id → realm.id | Link between local user and external IDP user |

**Lookup by `provider_alias`, NOT `internal_id`**: humans configure aliases (`google`, `okta`); internal_id is opaque.

**`provider_id` vs `internal_id`**: `provider_id` is the implementation type (`oidc`, `saml`, `google`); `internal_id` is the row's UUID.

**KC 26.0+ columns**:
- `HIDE_ON_LOGIN` (BOOLEAN, default false) — when true, the IdP is configured but does not render on the login screen. Replaces the older `HIDE_ON_LOGIN_PAGE` config-key approach.
- `ORGANIZATION_ID` (VARCHAR(255)) — when set, scopes the IdP to a specific organization (multi-tenancy). Indexed via `IDX_IDP_REALM_ORG`. NULL means realm-wide.

**`federated_identity` is unidirectional**: local user → external user. Reverse lookup uses `getUserByFederatedIdentity()`.

**`identity_provider` columns**: `provider_alias`, `provider_id`, `enabled`, `trust_email`, `store_token`, `add_token_role`, `authenticate_by_default`, `link_only`, `first_broker_login_flow_id`, `post_broker_login_flow_id`.

---

## 10. Authentication

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `authentication_flow` | `AuthenticationFlowEntity` | id | realm_id → realm.id | A flow (browser, direct grant, etc.) |
| `authentication_execution` | `AuthenticationExecutionEntity` | id | flow_id → authentication_flow.id (the parent flow), auth_flow_id → authentication_flow.id (sub-flow this execution invokes when `authenticator_flow = true`), realm_id → realm.id | Step in a flow (hierarchical) |
| `authenticator_config` | `AuthenticatorConfigEntity` | id | realm_id → realm.id | Reusable authenticator config |
| `authenticator_config_entry` | (no entity) | (authenticator_id, name) | authenticator_id → authenticator_config.id | Config entries |
| `required_action_provider` | `RequiredActionProviderEntity` | id | realm_id → realm.id | Required action definition |
| `required_action_config` | (no entity) | (required_action_id, name) | required_action_id → required_action_provider.id | Per-action config |

**Flow structure**: a flow is a tree of executions. Each execution is either an authenticator OR a sub-flow.

- `authentication_execution.flow_id` — the flow this execution belongs to (always set; the immediate parent in the tree).
- `authentication_execution.auth_flow_id` — set when `authenticator_flow = true`. Points to the `authentication_flow` row this execution invokes as a sub-flow. The sub-flow itself has its own executions whose `flow_id` references it.

There is **no `parent_flow` column**. Older skill writeups sometimes claim one; the actual hierarchy is two columns: `flow_id` (which flow am I in?) and `auth_flow_id` (which flow do I invoke, if any?).

**Execution requirements**: `REQUIRED`, `ALTERNATIVE`, `OPTIONAL`, `DISABLED`, `CONDITIONAL`.

**Realm has FK columns for default flows** (column names exact, all on the `realm` table): `browser_flow`, `registration_flow`, `direct_grant_flow`, `reset_credentials_flow`, `client_auth_flow`, `docker_auth_flow`. Note the abbreviations (`*_AUTH_FLOW`, not `*_AUTHENTICATION_FLOW`). Per-client overrides go in `client_auth_flow_bindings`.

**First-broker-login and post-broker-login flows are per-IDP, not per-realm**: `identity_provider.first_broker_login_flow_id` and `identity_provider.post_broker_login_flow_id` (NOT columns on `realm`). See section 9.

**Required actions** are per-realm definitions. `user_required_action` (on a user) references action by name. Auto-prompted at login when realm has the action `default_action = true` OR user has a row in `user_required_action`.

---

## 11. Components

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `component` | `ComponentEntity` | id | realm_id → realm.id, parent_id → component.id (self-FK) | SPI plugin instance |
| `component_config` | `ComponentConfigEntity` | id | component_id → component.id | Multi-valued component config |

**Generic SPI plugin storage**. Used for KeyProviders, UserStorageProviders (LDAP etc.), UserProfileProvider, OrganizationProvider (KC 25+), and more.

**`provider_type`** is the FQN of the SPI interface:
- `org.keycloak.keys.KeyProvider` — realm signing keys
- `org.keycloak.storage.UserStorageProvider` — external user federation
- `org.keycloak.storage.client.ClientStorageProvider`
- `org.keycloak.userprofile.UserProfileProvider`
- `org.keycloak.organization.OrganizationProvider`

**`provider_id`** is the implementation within a type:
- KeyProvider: `rsa-generated`, `aes-generated`, `hmac-generated`, `ecdsa-generated`
- UserStorageProvider: `ldap`, `kerberos`, custom

**Hierarchy via `parent_id`**: top-level components have `parent_id = realm.id`. LDAP example:
```
component (LDAP, parent_id = realm.id)
├── component (LDAP user attribute mapper, parent_id = ldap.id)
├── component (LDAP group mapper)
└── component (LDAP role mapper)
```

**Config is multi-valued**: same `name` can have multiple rows in `component_config`. Use `MultivaluedHashMap` via `ComponentModel.getConfig()`.

**`ComponentEntity` doesn't expose config map**: use `RealmModel.getComponentsStream(...)` and `ComponentModel.getConfig()` — the model layer joins.

**`component_config.value` is `NCLOB` since KC 23.0.0** (was `VARCHAR(255)` before). The 23.0.0 changeset added a transient `VALUE_NEW NCLOB`, copied data into it, dropped the old `VALUE`, then renamed `VALUE_NEW` back to `VALUE`. So at 26.5.5 there is **no `VALUE_NEW` column** — `VALUE` itself is `NCLOB` and holds values of any length.

---

## 12. Federated users

When users come from external storage their per-user data is in `fed_*` tables with **no FKs to `user_entity`**:

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `fed_user_attribute` | `FederatedUserAttributeEntity` | id (simple) | (no FKs) | Federated user attributes |
| `fed_user_credential` | `FederatedUserCredentialEntity` | id | (no FKs) | Federated user credentials |
| `fed_user_consent` | `FederatedUserConsentEntity` | id | (no FKs; realm_id is a varchar column) | OAuth2 consents |
| `fed_user_consent_cl_scope` | `FederatedUserConsentClientScopeEntity` | (user_consent_id, scope_id) | user_consent_id → fed_user_consent.id | Scopes in fed consent |
| `fed_user_group_membership` | `FederatedUserGroupMembershipEntity` | (group_id, user_id) | (no FKs; group_id and realm_id are varchar columns) | Federated user → group |
| `fed_user_required_action` | `FederatedUserRequiredActionEntity` | (required_action, user_id) | (no FKs) | Pending actions |
| `fed_user_role_mapping` | `FederatedUserRoleMappingEntity` | (role_id, user_id) | (no FKs; role_id and realm_id are varchar columns) | Federated user → role |
| `broker_link` | `BrokerLinkEntity` | (identity_provider, user_id) | (no FKs) | Federated user ↔ external IdP link (parallel to `federated_identity` for non-federated users) |

The 2-column PKs on `fed_user_role_mapping` / `_group_membership` / `_required_action` do **not** include `realm_id` — it is stored as a denormalized column for filtering and cleanup, but is not part of the unique key. Federated user IDs are expected to be globally unique (typically prefixed `f:<storage-provider-id>:<external-id>`), so collisions across realms are avoided by ID convention rather than by schema.

**Why no FKs to user_entity**: federated users live outside Keycloak's `user_entity` (in LDAP, Kerberos, custom storage). Each row carries `user_id + realm_id + storage_provider_id` instead.

**`fed_user_*` mirrors standard tables**: same semantics, denormalized layout.

**LDAP-sourced data is NOT in `fed_user_attribute`** — username, email etc. come from LDAP each time. The `fed_user_*` tables hold things Keycloak adds locally (Keycloak-side roles, required actions, consent grants).

**Sync vs federate modes**:
- **Federate**: user lives only externally; fed tables hold Keycloak-specific extras
- **Sync (import)**: copy users into local `user_entity`, with `federation_link` pointing to source

**Use the model API** — never query `fed_user_*` directly:
```java
session.users().getUserByUsername(realm, "alice");  // dispatches to UserStorageProvider
user.grantRole(role);  // writes to fed_user_role_mapping if user is federated
```

---

## 13. User consent

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `user_consent` | `UserConsentEntity` | id | user_id → user_entity.id, client_id → client.id (or federated client identity, see below) | OAuth2 consent grant per (user, client) |
| `user_consent_client_scope` | `UserConsentClientScopeEntity` | (user_consent_id, scope_id) | both | Scopes granted in this consent |

**Schema**: `id`, `user_id`, `client_id`, `client_storage_provider`, `external_client_id`, `created_date BIGINT`, `last_updated_date BIGINT`. The `client_storage_provider` and `external_client_id` columns (added 4.0.0) support consents for **federated clients** stored in a `ClientStorageProvider` (e.g. LDAP-backed clients) — local-realm clients have these as null.

**Unique constraints** at 26.5.5 (both added in 25.0.0, replacing the older 4-column `UK_JKUWUVD56...` that was dropped):
- `UK_LOCAL_CONSENT` on `(client_id, user_id)` — one consent per (user, local-client) pair.
- `UK_EXTERNAL_CONSENT` on `(client_storage_provider, external_client_id, user_id)` — one consent per (user, federated-client) pair.

Local-client consents have NULL in `client_storage_provider` / `external_client_id`; federated-client consents have NULL in `client_id`.

Updated in place when scopes change rather than inserting new rows.

**How consent works**: when `client.consent_required = true`, on first login Keycloak shows consent screen; user accepts → row inserted/updated. Subsequent logins skip prompt unless new scopes are requested.

**Federated user equivalent**: `fed_user_consent` + `fed_user_consent_cl_scope`.

---

## 14. Events / audit

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `event_entity` | `EventEntity` | id | (no FK; realm_id is varchar) | User auth events (LOGIN, LOGOUT, LOGIN_ERROR, ...) |
| `admin_event_entity` | `AdminEventEntity` | id | (no FK; realm_id is varchar) | Admin operations audit log |

**Optional** — only populated if event listeners are enabled in realm config (`realm_events_listeners` + `realm_enabled_event_types` for user events; admin events have a separate toggle).

**Append-only** — heavy realms produce huge volumes. Common to add a retention purge job.

**No FKs to other domain tables** — events survive entity deletes (intentional, for forensics).

**`realm_id` is `VARCHAR(255)`** — different width from most realm_id columns.

**Long-value spillover columns**:
- `EVENT_ENTITY.DETAILS_JSON_LONG_VALUE NCLOB` (added 23.0.0) — overflow when `DETAILS_JSON VARCHAR(2550)` is too small.
- `ADMIN_EVENT_ENTITY.DETAILS_JSON NCLOB` (added 26.1.0) — admin events did not previously have a details column at all.

Read both columns when querying event details on KC 23+/26.1+ — either may hold the actual payload.

---

## 15. Sessions

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `offline_user_session` | `PersistentUserSessionEntity` | (user_session_id, offline_flag) | realm_id → realm.id (varchar) | Persistent offline user sessions |
| `offline_client_session` | `PersistentClientSessionEntity` | (user_session_id, client_id, client_storage_provider, external_client_id, offline_flag) | (no FK) | Per-client offline session notes |
| `revoked_token` | `RevokedTokenEntity` | id (varchar(255)) | (no FK) | Token blacklist (KC 26.0+) |

**5-column PK on `offline_client_session`** since 4.0.0 (was 2-column before). The extra `client_storage_provider` and `external_client_id` columns let federated clients (LDAP-stored) coexist with realm clients without ID collision.

**Recent column additions on `offline_user_session`**:
- `BROKER_SESSION_ID VARCHAR(1024)` (25.0.0) — links the offline session to the upstream IdP session for SLO propagation.
- `VERSION INT` (25.0.0, also on `offline_client_session`) — JPA `@Version` optimistic-lock counter; concurrent updates throw `OptimisticLockException`.
- `REMEMBER_ME BOOLEAN` (26.5.0) — set when the offline session was created from a "remember me" login. Naive cleanup queries that don't preserve this on rotation will lose the persistence flag.

**Removed in Keycloak 26.0**: `user_session`, `user_session_note`, `client_session`, `client_session_role`, `client_session_note`, `client_session_prot_mapper`, `client_session_auth_status`, `client_user_session_note`. These are now Infinispan-only. If you query them on 26+ you'll get nothing or table-not-found.

**Persistent (offline) sessions still hit DB** for survival across cluster restarts.

**Don't query session tables directly** — use `session.sessions().getUserSession(...)` etc. The model API dispatches between Infinispan (live) and DB (offline).

---

## 16. Organizations

| Table | Entity | PK | FK | Purpose | Min Keycloak |
|---|---|---|---|---|---|
| `org` | `OrganizationEntity` | id | realm_id → realm.id, group_id → keycloak_group.id | Organization (multi-tenancy within a realm) | 25.0 |
| `org_domain` | `OrganizationDomainEntity` | (id, name) | org_id → org.id | Email domains associated with the org | 25.0 |
| `org_invitation` | `OrganizationInvitationEntity` | id | organization_id → org.id | Pending invitations to join. **Note**: this FK column is `organization_id` (asymmetric with `org_domain.org_id`); JPA field is `organizationId`. | 26.5.0 |

**Mirrors a backing group**: `org.group_id` references a `keycloak_group` row. Org membership = group membership.

**Email domains** drive auto-assignment: users with email `@acme.com` can be auto-routed into the corresponding org.

---

## 17. System / metadata

| Table | Entity | PK | FK | Purpose |
|---|---|---|---|---|
| `migration_model` | `MigrationModelEntity` | id | (no FK) | Schema version tracker |
| `databasechangelog` | (Liquibase-managed) | (id, author, filename) | (no FK) | Liquibase: applied changesets |
| `databasechangeloglock` | (Liquibase-managed) | id | (no FK) | Liquibase: migration lock |
| `jgroups_ping` | (no entity) | address | (no FK) | JGroups JDBC_PING cluster discovery (added KC 26.1.0). Columns: `address VARCHAR(200)` (PK), `name VARCHAR(200)`, `cluster_name VARCHAR(200)` (NOT NULL), `ip VARCHAR(200)` (NOT NULL), `coord BOOLEAN`. |

**`migration_model`**: single-row table, records `id` (schema version), `version`, `update_time`. Don't modify manually — Liquibase + Keycloak migration code keeps it consistent.

**`databasechangelog`**: standard Liquibase tracking. `md5sum` column detects modified-after-apply. Extension changelogs appear here too — segregated by `filename`.

**`databasechangeloglock`**: distributed lock during migration. If Keycloak crashes mid-migration:
```sql
UPDATE DATABASECHANGELOGLOCK SET LOCKED = FALSE, LOCKEDBY = NULL, LOCKGRANTED = NULL WHERE ID = 1;
```

**`jgroups_ping`**: only used when clustering uses JDBC_PING for member discovery (alternative to UDP multicast). Otherwise unused.

---

## Common Named Queries

Authoritative list at Keycloak 26.5.5. Verify against the entity class before relying on a name. **Some major entities have no `@NamedQuery` annotations** — those are called out explicitly. For entities without named queries, use the provider API or write inline JPQL / Criteria.

| Entity | Named queries (real, at 26.5.5) |
|---|---|
| `UserEntity` | `getRealmUserByUsername`, `getRealmUserByEmail`, `getRealmUserByLastName`, `getRealmUserByFirstLastName`, `getRealmUserByServiceAccount`, `getRealmUsersByAttributeNameAndValue`, `getRealmUsersByAttributeNameAndLongValue`, `deleteUsersByRealm`, `deleteUsersByRealmAndLink`, `unlinkUsers` |
| `RoleEntity` | `getRealmRoleByName`, `getRealmRoleIdByName`, `getClientRoleByName`, `getClientRoleIdByName`, `getRealmRoles`, `getClientRoles`, `getRealmRoleIds`, `getClientRoleIds`, `getRoleIdsFromIdList`, `getRoleIdsByNameContainingFromIdList`, `getChildRoles`, `searchForRealmRoles`, `searchForClientRoles` |
| `GroupEntity` | `getGroupIdsByParent`, `deleteGroupsByRealm` (no `getTopLevelGroups` — filter on `parentId = ' '` or use `JpaRealmProvider.getTopLevelGroupsStream`) |
| `ClientEntity` | `getClientById`, `findClientByClientId`, `findClientIdByClientId`, `getAllRedirectUrisOfEnabledClients`, `getAlwaysDisplayInConsoleClients` |
| `ClientScopeEntity` | `getClientScopeIds`, `getClientScopesByProtocol` |
| `CredentialEntity` | `credentialByUser`, `deleteCredentialsByRealm`, `deleteCredentialsByRealmAndLink` |
| `RealmEntity` | `getAllRealmIds`, `getRealmIdByName`, `getRealmIdsWithNameContaining`, `getRealmIdsWithProviderType` |
| `MigrationModelEntity` | (defines schema-version queries — see the class) |
| `CompositeRoleEntity` | (see class for delete queries) |
| `UserRoleMappingEntity`, `UserGroupMembershipEntity`, `GroupRoleMappingEntity` | composite-PK relationship entities, each with their own delete-by-realm / delete-by-parent queries |
| Federated user entities (`FederatedUser*`) | each defines its own delete-by-realm / delete-by-storage-provider queries |
| `ComponentEntity` | **none** — use the provider API or inline JPQL |
| `IdentityProviderEntity` | **none** — use the provider API or inline JPQL |
| `IdentityProviderMapperEntity` | **none** |
| `ProtocolMapperEntity` | **none** |
| `AuthenticationFlowEntity` | **none** — use `RealmAdapter` / `JpaRealmProvider` |
| `AuthenticatorConfigEntity` | **none** |
| `EventEntity` | **none** — `JpaEventStoreProvider` writes raw JPQL |
| `AdminEventEntity` | **none** — same |

---

## Cascading Deletes

| Parent deleted | Cascades to (main) |
|---|---|
| `realm` | Almost everything — heavy operation |
| `user_entity` | `user_attribute`, `user_role_mapping`, `user_group_membership`, `credential`, `user_required_action`, `user_consent` (+ `user_consent_client_scope`), `federated_identity` |
| `keycloak_role` | `user_role_mapping`, `group_role_mapping`, `composite_role` (parent and child), `role_attribute`, `client_scope_role_mapping`, `scope_mapping` |
| `keycloak_group` | `group_attribute`, `user_group_membership`, `group_role_mapping`, `keycloak_group` (children recursively), `realm_default_groups` |
| `client` | `client_attributes`, `client_scope_client`, `protocol_mapper` (where client_id matches), `keycloak_role` (client roles), `redirect_uris`, `web_origins`, `client_node_registrations`, `client_auth_flow_bindings`, `user_consent` + `user_consent_client_scope` (via `JpaUserProvider.preRemove`), Authorization Services data |
| `client_scope` | `client_scope_attributes`, `client_scope_client`, `client_scope_role_mapping`, `protocol_mapper` (where client_scope_id matches), `default_client_scope`, consent scope rows |
| `component` | `component_config`, child `component` rows recursively |
| `authentication_flow` | `authentication_execution` (where `flow_id` matches — JPA cascade). Deletion is **blocked** by `KeycloakModelUtils.isFlowUsed` when the flow is bound at realm level (any of `browser`, `registration`, `direct_grant`, `reset_credentials`, `client_authentication`, `docker_authentication`, `first_broker_login`), per-client (`client_auth_flow_bindings` for `browser` / `direct_grant`), or as an IDP `first_broker_login_flow_id` OR `post_broker_login_flow_id` (both matched by `JpaIdentityProviderStorageProvider.getByFlow`). Sub-flow references via `auth_flow_id` are not part of `isFlowUsed`. Block throws `ModelException("Cannot remove authentication flow, it is currently in use")`. |
| `identity_provider` | `identity_provider_config` (JPA `@ElementCollection`), `identity_provider_mapper` + `idp_mapper_config` (provider-level via `getMappersByAliasStream`), `federated_identity` rows referencing this IDP (cleaned via `JpaUserProvider.preRemove(realm, IdentityProviderModel)` → `deleteFederatedIdentityByProvider` named query, matched on alias). The `FEDERATED_IDENTITY.IDENTITY_PROVIDER` column is a plain `VARCHAR(255)` alias without an FK constraint, so this is application-level, not DB-level cascade. Re-creating an IDP with the same alias does NOT resume prior linkages. |

**Implication for extensions**: if you intercept delete on a parent and want to defer it, you must also block the cascade. Either intercept at REST layer (return 409) OR throw in your `*Provider.removeX()` to roll back the transaction.

**Audit log preservation**: `event_entity` and `admin_event_entity` deliberately have no FK to domain tables — events survive entity deletion. Useful for forensics; potentially surprising if you assumed cascade.
