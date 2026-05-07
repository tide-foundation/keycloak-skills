# Keycloak IGA Attestation Units

Self-contained spec for the **16 admin-attestable data structures** that fully cover Keycloak 26.5.5 OIDC token construction. An attestation chain over these 16 units gives the token signing service a complete, non-cherry-pickable guarantee of every input that produced any access token, ID token, userinfo response, or introspection response.

Verified against Keycloak **26.5.5**. Out of scope: authentication, signing keys, sessions, hash claims (`at_hash`, `c_hash`, `s_hash`), custom (non-built-in) protocol mappers' input dependencies.

## Inclusion criterion

A field appears in a unit's payload **only if** at least one of the following holds for the OIDC pipeline:

1. **Claim source** — the field's value (or a deterministic projection of it) becomes a claim value in some issued token. Example: `USER_ENTITY.email` → the `email` claim.
2. **Claim-shape gate** — the field's state changes which claims appear or what values they take, even if the field itself never appears in the JSON. Example: `CLIENT.full_scope_allowed` flips the role intersection in `TokenManager.getAccess`, changing `realm_access` / `resource_access` / `aud`.

Fields that **only** gate authentication, validation, admin-UI display, or session lifecycle (without affecting any issued token's claim map) are deliberately excluded. Each unit below lists what's in *and* what was excluded, with one-line justifications, so an auditor can re-derive the boundary.

This excludes anything a *custom* (non-built-in) mapper might happen to read. If your fork installs custom mappers that read additional fields (e.g. `CLIENT.root_url`, `KEYCLOAK_ROLE.description`), expand the relevant unit and document the dependency.

## Two unit shapes

1. **Definition bundle** — one entity row + its 1:N exclusively-owned children (config / attributes). One bundle per entity instance.
2. **Linkage set** — the **complete** list of child IDs for one parent in a relationship table. One set per parent. Hashing the entire set defeats the cherry-pick attack: deleting a row breaks the hash just as adding one does.

Per-row attestations on relationship tables are deliberately **not used** — they cannot detect deletions.

## Common envelope

Every attestation, regardless of unit type, wraps a `payload` in this envelope:

```json
{
  "unit_type": "<one of the 16 unit types>",
  "schema_version": 1,
  "realm_id": "<UUID of the realm; identical to payload.realm_id>",
  "target_id": "<primary key of the parent entity for this attestation>",
  "payload": { /* unit-specific; see each unit below */ }
}
```

The signed bytes are `JCS(envelope)` (RFC 8785 canonical JSON), hashed with SHA-256. Approver signatures (e.g. one or more Ed25519 sigs) are stored adjacent to the envelope. Main Keycloak tables grow one column — `current_attestation_id` — that points at the envelope's storage row; drafts live in the same store with `status='DRAFT'` and never touch the live row until promoted.

## Canonicalization rules (mandatory for stable hashes)

- **JSON form:** RFC 8785 JCS — UTF-8, sorted object keys, no insignificant whitespace.
- **All ID arrays sorted lexicographically ascending.**
- **All attribute / config lists sorted by `name` ascending; multi-value entries sort their `values` array too.**
- **Optional fields are explicit `null`, never omitted** — keeps the schema and the hash stable across versions.
- **Booleans always explicit `true` / `false`** (never coerced from absent).
- **Long attribute values:** when a `USER_ATTRIBUTE` row spilled into `LONG_VALUE`, use the resolved string; do **not** include the hash columns. The signing service rehydrates the same way before comparing.
- **Hash algorithm:** SHA-256 over the canonical bytes.

The signing service re-runs this same canonicalization against the live DB before every issuance and compares hashes. Any drift = refuse to sign.

---

# Definition bundles (units 1–7)

## 1. `realm_config`

**Trigger:** edit realm name (changes `iss`), edit token lifespans (changes `exp`), edit frontend URL (changes `iss`).

**Source tables:** `REALM`, `REALM_ATTRIBUTE` (filtered).

**Payload schema:**

```json
{
  "realm_id": "string",
  "name": "string",
  "access_token_lifespan_seconds": "integer",
  "access_token_lifespan_for_implicit_flow_seconds": "integer",
  "sso_session_idle_timeout_seconds": "integer",
  "sso_session_max_lifespan_seconds": "integer",
  "client_session_idle_timeout_seconds": "integer",
  "client_session_max_lifespan_seconds": "integer",
  "offline_session_idle_timeout_seconds": "integer",
  "offline_session_max_lifespan_enabled": "boolean",
  "offline_session_max_lifespan_seconds": "integer",
  "attributes": [
    { "name": "frontendUrl", "value": "string" }
  ]
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `name` | Embedded in the `iss` claim URL (`<base>/realms/<name>`), set into `OIDCLoginProtocol.ISSUER` note at auth-session attach. |
| `access_token_lifespan_seconds` | Default lifespan for `exp` (when no client override). |
| `access_token_lifespan_for_implicit_flow_seconds` | Lifespan for `exp` on implicit-flow tokens. |
| `sso_*`, `client_session_*`, `offline_session_*` | Cap `exp` via `getTokenExpiration` (TokenManager.L1027). |
| `attributes` (filtered to `frontendUrl`) | When set, overrides the request URI in `Urls.realmIssuer(...)`, changing `iss`. |

**Excluded (intentionally):**

| Field | Why excluded |
|---|---|
| `enabled` | Gates whether anything works at all; doesn't change the claim map of an issued token. |
| `default_role_id` | At user creation, Keycloak grants `default-roles-<realm>` via a real `USER_ROLE_MAPPING` row. At issuance time, the role appears in unit 8; the realm pointer is never read. |
| `ssl_required` | Transport-level enforcement; not in claims. |
| `default_signature_algorithm` | Signing-key concern (out of scope). |
| `not_before` | Validation policy — checked when verifying tokens, not written into them. |
| Other realm attributes (SMTP, brute-force, password policy, login policy, account-management URL, browser security headers, locale lists) | None reach the OIDC claim map. |

> **Caveat:** if the realm uses the step-up-authentication feature (`Feature.STEP_UP_AUTHENTICATION`), `acr` is written by `AcrProtocolMapper` whose LoA→ACR config lives on the mapper (unit 4), not on the realm. If your fork stores LoA mapping in a realm attribute (e.g. `acr.loa.map`), add it to the filter above.

---

## 2. `client_config`

**Trigger:** rename a client (changes `azp` / `aud`), flip `full_scope_allowed`, flip `service_accounts_enabled`, flip the lightweight-token attribute, change `web_origins`, change a per-client lifespan / `use_refresh_token` / `lower_case_in_token_response` attribute.

**Source tables:** `CLIENT`, `CLIENT_ATTRIBUTES` (filtered), `WEB_ORIGINS`.

**Payload schema:**

```json
{
  "client_id_uuid": "string",
  "client_id": "string",
  "realm_id": "string",
  "protocol": "string",
  "full_scope_allowed": "boolean",
  "service_accounts_enabled": "boolean",
  "web_origins": ["string"],
  "attributes": [
    { "name": "string", "value": "string" }
  ]
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `client_id_uuid` | Target of unit 12, 13, 15 attestations and of `KEYCLOAK_ROLE.container` for client roles; identifier only. |
| `client_id` | Becomes `azp` (initToken L996), the ID-token initial `aud` (L1270), the `resource_access.<client_id>.roles` path key, and `aud` entries via `AudienceResolveProtocolMapper` / `AudienceProtocolMapper`. |
| `protocol` | Gates `loadProtocolMappers` (DCSC.L312-315) and the per-mapper protocol filter (L322). Flipping to `"saml"` produces an empty mapper set → base-claims-only OIDC token. |
| `full_scope_allowed` | Flips role-intersection short-circuit in `TokenManager.getAccess` (L605-609); directly changes `realm_access`, `resource_access`, and `aud` (via AudienceResolve). |
| `service_accounts_enabled` | Triggers runtime auto-attachment of the realm's `service_account` client scope (whose mappers write `clientHost`, `clientAddress`, `client_id`). |
| `web_origins` | Read by `AllowedWebOriginsProtocolMapper` and written verbatim into the `allowed-origins` claim. |
| `attributes` (filtered list below) | All claim-affecting client attributes. |

**Allow-list of token-affecting client attributes** (filter `CLIENT_ATTRIBUTES` to these only):

| Attribute | Effect on token |
|---|---|
| `client.use.lightweight.access.token.enabled` | Switches the access-token mapper toggle from `access.token.claim` to `lightweight.claim` — entire fire/skip set changes. |
| `client_credentials.use_refresh_token` | Default `"false"` → `client_credentials` grant creates TRANSIENT session → `OAuth2GrantTypeBase.L132` nulls `sid` on the access token, propagates to id-token `sid` via `generateIDToken`. |
| `access.token.lifespan` | Per-client override of `exp`. |
| `use.lower.case.in.token.response` | Lowercases the `typ` claim (`formatTokenType`). |

**Excluded (intentionally):**

| Field | Why excluded |
|---|---|
| `name`, `description` | Admin UI / consent screen text only. |
| `enabled`, `bearer_only`, `public_client`, `consent_required`, `standard_flow_enabled`, `implicit_flow_enabled`, `direct_access_grants_enabled`, `frontchannel_logout`, `surrogate_auth_required`, `always_display_in_console` | Gate authentication / which grant types succeed; an issued OIDC token's claim map doesn't depend on them. The skill explicitly notes `consent_required` is "orthogonal to claim shape but can fail the request." |
| `root_url`, `base_url`, `management_url` | Not read by `initToken` or any built-in mapper. |
| `redirect_uris` | Validated at the auth/redirect step; never reaches a claim. |
| `not_before` | Validation policy. |
| `secret`, `registration_token` | Auth credentials. |
| `node_re_registration_timeout` | Cluster registration housekeeping. |
| `id.token.signed.response.alg`, `access.token.signed.response.alg` (and other `*.signed.response.alg`) | Signing-key concerns (out of scope). |
| `pkce.code.challenge.method`, `tls.client.certificate.bound.access.tokens`, `dpop.bound.access.tokens` | Auth-binding policy; affect token issuance preconditions and JWS-level binding, not the claim map. |
| All admin-UI / consent-display attributes | Not read by the construction pipeline. |

---

## 3. `client_scope_config`

**Trigger:** rename a scope (changes the `scope` claim), flip `include.in.token.scope`, change scope `protocol` (silently disables scope's mappers).

**Source tables:** `CLIENT_SCOPE`, `CLIENT_SCOPE_ATTRIBUTES` (filtered).

**Payload schema:**

```json
{
  "client_scope_id": "string",
  "name": "string",
  "realm_id": "string",
  "protocol": "string",
  "attributes": [
    { "name": "include.in.token.scope", "value": "string" }
  ]
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `name` | Joined into the `scope` claim by `DCSC.getScopeString` (DCSC.L188-212) when `include.in.token.scope` is true. |
| `protocol` | Mapper-set assembly filters mappers by `m.protocol == client.protocol` (DCSC.L322). A scope whose `protocol` isn't `openid-connect` contributes zero mappers to an OIDC token. |
| `attributes.include.in.token.scope` | Decides whether `name` appears in the `scope` claim. **Default-when-absent is `true`** (`ClientScopeModel.java:109-112`) — emit it explicitly with the canonical value the signing service should compare against. |

**Excluded:**

| Field | Why excluded |
|---|---|
| `description` | Consent screen text. |
| Other scope attributes (`display.on.consent.screen`, `consent.screen.text`, `gui.order`) | Consent UI only; not in claim map. |

---

## 4. `protocol_mapper`

**Trigger:** add or delete a mapper (also requires re-attesting the parent's mapper-set, unit 13 or 14), edit any mapper config key.

**Source tables:** `PROTOCOL_MAPPER`, `PROTOCOL_MAPPER_CONFIG`. Config rows are 1:N exclusive to one mapper, so they bundle here.

**Payload schema:**

```json
{
  "protocol_mapper_id": "string",
  "realm_id": "string",
  "parent_type": "client | client_scope",
  "parent_id": "string",
  "protocol": "string",
  "protocol_mapper": "string",
  "config": [
    { "name": "string", "value": "string" }
  ]
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `protocol_mapper_id` | Target id; referenced by units 13/14. |
| `parent_type` + `parent_id` | A mapper cannot move parents — bind the mapper definition to its parent in the hash. Exactly one of `PROTOCOL_MAPPER.client_id` or `PROTOCOL_MAPPER.client_scope_id` is set (gotcha #5). |
| `protocol` | Mapper-set assembly filters by protocol (DCSC.L322). Flipping to `"saml"` silently drops the mapper from the OIDC set. |
| `protocol_mapper` | Factory id (e.g. `oidc-usermodel-property-mapper`); selects which `setClaim` override runs. |
| `config[]` | All configured behavior — surface toggles (`access.token.claim`, `id.token.claim`, `userinfo.token.claim`, `introspection.token.claim`, `lightweight.claim`, `access.tokenResponse.claim`), claim-name / claim-path, jsonType, multivalued, user-property name, hardcoded value, sector identifier, etc. |

**Excluded:**

| Field | Why excluded |
|---|---|
| `name` (display) | Admin-UI label — no built-in mapper reads it; `config["claim.name"]` (already in `config`) determines the claim path. |

---

## 5. `role_definition`

**Trigger:** rename a role (changes `realm_access.roles` / `resource_access.<client>.roles`), flip `client_role` (changes which mapper writes the role and where), move a client role's container.

**Source tables:** `KEYCLOAK_ROLE`. (`ROLE_ATTRIBUTE` is intentionally excluded — see below.)

**Payload schema:**

```json
{
  "role_id": "string",
  "name": "string",
  "realm_id": "string",
  "client_role": "boolean",
  "container_id": "string"
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `name` | The literal value written into `realm_access.roles[]` or `resource_access.<client>.roles[]` by `UserRealmRoleMappingMapper` / `UserClientRoleMappingMapper`. |
| `client_role` | Determines which role mapper handles the role and which claim path it lands in. |
| `container_id` | For client roles, this is the owning client's UUID — unit 2 of that client provides the `client_id` string used as the `resource_access.<client_id>.roles` map key and as an `aud` entry contributed by `AudienceResolveProtocolMapper`. For realm roles, it's the realm id. |

**Excluded:**

| Field | Why excluded |
|---|---|
| `description` | Admin UI only. |
| `ROLE_ATTRIBUTE` rows | No built-in mapper reads role attributes. (Custom mappers can; if your fork has one, add an `attributes` field here.) |

---

## 6. `group_definition`

**Trigger:** rename a group (changes group claim), reparent a group (changes the path produced by `GroupMembershipMapper` AND changes the inherited-role chain via `RoleUtils.addGroupRoles`), change `type` (regular ↔ organization-backed) which gates `OrganizationMembershipMapper`.

**Source tables:** `KEYCLOAK_GROUP`. (`GROUP_ATTRIBUTE` is intentionally excluded — see below.)

**Payload schema:**

```json
{
  "group_id": "string",
  "name": "string",
  "realm_id": "string",
  "parent_group_id": "string | null",
  "type": "REALM | ORGANIZATION"
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `name` | Written into the group claim by `GroupMembershipMapper`. |
| `parent_group_id` | (a) `GroupMembershipMapper` builds the slash-separated path by walking parents, so renaming or reparenting a parent changes the emitted path; (b) `RoleUtils.addGroupRoles` recurses on `parent_group`, so a user in a subgroup inherits roles from each ancestor's `GROUP_ROLE_MAPPING`. |
| `type` | `OrganizationMembershipMapper` only emits org info for memberships in groups with `type = ORGANIZATION` (KC 26.0+). |

**Notes:**

- `parent_group_id` is `null` for top-level groups. **Do not** carry Keycloak's literal `' '` (single-space) sentinel — translate to `null` in canonical form. The signing service translates back when comparing against the live DB (gotcha #2).

**Excluded:**

| Field | Why excluded |
|---|---|
| `GROUP_ATTRIBUTE` rows | No built-in mapper reads group attributes. (`OrganizationMembershipMapper` reads from the `ORG` table, not group attributes.) Add to this unit if your fork has a custom group-attribute mapper. |

---

## 7. `user_identity`

**Trigger:** edit user profile (any of the property fields below), edit any user attribute.

**Source tables:** `USER_ENTITY` (filtered), `USER_ATTRIBUTE`.

**Payload schema:**

```json
{
  "user_id": "string",
  "username": "string",
  "realm_id": "string",
  "email": "string | null",
  "email_verified": "boolean",
  "first_name": "string | null",
  "last_name": "string | null",
  "attributes": [
    { "name": "string", "values": ["string"] }
  ]
}
```

**Why each field is in:**

| Field | Justification |
|---|---|
| `user_id` | `user.getId()` → `sub` (when `initToken` writes it on TRANSIENT sessions, and via `SubMapper` on persistent sessions). Also the lookup key for units 8 / 9. |
| `username` | `UserPropertyMapper` reads `getUsername()` → `preferred_username`. |
| `email` | `UserPropertyMapper` → `email`. |
| `email_verified` | `UserPropertyMapper` → `email_verified`. |
| `first_name` | `UserPropertyMapper` → `given_name`; also one input to `FullNameMapper` (`name` claim). |
| `last_name` | `UserPropertyMapper` → `family_name`; second input to `FullNameMapper`. |
| `attributes[]` | `UserAttributeMapper` reads any named attribute → configurable claim path. `AddressMapper` reads attributes prefixed by configured names → `address.*` claim. |

**Notes:**

- `attributes` MUST resolve `LONG_VALUE` spillover (`USER_ATTRIBUTE.LONG_VALUE`, KC 24+) to plain strings before hashing — the canonical form is the resolved string, not the column-split form.
- For service-account users (`username = "service-account-<clientId>"`), this same unit applies; the user is just a row in `USER_ENTITY`.

**Excluded:**

| Field | Why excluded |
|---|---|
| `enabled` | Gates whether tokens issue at all; doesn't appear in any claim. |
| `created_timestamp` | Not in claims. |
| `not_before` | Validation policy. |
| `federation_link` | UserStorage federation pointer; never read by built-in mappers. |
| `service_account_client_link` | Identifies which client owns this service-account user for admin lookups; mappers on the `service_account` scope read session notes (`clientHost`, `clientAddress`, `client_id`), not this column. |
| `CREDENTIAL`, `USER_REQUIRED_ACTION`, `USER_CONSENT`, `FEDERATED_IDENTITY` | Auth concerns (CREDENTIAL, REQUIRED_ACTION), orthogonal to claim shape (CONSENT — skill: "gates the request, doesn't change the claims map"), or already captured upstream (FEDERATED_IDENTITY rows are link-tracking from broker login; the IDP mapper outputs are stored in `USER_ATTRIBUTE` / `USER_ROLE_MAPPING`). |

---

# Linkage sets (units 8–16)

Every linkage set hashes the **complete** child-id collection for one parent. Adding or removing a row changes the hash. Per-row attestation is forbidden — it cannot detect deletions.

## 8. `user_role_mapping_set`

**Trigger:** grant or revoke a role to/from user U.

**Source tables:** `USER_ROLE_MAPPING`.

**Payload schema:**

```json
{
  "user_id": "string",
  "realm_id": "string",
  "role_ids": ["string"]
}
```

**Notes:**

- `role_ids` sorted lex ascending.
- Includes the implicit grant of `default-roles-<realm>` — every user gets a real `USER_ROLE_MAPPING` row at creation, so the role appears here naturally; its expansion is unit 11.

---

## 9. `user_group_membership_set`

**Trigger:** add or remove user U from any group (regular or org-backed).

**Source tables:** `USER_GROUP_MEMBERSHIP`.

**Payload schema:**

```json
{
  "user_id": "string",
  "realm_id": "string",
  "group_ids": ["string"]
}
```

**Notes:**

- `group_ids` sorted lex ascending.
- `MEMBERSHIP_TYPE` (UNMANAGED / MANAGED) is **excluded** — it controls org-membership lifecycle (whether the user can outlive the group), not claim emission. `OrganizationMembershipMapper` filters by `KEYCLOAK_GROUP.type = ORGANIZATION` (covered in unit 6), not by membership type.

---

## 10. `group_role_mapping_set`

**Trigger:** grant or revoke a role to/from group G.

**Source tables:** `GROUP_ROLE_MAPPING`.

**Payload schema:**

```json
{
  "group_id": "string",
  "realm_id": "string",
  "role_ids": ["string"]
}
```

---

## 11. `role_composite_children_set`

**Trigger:** add or remove a child role to/from composite R. Includes the `default-roles-<realm>` role's child set, which controls realm-default + client-default role inheritance for new users (the role is granted to every user via unit 8 at creation; this unit attests its expansion).

**Source tables:** `COMPOSITE_ROLE`.

**Payload schema:**

```json
{
  "composite_role_id": "string",
  "realm_id": "string",
  "child_role_ids": ["string"]
}
```

**Notes:**

- A non-composite role still gets an attestation here, with `child_role_ids = []`. That way the signing service can prove the role is non-composite (vs. unattested).

---

## 12. `client_scope_assignment_set`

**Trigger:** attach or detach a default or optional scope to/from client C.

**Source tables:** `CLIENT_SCOPE_CLIENT`.

**Payload schema:**

```json
{
  "client_id_uuid": "string",
  "realm_id": "string",
  "assignments": [
    { "client_scope_id": "string", "default": "boolean" }
  ]
}
```

**Notes:**

- Sort `assignments` by `client_scope_id` ascending.
- `default = true` → default scope (always applied). `default = false` → optional scope (applied only if named in the request's `scope` param).
- The realm's `service_account` scope is **NOT** stored here for service-account-enabled clients — it auto-attaches at runtime when `client.service_accounts_enabled = true` (unit 2). The signing service applies that rule.

---

## 13. `client_mapper_set`

**Trigger:** add or remove a mapper directly attached to client C. Each individual mapper's content is unit 4; this unit detects deletions and additions of the mapper rows themselves.

**Source tables:** `PROTOCOL_MAPPER` (filtered by `client_id`).

**Payload schema:**

```json
{
  "client_id_uuid": "string",
  "realm_id": "string",
  "protocol_mapper_ids": ["string"]
}
```

---

## 14. `client_scope_mapper_set`

**Trigger:** add or remove a mapper attached to scope S.

**Source tables:** `PROTOCOL_MAPPER` (filtered by `client_scope_id`).

**Payload schema:**

```json
{
  "client_scope_id": "string",
  "realm_id": "string",
  "protocol_mapper_ids": ["string"]
}
```

---

## 15. `scope_role_allowlist_set`

**Trigger:** edit which roles a scope (or a non-full-scope client) is allowed to issue.

**Source tables:** `CLIENT_SCOPE_ROLE_MAPPING` (when `parent_type = "client_scope"`) or `SCOPE_MAPPING` (when `parent_type = "client"` — the client's own role allowlist used by `TokenManager.getAccess` when `full_scope_allowed = false`).

**Payload schema:**

```json
{
  "parent_type": "client | client_scope",
  "parent_id": "string",
  "realm_id": "string",
  "role_ids": ["string"]
}
```

**Notes:**

- An empty `role_ids` for a client scope means **universal** — `isClientScopePermittedForUser` short-circuits to `true` (DCSC.L274-275). Always emit the empty array explicitly so the signing service can verify "no allowlist entries" was the attested intent, not a missing attestation.
- For `parent_type = "client"`: when `client.full_scope_allowed = true` (in unit 2's payload), this allowlist is bypassed by `TokenManager.getAccess`. Still attest it — flipping `full_scope_allowed` to `false` later should not require a separate allowlist re-attestation.

---

## 16. `realm_default_groups_set`

**Trigger:** add or remove a realm default group.

**Source tables:** `REALM_DEFAULT_GROUPS`.

**Payload schema:**

```json
{
  "realm_id": "string",
  "group_ids": ["string"]
}
```

**Notes:**

- This affects only newly-created users (each is auto-joined to these groups at user creation). Existing users' memberships live in unit 9.
- A token issuance for an already-existing user does **not** require this unit — only flows that create a user mid-issuance (broker first-login, admin user-creation) need it.

---

# Verification — graph walk at token-issuance time

Given `(user U, client C, scopeParam, surface)`, the signing service walks this graph against the live DB and the attestation store. For each node visited, it (a) recomputes the canonical hash from current rows, (b) compares to the latest `APPROVED` attestation, (c) verifies approver signatures. Any mismatch → refuse to sign.

```
realm_config(R)                                      ← unit 1
client_config(C)                                     ← unit 2
client_scope_assignment_set(C)                       ← unit 12
client_mapper_set(C)                                 ← unit 13
scope_role_allowlist_set("client", C)                ← unit 15
for each mapper M in client_mapper_set(C):
    protocol_mapper(M)                               ← unit 4

resolved_scopes ← (default scopes from unit 12)
                ∪ (optional scopes from unit 12 named in scopeParam)
                ∪ (realm's "service_account" scope IF client_config.service_accounts_enabled)
                ∪ ({client_scope_id: C} — the client itself participates as a ClientScopeModel)

for each scope S in resolved_scopes:
    client_scope_config(S)                           ← unit 3
    client_scope_mapper_set(S)                       ← unit 14
    scope_role_allowlist_set("client_scope", S)      ← unit 15
    for each mapper M in client_scope_mapper_set(S):
        protocol_mapper(M)                           ← unit 4

user_identity(U)                                     ← unit 7
user_role_mapping_set(U)                             ← unit 8
user_group_membership_set(U)                         ← unit 9

groups_to_walk ← all groups in user_group_membership_set(U)
visited_groups ← ∅
while groups_to_walk non-empty:
    G ← pop(groups_to_walk)
    if G ∈ visited_groups: continue
    visited_groups += G
    group_definition(G)                              ← unit 6
    group_role_mapping_set(G)                        ← unit 10
    if group_definition(G).parent_group_id != null:
        groups_to_walk += parent_group_id

roles_to_walk ← user_role_mapping_set(U).role_ids
              ∪ ⋃ { group_role_mapping_set(G).role_ids : G ∈ visited_groups }
visited_roles ← ∅
while roles_to_walk non-empty:
    R ← pop(roles_to_walk)
    if R ∈ visited_roles: continue
    visited_roles += R
    role_definition(R)                               ← unit 5
    role_composite_children_set(R)                   ← unit 11
    roles_to_walk += role_composite_children_set(R).child_role_ids

# Cross-client dependency: client roles in the user's effective set carry
# their owning client's client_id string into resource_access path keys
# and into aud (via AudienceResolveProtocolMapper). Attest each container.
for each role R in visited_roles WHERE role_definition(R).client_role:
    client_config(role_definition(R).container_id)   ← unit 2

# unit 16 only required when the request creates a new user (broker first-login,
# admin user-creation flow). Steady-state issuance does not need it.
```

If every node passes, the signing service knows: every byte of state that fed `construct(user, client, scopeParam, surface, sessionCtxAttrs) → claimsMap` was admin-attested. Sign the token.

---

# Out of scope (intentionally not attested)

These are state surfaces that either don't reach token claims, or sit upstream of state already covered:

- **`COMPONENT` (KeyProvider)** — signing keys are the signing service's domain.
- **Authentication flows** (`AUTHENTICATION_FLOW`, `AUTHENTICATION_EXECUTION`, `AUTHENTICATOR_CONFIG`), `CREDENTIAL`, `USER_REQUIRED_ACTION` — auth, not token construction.
- **`USER_CONSENT` / `USER_CONSENT_CLIENT_SCOPE`** — gates whether the request *fails*, doesn't change the claims map.
- **`IDENTITY_PROVIDER` / `IDENTITY_PROVIDER_MAPPER` / `FEDERATED_IDENTITY`** — broker login. IDP mappers run at login and write into `USER_ATTRIBUTE` / `USER_ROLE_MAPPING`, which units 7/8 already capture.
- **`fed_user_*`** — if external user storage is in use, you'll need parallel "federated user identity" / "federated user role-mapping set" units (mirroring 7/8) since these tables have no FKs and won't be picked up by unit 7's joins.
- **Organizations** (`ORG`, `ORG_DOMAIN`, KC 25+) — if `OrganizationMembershipMapper` reads org name / domains for the `organization` claim, add an "org definition" unit (org row + its exclusive `ORG_DOMAIN` children). Org *membership* is already covered by unit 9 (rows in `USER_GROUP_MEMBERSHIP` to a `KEYCLOAK_GROUP.type = ORGANIZATION`).
- **Sessions** (`offline_user_session`, `offline_client_session`, `revoked_token`) — Infinispan-only since 26.0; not part of token *construction*.
- **`at_hash` / `c_hash` / `s_hash` / `jti`** — computed over the encoded JWS or generated, not from the claims map. Not subject to admin attestation.
- **Custom (non-built-in) mappers' input dependencies** — every field excluded above was excluded *for the built-in mapper set*. If a custom mapper reads e.g. `KEYCLOAK_ROLE.description` or `CLIENT.root_url`, expand the relevant unit and document the dependency.

---

# Unit summary table

| # | Unit type | Shape | Target | Triggering admin action |
|---|---|---|---|---|
| 1 | `realm_config` | Definition bundle | realm UUID | Edit realm name / token lifespans / frontend URL |
| 2 | `client_config` | Definition bundle | client UUID | Rename client, flip full-scope / service-accounts / lightweight, change web_origins / lifespan / use_refresh_token / lower_case |
| 3 | `client_scope_config` | Definition bundle | scope UUID | Rename scope, flip `include.in.token.scope`, change scope protocol |
| 4 | `protocol_mapper` | Definition bundle | mapper UUID | Add/edit/delete mapper config (incl. surface toggles, claim name, factory id) |
| 5 | `role_definition` | Definition bundle | role UUID | Rename role, flip `client_role`, move container |
| 6 | `group_definition` | Definition bundle | group UUID | Rename / reparent group, flip `type` (REALM ↔ ORGANIZATION) |
| 7 | `user_identity` | Definition bundle | user UUID | Edit username / email / names / verified flag / attributes |
| 8 | `user_role_mapping_set` | Linkage set | user UUID | Grant/revoke role to user |
| 9 | `user_group_membership_set` | Linkage set | user UUID | Add/remove user from group |
| 10 | `group_role_mapping_set` | Linkage set | group UUID | Grant/revoke role to group |
| 11 | `role_composite_children_set` | Linkage set | composite role UUID | Add/remove composite child |
| 12 | `client_scope_assignment_set` | Linkage set | client UUID | Attach/detach scope to client |
| 13 | `client_mapper_set` | Linkage set | client UUID | Add/remove mapper on client |
| 14 | `client_scope_mapper_set` | Linkage set | scope UUID | Add/remove mapper on scope |
| 15 | `scope_role_allowlist_set` | Linkage set | client OR scope UUID | Edit role allowlist |
| 16 | `realm_default_groups_set` | Linkage set | realm UUID | Add/remove realm default group |
