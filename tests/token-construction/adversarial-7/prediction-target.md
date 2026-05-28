# Prediction target — adversarial-7 (`oidc-hardcoded-role-mapper`)

One token request (`request.json`, ROPC `password` grant, `scope=openid`)
is issued against `adv7-client` in realm `adv-7`. It yields an **access
token** and an **ID token**. The access token is then replayed against the
**userinfo** endpoint (`request-userinfo.json`). All configuration is in
`realm-config.json`.

`adv7-client` has `fullScopeAllowed=false` and carries two client-level
protocol mappers of type `oidc-hardcoded-role-mapper`:

- `hc-realm-role` → `role = "unassigned-realm-role"` (a realm role that
  exists in `adv-7` but is **not** assigned to `adv7-user`).
- `hc-client-role` → `role = "adv7-resource.resource-reader"` (a client
  role on the separate client `adv7-resource`, **not** assigned to the
  user).

`adv7-user` holds only the realm defaults (`default-roles-adv-7`,
`offline_access`, `uma_authorization`) and no client roles. Inspect the
`roles` client-scope mapper toggles in `realm-config.json` carefully —
the `realm roles` and `client roles` mappers do **not** carry identical
surface toggles in this realm.

The skill must commit, with concrete `present`/`absent` values and exact
role strings, to **all** of the following. No item may be hedged unless a
named SKILL.md invariant or `references/` passage mandates the hedge.

## Committed questions

**Access token**
- `at.realm_role` — does `realm_access.roles` contain `"unassigned-realm-role"`? (`present`/`absent`)
- `at.client_role` — does `resource_access["adv7-resource"].roles` contain `"resource-reader"`? (`present`/`absent`)
- `at.aud_resource` — does `aud` contain `"adv7-resource"`? (`present`/`absent`)

**ID token**
- `idt.realm_role` — does `realm_access.roles` contain `"unassigned-realm-role"`? (`present`/`absent`)
- `idt.client_role` — does `resource_access["adv7-resource"]` exist at all? (`present`/`absent`)
- `idt.aud_resource` — does `aud` contain `"adv7-resource"`? (`present`/`absent`)

**Userinfo**
- `ui.realm_role` — does `realm_access.roles` contain `"unassigned-realm-role"`? (`present`/`absent`)
- `ui.client_role` — does `resource_access["adv7-resource"]` exist at all? (`present`/`absent`)

**Cross-cutting**
- `bypass_relevance` — given the user holds neither hardcoded role and
  `fullScopeAllowed=false`, are those facts `relevant` or `irrelevant`
  to whether the hardcoded roles appear? Commit to one word and justify
  from the mapper's source behaviour.

## Required output shape

```json
{
  "access_token": {
    "realm_role": "<present|absent>",
    "client_role": "<present|absent>",
    "aud_resource": "<present|absent>"
  },
  "id_token": {
    "realm_role": "<present|absent>",
    "client_role": "<present|absent>",
    "aud_resource": "<present|absent>"
  },
  "userinfo": {
    "realm_role": "<present|absent>",
    "client_role": "<present|absent>"
  },
  "bypass_relevance": "<relevant|irrelevant>",
  "reasoning": "<cite SKILL.md / references passages per commitment>",
  "shapes_ruled_out_by_skill": ["..."],
  "skill_passages_invoked": ["..."],
  "fixture_target_compliance_note": "..."
}
```

## What does NOT count as a prediction

- "depends on the surface toggle of the hardcoded-role mapper" without
  resolving it — the `oidc-hardcoded-role-mapper` config has no
  `*.token.claim` keys at all; the prediction must resolve what that
  means for dispatch rather than defaulting it.
- "either present or absent" for any item.
- "the hardcoded role may or may not surface depending on mapper order"
  — the relevant mapper priorities are fixed integers; resolve the order.
- Refusing to commit on the ID-token / userinfo items by appealing to
  invariant 7 (ID-token inheritance) without checking whether
  `realm_access`/`resource_access` are actually among the inherited
  fields.

## Plausible outputs (the trap menu)

Exactly one combination is correct; it will be confirmed by minting. The
others are misreads a vague reading would let through. (No entry here is
marked correct — that is recorded only in `setup.md`, which the predictor
must not read.)

1. **Everything `absent` on every surface.** The misread the seam is
   built to defeat: a reader who applies the surface-toggle pseudocode in
   `references/mapper-execution.md` literally to the hardcoded-role
   mapper, sees no `access.token.claim` / `id.token.claim` key in its
   config, evaluates `config["access.token.claim"] == "true"` → false,
   and concludes the mapper is skipped on every surface.

2. **Everything `absent` because the user lacks the roles and
   `fullScopeAllowed=false`.** A reader who assumes role-bearing claims
   are always the user's real roles intersected with the allowlist
   (invariant 6) and forgets that a hardcoded-role injection is not a
   real role mapping.

3. **All three hardcoded effects `present` on all three surfaces
   uniformly** (realm role, client role, and `adv7-resource` in `aud`
   present on access, ID, and userinfo alike). A reader who knows the
   hardcoded mapper fires unconditionally but treats "fired" as "claim on
   the wire on every surface," ignoring that the claim is actually
   written by the *consumer* role-list mappers whose per-surface toggles
   differ, and ignoring that the mapper does not implement the
   ID-token mapper interface.

4. **Realm role present everywhere, client role present everywhere, but
   `aud` does not contain `adv7-resource` on any surface.** A reader who
   gets the role claims right but does not connect the resolved
   client-role injection to the audience-resolve mapper.

5. **Access-token effects present; ID-token and userinfo effects all
   absent.** A reader who correctly defeats trap 1/2 for the access token
   but then over-applies "role claims aren't in the ID token / userinfo
   by default" without reading this realm's specific per-mapper toggles.

6. **Some other mixed combination** — fill in the exact per-surface,
   per-claim values.

## Minimum specificity to pass

Every field in the output shape must hold a concrete `present`/`absent`
(or `relevant`/`irrelevant`) value with no hedge, and `reasoning` must
cite the specific mechanism that routes a hardcoded role onto (or keeps
it off) each surface. A correct prediction must in particular resolve
(a) whether the hardcoded-role mapper's missing `*.token.claim` keys
suppress it, (b) which mapper actually writes the role claim and what
its per-surface toggles are in this realm, and (c) whether the user
actually holding the role matters.
