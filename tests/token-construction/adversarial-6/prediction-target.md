# Prediction target — adversarial-6

This fixture asks three questions, one per request. See
`realm-config.json`, `realm-organizations.json`,
`request-specific.json`, `request-wildcard.json`,
`request-nonexistent.json` as inputs.

The three requests differ ONLY in the `scope` form parameter:

- `request-specific.json` — `scope=openid organization:acme`
- `request-wildcard.json` — `scope=openid organization:*`
- `request-nonexistent.json` — `scope=openid organization:nonexistent`

The same client, same user, same password grant for all three. The
user is a member of TWO organisations in `realm-organizations.json`:
`acme` (insertion-order first) and `globex` (insertion-order
second). Both are real organisations in the realm.
`organization:nonexistent` is intentionally NOT a real organisation
in the realm.

For each request, the skill must commit to the shapes below.
Hedges of the form "depends on `tryResolveDynamicClientScope`
internals," "either narrowing or expanding," "implementation-
defined", "I don't know the alias-qualifier semantics" do not
count as predictions UNLESS they cite a specific passage in the
target skill that mandates the hedge and explain why that passage
applies here.

## Required output shape

The shape mirrors `tests/token-construction/adversarial-1/prediction.json`
with one top-level object per request. Use this shape:

```json
{
  "fixture": "adversarial-6",
  "request_specific": {
    "outcome": "success|http_4xx",
    "if_http_4xx_status_code": "<integer or null>",
    "if_http_4xx_error_code": "<string or null>",
    "access_token_organization_claim": "<exact JSON value or 'absent' or 'n/a-rejected'>",
    "id_token_organization_claim":     "<exact JSON value or 'absent' or 'n/a-rejected'>",
    "access_token_scope_claim_string": "<exact string or 'absent' or 'n/a-rejected'>",
    "trap_index_organization": "<one of 1a..1d>",
    "trap_index_scope":        "<one of 1-scope-A..1-scope-D>",
    "reasoning": "...",
    "skill_passages_invoked": ["..."]
  },
  "request_wildcard": {
    "outcome": "success|http_4xx",
    "if_http_4xx_status_code": "<integer or null>",
    "if_http_4xx_error_code": "<string or null>",
    "access_token_organization_claim": "<exact JSON value or 'absent' or 'n/a-rejected'>",
    "id_token_organization_claim":     "<exact JSON value or 'absent' or 'n/a-rejected'>",
    "access_token_scope_claim_string": "<exact string or 'absent' or 'n/a-rejected'>",
    "trap_index_organization": "<one of 2a..2f>",
    "trap_index_scope":        "<one of 2-scope-A..2-scope-D>",
    "wildcard_order_commitment": "<exact order, or 'hedge-with-citation' + citation>",
    "reasoning": "...",
    "skill_passages_invoked": ["..."]
  },
  "request_nonexistent": {
    "outcome": "success|http_4xx",
    "if_http_4xx_status_code": "<integer or null>",
    "if_http_4xx_error_code": "<string or null>",
    "access_token_organization_claim": "<exact JSON value or 'absent' or 'n/a-rejected'>",
    "id_token_organization_claim":     "<exact JSON value or 'absent' or 'n/a-rejected'>",
    "access_token_scope_claim_string": "<exact string or 'absent' or 'n/a-rejected'>",
    "trap_index_outcome": "<one of 3a..3e>",
    "trap_index_scope":   "<one of 3-scope-A..3-scope-D>",
    "reasoning": "...",
    "skill_passages_invoked": ["..."]
  },
  "fixture_target_compliance_note": "...",
  "shapes_ruled_out_by_skill": ["..."]
}
```

Per-field semantics:

- `outcome`: `success` if the request returns HTTP 200 with an
  `access_token`; `http_4xx` if it returns any 4xx.
- `if_http_4xx_status_code` / `if_http_4xx_error_code`: the
  integer HTTP status (e.g., 400) and the OAuth2 `error` field
  value (e.g., `invalid_scope`). Both null if `outcome == success`.
- `access_token_organization_claim` / `id_token_organization_claim`:
  the exact JSON value of the `organization` claim on the
  respective token, as it would appear in
  `jq -S .organization < decoded-payload.json`. Use the literal
  string `"absent"` (without JSON-array brackets) if the claim is
  missing from the payload entirely. Use `"n/a-rejected"` for
  request 3 if the request was rejected with 4xx (no token
  exists). For an array claim, write the JSON array verbatim
  (e.g., `["acme"]` or `["globex", "acme"]`).
- `access_token_scope_claim_string`: the exact value of the
  `scope` claim on the access token, e.g.,
  `"openid profile email organization:acme"`. Order and spacing
  matters. `"absent"` if missing. `"n/a-rejected"` if no token.
- `trap_index_*`: a single index from the per-request trap menu
  below.
