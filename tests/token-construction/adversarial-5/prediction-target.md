# Prediction target

One token request is issued against `adv5-client` in realm `adv-5`
via the Resource Owner Password Credentials grant with
`scope=openid organization`. The user `adv5-multimember` is a
member of **two** organisations in this realm:

- `zeta` — alias `zeta`, name `Zeta Industries`, domain `zeta.test`.
  This organisation was created first (HTTP 201 #1) and the user
  was added as a member first.
- `acme` — alias `acme`, name `Acme Corp`, domain `acme.test`. This
  organisation was created second and the user was added second.

These insertion-order facts are visible in `realm-organizations.json`
via the `members[].createdTimestamp` field (and the `_note` in that
file). The realm's built-in `organization` client scope is attached
as a **default** scope on `adv5-client`; the client has
`fullScopeAllowed=false`. The `oidc-organization-membership-mapper`
baked into the built-in `organization` scope is the only protocol
mapper producing the `organization` claim. Its config in the
realm-config export shows `multivalued: "true"`,
`jsonType.label: "String"`, `access.token.claim: "true"`,
`id.token.claim: "true"`, `introspection.token.claim: "true"`.

For the **access token** AND the **ID token** from this single
mint, the skill must commit to:

1. **The exact JSON value of the `organization` claim, including
   array order if the shape is an array.** Pick one entry from the
   trap menu below per surface. Where the entry requires concrete
   aliases, write them out (e.g. `["acme", "zeta"]` is a complete
   commitment; `<an array of strings>` is not).
2. **The literal `scope` claim string on the access token** —
   committed as the exact whitespace-separated string. The
   prediction must explicitly answer: does the substring
   `organization` appear in the `scope` claim string **once** or
   **twice** (or more)?
3. **The multiset of scope names** the predictor expects in the
   access token's `scope` claim — listed as an ordered or
   unordered multiset (per-name occurrence count), independent of
   the literal-string commitment in (2).

## Required output shape

```json
{
  "access_token": {
    "organization_claim_trap_index": "<integer 1..13>",
    "organization_claim_value": <the exact JSON value, or null if shape #1 (absent)>,
    "scope_claim_literal_string": "<exact whitespace-separated string>",
    "scope_claim_multiset": {"<scope_name>": "<integer occurrence count>", "...": "..."},
    "organization_in_scope_count": "<integer: 0, 1, 2, ...>"
  },
  "id_token": {
    "organization_claim_trap_index": "<integer 1..13>",
    "organization_claim_value": <the exact JSON value, or null if shape #1 (absent)>
  },
  "reasoning": {
    "organization_claim": "<which SKILL.md / references/ passages support the chosen shape and order>",
    "scope_claim": "<which invariant supports the scope-claim composition; explain the once-or-twice answer>"
  }
}
```

The `reasoning` field must cite the SKILL.md / references/
passage(s) the commitments are sourced from. If the skill does NOT
pin a particular dimension, the reasoning must say so explicitly
and (if hedging) name the invariant that authorises the hedge.

## What does NOT count as a prediction

- "depends on the mapper configuration" without resolving the
  toggles (the `organization` client scope and its
  `oidc-organization-membership-mapper` are fully visible in
  `realm-config.json` — read them).
- "either an array or an object" without picking one.
- "the claim is present in some form" without picking a wire shape
  from the trap menu.
- "the claim contains both aliases in some order" — partial
  commitment on set without a stance on order. The prediction must
  EITHER commit to a specific JSON array literal (e.g.
  `["acme", "zeta"]` or `["zeta", "acme"]`) OR pick trap-menu
  index #7 (hedge-with-invariant-10-citation) with a specific
  contract rationale. Saying "I'm not sure of the order" without
  citing why the skill text doesn't pin it is NOT a clean hedge.
- For (3): "scope contains `organization`" without saying once vs.
  twice. Even if your answer is "once is the only possibility,"
  state it explicitly.
- Refusing to commit on the `organization` claim because
  "Keycloak's mapper is undocumented" — the mapper's config (with
  `multivalued: "true"` and `jsonType.label: "String"`) is in the
  realm export; commit on the basis of those toggles plus the
  general rules SKILL.md gives for `multivalued` / `jsonType`.

If the skill mandates a hedge for one of the commitments, the
prediction must cite the specific invariant or reference passage
that requires the hedge, and explain why that passage applies here
while not applying to the contrast case (e.g. a single-membership
user with one alias).

## Plausible outputs (the trap menu)

For the `organization` claim, the candidate wire shapes are
enumerated below. Commit by index per surface (access token and
ID token).

1. **Absent.** Claim does not appear in the payload. Would be
   predicted by a reader who applied invariant 11 (NON_NULL) to a
   mapper that returns null in the multi-membership case. The
   mapper config shows `multivalued: "true"` so this would be
   surprising — but if the mapper logic only handles N=1 and
   collapses to null on N>1, this is the outcome.

2. **Empty array `[]`.** Would be predicted by a reader who
   assumed the mapper short-circuits on multi-membership and emits
   an explicitly-empty array.

