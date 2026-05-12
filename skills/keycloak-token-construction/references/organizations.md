# Organisations: the `organization` claim

> **All source paths in this document are remote URLs at [github.com/keycloak/keycloak](https://github.com/keycloak/keycloak) tag `26.5.5` — they are NOT files in this working directory.** Use `WebFetch` to inspect them; do not look for them on the local filesystem. Full path → URL mapping is in [source-pointers.md](source-pointers.md).

Defines how the `organization` claim is constructed in OIDC tokens when the
realm has `organizationsEnabled=true` and the server `ORGANIZATION` feature is
enabled. The claim is produced exclusively by `oidc-organization-membership-mapper`,
which is baked into the realm's built-in `organization` client scope. There are
**three distinct entry paths** with materially different behaviour. The skill
text in [scope-resolution.md](scope-resolution.md) L22-28 + L35-37 names two of
the mechanisms (dedup; `tryResolveDynamicClientScope`) but does not document
the per-form behaviour or the wire shape — this file does both.

The three forms are governed by the literal `scope` parameter on the token
request. Same client, same user, same grant — only the scope param varies:

| Scope param form | What it requests | Multi-member user behaviour | Single-member user behaviour | Zero-member user behaviour |
| --- | --- | --- | --- | --- |
| `organization` (unqualified, static) | the static-default `organization` client scope | **claim absent** (NON_NULL drop) | `["acme"]` (the one alias) | **claim absent** (NON_NULL drop) |
| `organization:*` (wildcard, dynamic) | all of the user's memberships | `["alias1", "alias2", ...]`, HashSet-iteration order | `["acme"]` | **claim absent** (mapper not in set; see §3.2) |
| `organization:<alias>` (specific, dynamic) | exactly the named org | `["<alias>"]` if member; **HTTP 400 `invalid_scope`** pre-flight if not | same | **HTTP 400 `invalid_scope`** pre-flight |

Three behavioural traps fall out of this table:

- The unqualified static path is a **lucky-path** for single-membership users only. A skill reader writing a JWT mock for a multi-member user will get the claim missing if they only pass `scope=organization`.
- The wildcard's array order is **not contract-derivable** from the documented behaviour. Cross-fixture evidence (adversarial-5 vs adversarial-6) shows the order is HashSet-iteration over org UUIDs — the same shape as invariant 10's mapper-sort ties.
- The specific form `organization:<alias>` is the only path that **rejects at the HTTP layer** when the alias is unknown to the user. The other two paths emit an absent claim with a successful HTTP 200.

## 1. Wire shape under default mapper config

The `oidc-organization-membership-mapper` in the realm's built-in `organization`
client scope is configured by default with:

- `claim.name=organization`
- `jsonType.label=String`
- `multivalued=true`
- `access.token.claim=true`
- `id.token.claim=true`
- `introspection.token.claim=true`
- `addOrganizationId`, `addOrganizationAttributes` unset

Under those defaults, the claim is a **flat JSON array of org alias strings**:

```json
"organization": ["acme"]
```

The same array literal appears on the access token, the ID token, and (per the
toggles) the userinfo / introspection responses. Same shape, same contents,
across surfaces — invariants 7 and 9 hold here just as for any other mapper.

The mapper exposes `addOrganizationId` and `addOrganizationAttributes` config
flags that change the shape (likely to a per-org object map keyed by alias).
This skill does not yet pin those alternative shapes — they have no fixture
coverage. The OOTB shape is array-of-strings.

### 1.1. Per-org emit filter (multivalued branch — source-traced)

Inside `OrganizationMembershipMapper.resolveValue`
([`services/src/main/java/org/keycloak/organization/protocol/mappers/oidc/OrganizationMembershipMapper.java`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/organization/protocol/mappers/oidc/OrganizationMembershipMapper.java),
the for-loop in the multivalued branch on Keycloak 26.5.5), each candidate
org is filtered before its alias is emitted:

```java
for (OrganizationModel o : organizations) {
    if (o == null || !o.isEnabled() || user == null || !o.isMember(user)) {
        continue;
    }
    ...
    value.put(o.getAlias(), claims);
}
```

`OrganizationModel.isEnabled()` is the standard model-layer projection of the
`ORG.enabled` column — no separately-populated cache sits between the column
and the filter. Disabling an org via `ORG.enabled=false` therefore suppresses
its alias from the claim with no companion change to `USER_GROUP_MEMBERSHIP`
required. The same loop also calls `o.isMember(user)`, which is the
membership lookup against the org's backing group (`KEYCLOAK_GROUP.type =
ORGANIZATION`) — see [keycloak-entities/references/entities.md §16](../../keycloak-entities/references/entities.md).

**`multivalued=false` carve-out (non-default).** The default mapper config is
`multivalued=true` (see the config table in §1). When a deployment flips the
flag to `false`, `resolveValue` short-circuits to
`organizations.get(0).getAlias()` **before** the for-loop runs — so neither
`isEnabled()` nor `isMember()` is checked. Under that config, a disabled
org's alias can still emit if it sits at position 0 of the resolved-orgs
list. Source-only; no fixture coverage. Build a fixture flipping
`multivalued=false` against a disabled-org / non-member to anchor the
carve-out empirically.

## 2. NON_NULL on zero/empty membership

When the mapper would write null (e.g. zero-membership user on the static path,
multi-member user on the static path — see §3.1 — or an unresolved dynamic
scope where the mapper never reaches the set), invariant 11 takes over:
`JsonInclude.NON_NULL` drops the claim from the wire entirely. The wire shape
is **not** `[]` or `{}` — it is the absence of the key.

Empirical anchor: `tests/token-construction/adversarial-4/actual-token-nonmember.json`
has no `organization` key; `jq 'has("organization")'` returns `false`.

## 3. The three scope-param entry paths

### 3.1. Unqualified `scope=organization` (static path)

Activates only the static-default `organization` client scope. The dedup rule
in [scope-resolution.md](scope-resolution.md) L22-28 does **not** fire (the
rule requires `name + ":"` substring, and unqualified `organization` has no
colon). So the static-default scope survives candidate-set assembly, the
mapper enters the mapper set, and `setClaim` runs.

The mapper writes the `organization` claim **only when the user has exactly
one organisation membership.** For zero-membership or multi-membership, the
mapper writes null and invariant 11 (NON_NULL) drops the claim. The mechanism
inside `setClaim` that produces null for N≠1 is not source-traced in this
skill — but the empirical behaviour is reproducible (adv-4 single-member +
adv-5 multi-member).

**Single-membership side-finding (observed; mechanism not yet source-traced).**
When `Feature.ORGANIZATION` is on and the user has exactly one membership,
`organization` can appear **twice in the literal `scope` claim string** (e.g.
`"openid profile organization organization email"`). Both occurrences refer to
the static-default `organization` scope name. The candidate-set algorithm in
[scope-resolution.md](scope-resolution.md) L22-41 ends in `.distinct()`, which
operates over `ClientScopeModel` instances (not by string-name comparison) —
the most likely explanation is that the static path and an internal
auto-resolution path produce two distinct `ClientScopeModel` instances with
identical names, both survive `.distinct()`, and both render as `organization`
in `getScopeString()`'s `join(" ")`. Adv-4's `surprises.md` documents the
observation and the log lines that triggered it; a source-code trace is
flagged as future work. The duplicate does not appear under §3.2 or §3.3.

### 3.2. Wildcard `scope=organization:*` (dynamic path)

The dedup rule in [scope-resolution.md](scope-resolution.md) L22-28 fires
(`organization:` prefix matches the static-default scope's `name + ":"`) and
**drops the static-default `organization` from the candidate set.**
`tryResolveDynamicClientScope("organization:*", user, session)` then resolves
a dynamic `ClientScopeModel` whose `name` is the literal `"organization:*"`,
with an `OrganizationMembershipMapper` configured to emit **all of the user's
memberships** as a flat array of alias strings.

Three downstream consequences:

1. The literal `scope` claim string contains `organization:*` and not bare
   `organization`. The dedup is what removes the bare form.
2. The `organization` claim contains every alias the user is a member of.
3. The **array order is HashSet-iteration over the orgs' UUIDs**, JVM-dependent
   across realm exports — invariant 10's HashSet contract applies (see §5).

Empirical anchors:

- `adversarial-5/actual-token.json` (user member of `zeta` then `acme`):
  with `scope=organization:*`, claim is `["zeta", "acme"]`.
- `adversarial-6/actual-token-wildcard.json` (user member of `acme` then
  `globex`): with `scope=organization:*`, claim is `["globex", "acme"]`.

The two fixtures together rule out alphabetical, reverse-alphabetical,
insertion-order, and reverse-insertion-order as candidate rules. The remaining
explanation that fits both is HashSet bucket order over the UUID hash codes —
the same mechanism documented under invariant 10 for mapper-sort ties.

### 3.3. Specific `scope=organization:<alias>` (dynamic path)

The dedup rule fires (drops the static-default `organization`).
`tryResolveDynamicClientScope("organization:<alias>", user, session)`:

- If `<alias>` is a real organisation in the realm AND the user is a member
  of it: returns a dynamic `ClientScopeModel` named literally
  `organization:<alias>`, with an `OrganizationMembershipMapper` scoped to
  the requested alias only. The `organization` claim is then `["<alias>"]`
  (a one-element array).
- If `<alias>` is not a real organisation, OR the user is not a member of
  it: `tryResolveDynamicClientScope` returns null. Pre-flight `isValidScope`
  ([scope-resolution.md](scope-resolution.md) L86-97) rejects the request
  with `OAuthErrorException.INVALID_SCOPE` → HTTP 400 with body
  `{"error":"invalid_scope","error_description":"Invalid scopes: ..."}`,
  and `event.error(Errors.INVALID_REQUEST)` produces a `CLIENT_LOGIN_ERROR`
  WARN in the events log. No token is minted.

The literal `scope` claim string (on success) contains `organization:<alias>`
and not bare `organization`.

Empirical anchors:

- Success: `adversarial-6/actual-token-specific.json` — request
  `scope=openid organization:acme` against a user member of `acme` → claim
  `["acme"]`, scope claim contains `organization:acme`, no bare `organization`.
- Pre-flight reject: `adversarial-6/actual-response-nonexistent.json` —
  request `scope=openid organization:nonexistent` → HTTP 400, body
  `{"error":"invalid_scope","error_description":"Invalid scopes: openid organization:nonexistent"}`.

## 4. Pre-flight vs silent-skip — clarifying L156-159

[scope-resolution.md](scope-resolution.md) L156-159 currently says:

> Dynamic scope rejected by `tryResolveDynamicClientScope`: silently skipped
> by Step 1. If the name is otherwise unknown, pre-flight `isValidScope`
> still rejects.

This is load-bearing for the §3.3 outcome. The natural-language reading is
ambiguous: when does an unknown alias count as "otherwise unknown"?

The empirically-verified rule (adversarial-6 request 3) is:

- **"Silently skipped by Step 1"** describes Step 1 of the *post-auth
  construction pipeline* (the candidate-set assembly inside
  `getRequestedClientScopes`). That step never runs in the rejection case.
- **`isValidScope`** runs *before* Step 1 (it is called by
  `OAuth2GrantTypeBase.getRequestedScopes` at L240-259, before any
  post-auth code). For dynamic-scope-shaped names like
  `organization:nonexistent`, `isValidScope` calls into the same dynamic
  resolver — if it returns null, pre-flight rejects with `INVALID_SCOPE`.
  A registered prefix is not by itself enough to pass pre-flight; the
  alias has to resolve.

So `organization:nonexistent` is treated as "the name is otherwise unknown"
in L156-159's phrasing — the prefix being registered does not save it. The
silent-skip path is reserved for cases where a *different* resolution
mechanism finds the name (e.g. an exact match against an optional or default
scope) but `tryResolveDynamicClientScope` declines to handle it. There is no
such overlap on `organization:<alias>`.

## 5. Intra-mapper Set iteration — extending invariant 10

Invariant 10 in [SKILL.md](../SKILL.md) is currently scoped to
`ProtocolMapperUtils.compare` (mapper-sort ties at the `Set<ProtocolMapperModel>`
layer). The same HashSet contract applies one layer down, inside
`oidc-organization-membership-mapper`'s wildcard emission: it iterates the
user's organisation memberships (a Java `Set<OrganizationModel>` backed by a
JPA stream) and emits them in HashSet-bucket order over the org UUIDs.

The cross-fixture observation in §3.2 is the empirical anchor. A verifier
asked to predict the *order* of the `organization` claim array under
`scope=organization:*` should hedge with the same shape adversarial-2 used
for the inter-scope `scope` claim order: commit to the set, hedge on the
order, cite invariant 10's HashSet contract.

A verifier asked to predict only the **set** of aliases (which orgs the user
is a member of) has no such hedge — that is fully contract-derivable from
the realm membership state.

## 6. Cross-fixture summary

The three adversarial fixtures `adv-4`, `adv-5`, `adv-6` together anchor
every claim in this file:

| Fixture | Probe | Anchors §§ |
| --- | --- | --- |
| `tests/token-construction/adversarial-4` | Single-membership user + zero-membership control under unqualified `scope=organization` | §1 (wire shape), §2 (NON_NULL drop for zero membership), §3.1 (single-member lucky path) |
| `tests/token-construction/adversarial-5` | Multi-membership user under unqualified `scope=organization` | §3.1 (multi → claim absent) |
| `tests/token-construction/adversarial-6` | Multi-membership user under three dynamic forms (`:acme`, `:*`, `:nonexistent`) | §3.2 (wildcard), §3.3 (specific + reject), §4 (pre-flight), §5 (intra-mapper Set iteration; cross-anchor with adv-5) |

The fixtures are the authoritative wire-shape evidence. Mapper internals are
not logged at any level (per [SKILL.md](../SKILL.md) "When to consult
fixtures") — token bodies and the events log are the only outputs.

## See also

- [scope-resolution.md](scope-resolution.md) L22-28 — the dedup rule.
- [scope-resolution.md](scope-resolution.md) L35-37 — dynamic-scope resolution under `Feature.ORGANIZATION`.
- [scope-resolution.md](scope-resolution.md) L86-97 — pre-flight `isValidScope` rejection branch.
- [scope-resolution.md](scope-resolution.md) L156-159 — the silent-skip vs pre-flight-reject phrasing this file clarifies.
- [mapper-execution.md](mapper-execution.md) — per-surface toggle gating; same machinery applies to `oidc-organization-membership-mapper` as to any OIDC mapper.
- [inputs-and-outputs.md](inputs-and-outputs.md) — `JsonInclude.NON_NULL` and the "fires is not writes a non-null claim" rule.
- [`TokenManager.java:679-695`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L679-L695) — `tryResolveDynamicClientScope` call site (the resolution mechanism behind both wildcard and specific forms).
- [`TokenManager.java:705-762`](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L705-L762) — `isValidScope`, the pre-flight validator that decides §3.3's HTTP-400 case.

## Open items (candidates for future fixtures)

- **`addOrganizationId=true` / `addOrganizationAttributes=true` mapper config**: shape changes from `["alias"]` to a per-org object map. Not covered by current fixtures. Build a fixture with non-default flags to pin the alternative shape.
- **Source-code mechanism for the single-membership scope-claim duplicate** (§3.1 side-finding). The `.distinct()` semantics on `ClientScopeModel` instances need to be verified by reading `DefaultClientSessionContext.getScopeString` and tracing the upstream stream.
- **Userinfo and introspection surfaces** for the `organization` claim. The current adversarial fixtures only exercise access and ID tokens. Default mapper toggles include `introspection.token.claim=true`; userinfo falls back to `id.token.claim=true` (invariant 5). The shape parity claim in §1 is by analogy to invariants 7+9, not by direct fixture evidence on those surfaces.
