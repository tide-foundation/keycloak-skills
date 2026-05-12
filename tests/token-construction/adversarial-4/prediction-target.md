# Prediction target

Two token requests are issued against the same client `adv4-client` in
realm `adv-4`, both via the Resource Owner Password Credentials grant,
both with `scope=openid organization`. The only variable is the
username:

- `adv4-member` is a member of exactly one organisation (`acme`). A
  second organisation (`globex`) exists in the realm but `adv4-member`
  is NOT a member of it.
- `adv4-nonmember` is a member of **zero** organisations.

The realm's built-in `organization` client scope is attached as a
**default** scope on `adv4-client`, so the scope is included
automatically; `scope=openid organization` is requested explicitly
for clarity. The client has `fullScopeAllowed=false`. The
`oidc-organization-membership-mapper` baked into the built-in
`organization` scope is the only protocol mapper producing the
`organization` claim.

For **each of the two tokens** (member's access token, member's ID
token, non-member's access token, non-member's ID token), the skill
must commit to:

1. **The exact JSON shape and value of the `organization` claim.**
   Pick one entry from the trap menu below for each of the four
   surfaces. Where the entry says "list orgs" / "object keyed by
   alias" / etc., commit to the specific aliases that appear (e.g.
   `["acme"]` is a complete commitment; `<an array of strings>` is
   not).

2. **The value of the `scope` claim** — committed as the **set** of
   scope names that appear (order-insensitive). Include or exclude
   `openid` per invariant 2 of the target skill.

## Required output shape

```json
{
  "member": {
    "access_token_organization_claim_trap_index": "<integer 1..N>",
    "access_token_organization_claim_value": <the exact JSON value, or null if shape #1 (absent)>,
    "id_token_organization_claim_trap_index": "<integer 1..N>",
    "id_token_organization_claim_value": <the exact JSON value, or null if shape #1 (absent)>,
    "access_token_scope_claim_set": ["<scope>", "..."],
    "id_token_scope_claim_set_or_absent": ["<scope>", "..."]
  },
  "nonmember": {
    "access_token_organization_claim_trap_index": "<integer 1..N>",
    "access_token_organization_claim_value": <the exact JSON value, or null if shape #1 (absent)>,
    "id_token_organization_claim_trap_index": "<integer 1..N>",
    "id_token_organization_claim_value": <the exact JSON value, or null if shape #1 (absent)>,
    "access_token_scope_claim_set": ["<scope>", "..."],
    "id_token_scope_claim_set_or_absent": ["<scope>", "..."]
  }
}
```

Plus a `reasoning` field per commitment citing the SKILL.md /
references/ passages the commitment is sourced from.

## What does NOT count as a prediction

- "depends on the mapper configuration" without resolving which mapper
  is producing the claim and what its toggles are (the
  `organization` client scope and its
  `oidc-organization-membership-mapper` are visible in
  `realm-config.json`).
- "either an array or an object" without picking one.
- "the claim is present in some form" without picking a wire shape
  from the trap menu.
- Refusing to commit on the non-member case because "membership is
  empty" — invariant 11 (NON_NULL drops null claims) plus invariant 2
  jointly constrain the answer: the claim is either dropped (NON_NULL
  on a null/empty mapper output) or present as an explicitly-empty
  container. Pick one.

If the skill mandates a hedge for one of the commitments, the
prediction must cite the specific invariant or reference passage that
requires the hedge, and explain why that passage applies here.

## Plausible outputs (the trap menu)

For the `organization` claim on the member's tokens, the seven
candidate wire shapes are enumerated below. The non-member's tokens
draw from a smaller subset (only shapes that are valid for an
empty-membership user).

Each shape is numbered; commit by index per surface.

1. **Absent** — the `organization` claim does not appear in the
   payload at all. Would be predicted by a reader who applied
   invariant 11 (NON_NULL) to a mapper that emitted null because the
   user has no organisation memberships. For the **member**, this is
   wrong if the mapper emits any non-null value — and the skill's
   only explicit organisation mention (scope-resolution.md L74-77)
   strongly suggests the claim is *present* for a member. For the
   **non-member**, this is the most-likely-correct shape.

2. **Empty array `[]`** — would be predicted by a reader who assumed
   the mapper always emits an array even for empty membership. For
   the member, wrong. For the non-member, plausible if the mapper
   short-circuits its NON_NULL behaviour by emitting an explicit
   empty container.

3. **Empty object `{}`** — same as #2 but with the object shape. For
   the member, wrong (unless the object shape is the wire format and
   the empty-membership case still emits an empty object). For the
   non-member, plausible.

4. **Array of alias strings `["acme"]`** — would be predicted by a
   reader who assumed the mapper emits a flat list of org aliases.
   Compact, symmetric with how Keycloak emits `roles` and `groups`
   claims.

5. **Object keyed by alias with empty value bodies, e.g.
   `{"acme": {}}`** — would be predicted by a reader who assumed
   Keycloak namespaces org claims by alias for forward-compatibility
   with per-org metadata, but elides metadata by default.

6. **Object keyed by alias with non-empty value bodies, e.g.
   `{"acme": {"id": "<uuid>", "name": "Acme Corp", ...}}`** — would be
   predicted by a reader who assumed the mapper inlines the full org
   representation under each alias.

7. **Array of org-representation objects, e.g.
   `[{"alias": "acme", "id": "...", "name": "Acme Corp", ...}]`** —
   would be predicted by a reader who assumed parity with the admin
   REST API's GET `/organizations` response shape.

8. **The realm-wide list of all organisations, regardless of
   membership** — e.g. `["acme", "globex"]` for the member AND the
   non-member alike. Would be predicted by a reader who confused the
   mapper with an "available orgs" introspection. The presence of the
   `globex` control specifically defeats this misread.

9. **Different shape between access token and ID token** — e.g. the
   access token has shape #4 but the ID token has shape #5. Would be
   predicted by a reader who assumed Keycloak applies different
   serialisers per surface. Per invariant 7, the ID token's base
   claims are sourced from the transformed access token, so different
   shapes per surface would require a per-surface mapper toggle that
   the OOTB mapper does not expose. Commit to "same shape per
   surface" unless one of the surfaces drops the claim entirely
   (which would itself be one of shapes 1-8).

10. **Non-deterministic across mints** — would invalidate the fixture
    and is checked explicitly by the builder's determinism step
    (Step 6 of `seam-design.md`).

The pre-mint expectation is that ONE of shapes 1-8 is the truth for
each surface. The Predictor must commit by index per surface.

## Minimum specificity to pass

- Trap index must be 1..9 (10 only if the determinism check actually
  fails, which the predictor cannot observe — so 10 is essentially
  off-menu for the predictor).
- If the trap index implies a non-trivial value (shapes 2-8), the
  `*_organization_claim_value` field must contain the exact JSON
  value, with the alias `acme` spelled correctly and any per-org
  metadata fields named exactly as Keycloak emits them.
- The `*_scope_claim_set` field must list every scope name the
  predictor expects in the `scope` claim, order-insensitive. Include
  `openid` only if invariant 2 instructs.

## Sample pass shapes

Predictor commits trap index `4` for the member's access token and
trap index `1` for the non-member's access token:

```json
{
  "member": {
    "access_token_organization_claim_trap_index": 4,
    "access_token_organization_claim_value": ["acme"]
  },
  "nonmember": {
    "access_token_organization_claim_trap_index": 1,
    "access_token_organization_claim_value": null
  }
}
```

That's a complete pass shape (modulo the ID-token mirrors and the
scope claim sets, which the predictor must also fill).