- `wildcard_order_commitment` (request 2 only): the exact order
  (`["acme", "globex"]` or `["globex", "acme"]` etc) OR
  `hedge-with-citation` followed by the citation. Hedging
  without citation is not admissible per the verdict rubric.
- `reasoning`: 1-3 sentences per commitment, citing target skill
  passages.
- `skill_passages_invoked`: array of citations (e.g.,
  `"scope-resolution.md L22-28"`).
- `fixture_target_compliance_note`: per-fixture self-assessment of
  which forbidden files were checked-not-read, which inputs were
  consulted.
- `shapes_ruled_out_by_skill`: list of trap indices the skill text
  rules out (so the diff can score how many were correctly
  eliminated).

## What does NOT count as a prediction

- "Hedge: depends on `tryResolveDynamicClientScope`" without
  citing a SKILL.md/references passage that explicitly admits the
  hedge.
- For request 2: "either alphabetical or insertion-order" without
  picking one OR invoking invariant 10 + a contract rationale.
- For request 3: refusing to commit on success vs. 4xx because the
  skill is "silent on dynamic-scope error semantics" — the skill
  explicitly does cover pre-flight INVALID_SCOPE in
  `scope-resolution.md L86-97`. A non-commitment on outcome is a
  skill-gap claim that must be backed by specifically pointing to
  a missing passage.
- A commitment that does not enumerate trap indices is not
  scoreable.

## Plausible outputs (the trap menu)

This trap menu is the predictor's view; the builder has the same
trap menu in `setup.md`. Each request has its own set of indices.

### Request 1 — `scope=openid organization:acme`

`organization` claim shape:

- **1a**: `["acme"]` only. Narrowing to the alias-qualified
  request.
- **1b**: `["acme", "globex"]` or `["globex", "acme"]` — all
  memberships regardless of qualifier.
- **1c**: `absent`. The dynamic-scope token attaches but produces
  no claim.
- **1d**: HTTP 4xx — pre-flight rejects.

`scope` claim composition:

- **1-scope-A**: Contains `organization:acme` only (static
  `organization` dedup'd out per L22-28).
- **1-scope-B**: Contains both `organization` AND
  `organization:acme`.
- **1-scope-C**: Contains bare `organization` only.
- **1-scope-D**: Contains `organization:acme` twice (synthetic
  duplication).

### Request 2 — `scope=openid organization:*`

`organization` claim shape:

- **2a**: `["acme", "globex"]` — both memberships, alphabetical
  order.
- **2b**: `["globex", "acme"]` — both memberships,
  reverse-alphabetical.
- **2c**: `["acme"]` or `["globex"]` — wildcard auto-picks one.
- **2d**: `absent`.
- **2e**: HTTP 4xx — wildcard rejected.
- **2f**: Non-deterministic across mints on order (same set, different
  order). Invariant-10 hedge anchor if applicable.

`scope` claim composition:

- **2-scope-A**: Contains `organization:*` only.
- **2-scope-B**: Contains both `organization` and
  `organization:*`.
- **2-scope-C**: Contains bare `organization` only.
- **2-scope-D**: Wildcard `:*` is escaped/encoded/dropped from
  the scope claim.

### Request 3 — `scope=openid organization:nonexistent`

Outcome:

- **3a**: HTTP 400 with `error=invalid_scope` (pre-flight L86-97
  rejection). No token, no claims.
- **3b**: HTTP 200, token minted, `organization` absent.
- **3c**: HTTP 200, token minted, `organization` contains
  `["nonexistent"]` (mapper echoes the alias).
- **3d**: HTTP 200, token minted, `organization` contains all
  memberships (fallback to wildcard-style expansion).
- **3e**: HTTP 4xx with a different `error` code.

`scope` claim (if minted):

- **3-scope-A**: `scope` claim absent (no token).
- **3-scope-B**: `scope` claim present, contains
  `organization:nonexistent`.
- **3-scope-C**: `scope` claim present, bogus qualifier silently
  dropped.
- **3-scope-D**: `scope` claim present, contains bare
  `organization` only.

## Minimum specificity to pass

A passing prediction requires per-request:

- A trap index for the `organization` claim shape (or outcome for
  request 3).
- A trap index for the `scope` claim composition (or 3-scope-A if
  the request was rejected).
- The exact JSON value of the `organization` claim filled in
  (or `absent` / `n/a-rejected`).
- The exact `scope` claim string filled in
  (or `absent` / `n/a-rejected`).
- For request 2 only: a commitment on order, OR an invariant-10
  hedge with citation.
- A `reasoning` field per commitment citing the SKILL.md /
  references/ passage(s) consulted.
- The `skill_passages_invoked` array populated.

A passing prediction may legitimately hedge ONLY if the hedge
cites a specific passage in the target skill that admits the
hedge. The verdict for a citation-backed hedge that matches the
ground truth is `pass`; for a citation-backed hedge whose
ground-truth is contract-derivable, `fail-skill-gap`.