3. **Single-alias array `["acme"]`.** Would be predicted by a
   reader who assumed the mapper picks the alphabetically-first
   alias when multiple memberships exist, ignoring the rest.

4. **Single-alias array `["zeta"]`.** Same as #3 but picking by
   insertion-order-first rather than alphabetical-first.

5. **Both aliases, alphabetical order: `["acme", "zeta"]`.** Would
   be predicted by a reader who assumed Keycloak sorts the
   multivalued container alphabetically (lexicographic on the alias
   string).

6. **Both aliases, insertion order: `["zeta", "acme"]`.** Would be
   predicted by a reader who assumed Keycloak preserves the
   chronological order in which the user was added to each
   organisation. Tip-off: `realm-organizations.json` shows the
   first-added membership for the user is `zeta`.

7. **Both aliases, JVM-iteration order — hedge with invariant 10
   citation.** Would be predicted by a reader who concluded the
   skill text does not pin the order of a `multivalued: "true"`
   organisation-membership claim, and therefore the order is
   contract-undefined the same way mapper-tie order is. The
   commitment in this case is **the set `{"acme", "zeta"}`** with
   an explicit "order is non-deterministic across mints; cf.
   invariant 10" annotation.

8. **Both aliases, object keyed by alias with empty bodies:
   `{"acme": {}, "zeta": {}}`.** Would be predicted by a reader
   who assumed Keycloak namespaces orgs by alias under an object
   container.

9. **Both aliases, object keyed by alias with non-empty bodies,
   e.g. `{"acme": {"id": "<uuid>", "name": "Acme Corp", ...},
   "zeta": {...}}`.** Would be predicted by a reader who assumed
   the OOTB mapper inlines the full org representation under each
   alias.

10. **Array of org-representation objects, e.g.
    `[{"alias": "acme", "id": "...", "name": "Acme Corp", ...},
    {"alias": "zeta", ...}]`.** Would be predicted by a reader who
    assumed parity with the admin REST API's GET `/organizations`
    response shape.

11. **Different shape between access token and ID token** — e.g.
    the access token has shape #5 but the ID token has shape #8.
    Per invariant 7, the ID token's base claims are sourced from
    the transformed access token, so this would require a per-
    surface mapper toggle that the OOTB mapper does not expose.

12. **Realm-wide list of all organisations regardless of
    membership** — e.g. the same shape as the correct one, but
    including organisations the user is NOT a member of. In this
    realm `adv5-multimember` IS a member of all organisations
    (both `zeta` and `acme`), so this trap is structurally
    indistinguishable from the correct shape unless an
    additional non-member org is added later — but it's enumerated
    so the predictor can rule it out by inspecting the membership
    list.

13. **Per-mint volatility on SET MEMBERSHIP (not just order).**
    Would invalidate the fixture and is checked by the builder's
    determinism step. The predictor cannot observe this directly
    and should not pick this index.

For the **`scope` claim** literal string and multiset, the
predictor's commitment is constrained by invariant 2 (the scope-
claim composition rule). The most plausible scope-name set is
`{openid, profile, organization, basic, email, roles, acr,
web-origins}` filtered by each scope's `include.in.token.scope`
attribute, then sorted by some Keycloak-internal rule. The
duplicate-organization question (once vs. twice) is its own
invariant-2-shaped commitment — the predictor should reason about
whether the static-default-scope attachment AND any dynamic-
resolution path for the `organization` scope could both
contribute the same scope name to the claim, and whether invariant
2's composition rule dedups.

## Minimum specificity to pass

- `organization_claim_trap_index` for access and ID tokens must be
  an integer 1..12 (13 is essentially off-menu for the predictor).
- If the chosen index implies a non-trivial JSON value, the
  `organization_claim_value` field must be that exact value with
  array order matching the chosen index. For #7, the value field
  may be the set unordered AND the prediction must explicitly
  annotate the hedge.
- `scope_claim_literal_string` must be the exact string the
  predictor expects (with whitespace).
- `scope_claim_multiset` must list every scope name expected with
  an integer count.
- `organization_in_scope_count` must be an integer; `1` and `2`
  are both plausible answers depending on how the predictor reads
  invariant 2's scope-resolution rules.

## Sample pass shape

Predictor commits trap index `5` for both access and ID tokens
(alphabetical-order shape), and commits scope-claim with
`organization` appearing once:

```json
{
  "access_token": {
    "organization_claim_trap_index": 5,
    "organization_claim_value": ["acme", "zeta"],
    "scope_claim_literal_string": "openid profile organization email",
    "scope_claim_multiset": {"openid": 1, "profile": 1, "organization": 1, "email": 1},
    "organization_in_scope_count": 1
  },
  "id_token": {
    "organization_claim_trap_index": 5,
    "organization_claim_value": ["acme", "zeta"]
  },
  "reasoning": {
    "organization_claim": "<cited passages...>",
    "scope_claim": "<invariant 2 reasoning...>"
  }
}
```

That's a complete pass shape — but the predictor's specific values
will depend on its read of the skill. The trap-menu index and the
value's array order MUST be consistent.
