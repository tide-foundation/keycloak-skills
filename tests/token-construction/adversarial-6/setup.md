# adversarial-6 — alias-qualifier dynamic `organization` scope: specific / wildcard / nonexistent

## The seam

The target skill (`keycloak-token-construction`) is essentially
**silent on the dynamic-scope alias-qualifier mechanism** for the
built-in `organization` client scope. Its only references to
organisations are three short paragraphs in
`references/scope-resolution.md`:

- **L22-28** — the dedup rule: drop a default-attached scope whose
  `name + ":"` prefix appears in `scopeParam` AND which carries an
  `OrganizationMembershipMapper`. (Filters out the static
  `organization` scope when a dynamic `organization:<alias>` request
  is present.)
- **L35-37** — `tryResolveDynamicClientScope`: a per-request
  best-effort resolution that turns a non-static name in `scopeParam`
  into a synthetic dynamic scope (when `Feature.ORGANIZATION` is
  enabled).
- **L86-97** — pre-flight `isValidScope` rejection branch
  (`OAuthErrorException.INVALID_SCOPE` 400 / `CLIENT_LOGIN_ERROR`
  WARN; no token, no clientSessionCtx, no mappers).

What the skill **does not** say:

- How `tryResolveDynamicClientScope` actually resolves
  `organization:<alias>` — does it narrow the membership set to just
  that alias? Does it succeed if the alias doesn't match any org?
- Whether `organization:*` is special-cased (and if so, how it
  expands).
- Whether the pre-flight `isValidScope` (per L86-97) considers a
  dynamic-scope token whose alias does not match any organisation
  to be **valid** (because the static `organization` scope is in the
  client's defaults and the alias-qualifier is a syntactic suffix)
  or **invalid** (because no organisation with that alias exists).

This fixture probes those three sub-cases in **one realm, one user,
one client, three requests**, varying only `scope`:

1. `scope=openid organization:acme` (a specific real alias, user
   member of two orgs `acme` + `globex`).
2. `scope=openid organization:*` (the wildcard).
3. `scope=openid organization:nonexistent` (a syntactically-valid
   alias name that is NOT a real organisation in the realm).

Cross-cutting questions per request:

- **`organization` claim value**: `["acme"]`? both `["acme",
  "globex"]` / `["globex", "acme"]`? `absent`?
- **Literal `scope` claim string**: does the static `organization`
  default-scope (dedup rule L22-28) survive when the dynamic
  counterpart is requested? Does the literal string contain
  `organization:acme` / `organization:*` / `organization:nonexistent`?
- **For request 3 specifically**: does Keycloak return HTTP
  4xx INVALID_SCOPE pre-flight, or silently skip the unresolvable
  token and mint a token successfully with `organization` claim
  absent?

Pre-mint hypothesis (NOT shared with the Predictor): adv-5's
out-of-band probes (surprises.md §1) observed:

- `scope=openid organization:<alias>` → `organization: ["<alias>"]`,
  scope claim contains `organization:<alias>` (not bare
  `organization`).
- `scope=openid organization:*` → `organization` claim contains all
  memberships in insertion-order, scope claim contains
  `organization:*`.

That gives builder-side priors for requests 1 and 2 (specific
narrowing, and wildcard insertion-order behaviour). Request 3's
behaviour is *not* covered by adv-5's probes — that's the seam's
fresh discrimination point. The Predictor sees neither adv-4's nor
adv-5's surprises/setup files.

Stated invariants invoked / probed by this fixture:

- **Invariant 2** — `scope` claim composition. For each request,
  what scopes end up in the literal `scope` claim? Does the dedup
  rule (L22-28) drop the static `organization` so the claim has
  ONLY the dynamic qualifier? Or do both coexist?
- **Invariant 7** — ID-token base claims sourced from transformed
  access token. The `organization` claim shape (and the literal
  `scope` claim — actually `scope` is access-only here per adv-5)
  should be consistent between access and ID surfaces.
- **Invariant 10** — mapper sort tie / HashSet iteration order.
  Used as the hedge anchor for the wildcard case if the determinism
  check shows volatile ordering. Adv-5 already observed
  insertion-order-stable across 5 mints for `organization:*` with
  N=2; this fixture confirms with another 2 mints under the same
  setup with a different insertion order (acme-then-globex this
  time, instead of zeta-then-acme).
- **Invariant 11** — NON_NULL drops null claims. Relevant for
  request 3 if the dynamic-scope token attaches but the mapper
  returns nothing because the alias doesn't match a membership.
- **scope-resolution.md L86-97** — pre-flight INVALID_SCOPE. Relevant
  for request 3: does this branch fire, or is the dynamic-scope
  path more permissive?

## Realm / client / scope / mapper / user configuration

Realm: `adv-6` (fresh; doesn't collide with `master`, `adv-1`,
`adv-2`, `adv-3`, `adv-4`, `adv-5`, `myrealm`, `orgtest`).

Realm-level `organizationsEnabled=true` (toggled AFTER realm
creation per adv-4 surprise §2 — server-level `ORGANIZATION`
feature is enabled, but realm-level toggle defaults to false).

Client: `adv6-client`
- Confidential (`publicClient=false`), secret
  `adv6-secret-deadbeef`.
- `directAccessGrantsEnabled=true` — for ROPC password grant.
- `serviceAccountsEnabled=false`, `standardFlowEnabled=false`,
  `implicitFlowEnabled=false` — out of scope.
- `fullScopeAllowed=false` — deterministic scope governance per
  invariant 6.
- `defaultClientScopes`: Keycloak's OIDC built-ins (`web-origins`,
  `acr`, `profile`, `roles`, `basic`, `email`) PLUS the realm's
  built-in `organization` client scope as a **default** (so both
  static and dynamic resolution paths are active and the dedup rule
  L22-28 has a candidate to drop).
- `optionalClientScopes`: Keycloak defaults minus `organization`
  (which is moved to default).
- No custom protocol mappers. The OOTB
  `oidc-organization-membership-mapper` baked into the built-in
  `organization` scope is the only thing producing the claim.

Organisations (two, both with the test user as a member):

- `acme` — alias `acme`, name `Acme Corp`, domain `acme.test`.
  **Created FIRST** in chronological insertion order. (Insertion
  order = alphabetical here, so the order-versus-alphabetical
  discrimination is moot for this realm — the adv-5 fixture already
  used `zeta` to disambiguate. Here the wildcard question is
  primarily a *consistency check* on adv-5's insertion-order
  finding, not a fresh discrimination.)
- `globex` — alias `globex`, name `Globex Inc`, domain
  `globex.test`. Created SECOND.

User: `adv6-multimember`
- Username `adv6-multimember`, password `password`, `enabled=true`,
  `emailVerified=true`, `firstName=Adv6`,
  `lastName=Multimember`,
  `email=adv6-multimember@example.invalid`.
- Why first/last/email populated: required for password grant to
  clear `verify-profile` even with `requiredActions=[]`.
- Membership added to `acme` FIRST, then `globex` SECOND. UNMANAGED
  membership type.

## The three requests

All requests share the same client + user + grant; only `scope`
varies. Captured form bodies live in `request-specific.json`,
`request-wildcard.json`, `request-nonexistent.json`.

### Request 1 — specific alias (`organization:acme`)

```
POST /realms/adv-6/protocol/openid-connect/token
grant_type=password
client_id=adv6-client
client_secret=adv6-secret-deadbeef
username=adv6-multimember
password=password
scope=openid organization:acme
```

### Request 2 — wildcard (`organization:*`)

```
... same as above, with
scope=openid organization:*
```

### Request 3 — nonexistent alias (`organization:nonexistent`)

```
... same as above, with
scope=openid organization:nonexistent
```

## Plausible outputs (the trap menu)

This is the single canonical trap menu shared across this file and
`prediction-target.md`. The Predictor will see it via the latter.

### For request 1 (specific real alias `organization:acme`)

The candidate space is the cartesian of `organization` claim shape
× literal `scope` claim composition. Numbered options:

1a. **`organization: ["acme"]`** — only the requested alias. Narrows
    to the alias-qualified request.
1b. **`organization: ["acme", "globex"]`** or
    **`["globex", "acme"]`** — all memberships regardless of
    qualifier.
1c. **`organization: absent`** — the dynamic-scope token doesn't
    produce a claim; mapper sees nothing.
1d. **HTTP 4xx** — pre-flight rejects `organization:acme` as not a
    registered client scope.

1-scope-A. Literal `scope` claim contains **only**
    `organization:acme` (static `organization` dedup'd out per
    L22-28).
1-scope-B. Literal `scope` claim contains **both** bare
    `organization` AND `organization:acme` (dedup rule didn't
    fire, or applies differently than the skill describes).
1-scope-C. Literal `scope` claim contains **only** bare
    `organization` (the dynamic qualifier is consumed but not
    emitted in the claim).
1-scope-D. Literal `scope` claim contains `organization:acme`
    twice (synthetic duplication, c.f. adv-4 §3 finding).

### For request 2 (wildcard `organization:*`)

2a. **`organization: ["acme", "globex"]`** — both memberships,
    alphabetical order. Sub-question is order.
2b. **`organization: ["globex", "acme"]`** — both memberships,
    reverse-alphabetical / insertion-reverse. (Insertion order
    here is acme-then-globex, which coincides with alphabetical.
    A `globex`-first result would indicate something other than
    insertion order.)
2c. **`organization: ["acme"]` or `["globex"]`** — wildcard
    auto-picks one of the memberships.
2d. **`organization: absent`** — wildcard doesn't resolve to any
    memberships.
2e. **HTTP 4xx** — `organization:*` rejected as an unknown
    dynamic scope name.
2f. **Per-mint non-deterministic order on the same set
    (`["acme", "globex"]` vs `["globex", "acme"]` across mints)**
    — the invariant-10 hedge anchor if the determinism check shows
    it.

2-scope-A. Literal `scope` contains `organization:*` only.
2-scope-B. Literal `scope` contains both `organization` and
    `organization:*`.
2-scope-C. Literal `scope` contains bare `organization` only.
2-scope-D. Wildcard `:*` is escaped / encoded / dropped from the
    scope claim, leaving just `organization` or just nothing.

### For request 3 (nonexistent alias `organization:nonexistent`)

3a. **HTTP 400 with `error=invalid_scope`** — pre-flight L86-97
    rejects. No token, no claims. (Most consistent with the skill
    text: `tryResolveDynamicClientScope` returns null for
    unresolvable names, candidate-set is unchanged, then
    `isValidScope` rejects the unknown token name.)
3b. **HTTP 200, token minted, `organization` absent** — pre-flight
    accepts the syntactically-valid dynamic-scope token (because
    the `organization:` prefix matches a registered scope) but the
    runtime mapper produces nothing because no membership matches.
3c. **HTTP 200, token minted, `organization` claim contains the
    bogus alias verbatim (`["nonexistent"]`)** — mapper echoes the
    requested alias without verifying membership.
3d. **HTTP 200, token minted, `organization` contains all
    memberships** — the unresolvable alias falls back to "give them
    all".
3e. **HTTP 4xx, different error code** (e.g. `invalid_request`).

3-scope-A. `scope` claim absent (no token at all).
3-scope-B. `scope` claim present, contains
    `organization:nonexistent`.
3-scope-C. `scope` claim present, does NOT contain the bogus
    qualifier (it was silently dropped).
3-scope-D. `scope` claim present, contains bare `organization`
    only.

The trap menu is intentionally large. The minimum specificity to
pass (below) compresses it to a per-request commitment shape that's
graded compactly.

### Pre-mint best guesses (NOT in `prediction-target.md`)

Internal-only:

- Request 1: claim `["acme"]`, scope claim **A** (only
  `organization:acme`, static dropped by dedup) — consistent with
  adv-5 surprises §1 and skill L22-28.
- Request 2: claim `["acme", "globex"]` (insertion order, which
  here coincides with alphabetical), scope claim **A** (only
  `organization:*`).
- Request 3: HTTP 400 INVALID_SCOPE (option 3a). Rationale: skill
  L86-97 says pre-flight rejects unknown scope tokens, and a
  `tryResolveDynamicClientScope` that returns null for a no-match
  alias plus an `isValidScope` that doesn't special-case the
  `organization:` prefix produces a clean rejection. But option 3b
  (silent skip with absent claim) is also plausible if the
  dynamic-scope resolver is more permissive than the skill text
  implies.

These are pre-mint commitments; if wrong, that's the seam paying
off and the surprises.md will document the actual mechanism.

## Minimum specificity to pass

For each of the three requests, the Predictor must commit:

1. For requests 1 and 2:
   - The `organization` claim exact JSON value on access AND ID
     token (or `absent`), spelled exactly.
   - The literal `scope` claim string on the access token, exact.
   - For request 2: order commitment OR a clean invariant-10
     hedge with citation explaining why the order is non-
     derivable.

2. For request 3:
   - Whether the request succeeds (mint) or fails (HTTP 4xx).
   - If fails: HTTP status code and the `error=` value.
   - If succeeds: same shape as requests 1 and 2.

Hedges-without-citation are not predictions. Hedges with a clean
citation to a specific SKILL.md invariant or references/ passage
that explicitly admits the hedge ARE acceptable per the verdict
rubric (`fail-by-design` if the skill correctly hedges; `pass` if
the commitment is right; `fail-skill-gap` if the commitment is
wrong AND the trap menu enumerates the actual outcome).

## Determinism check plan

Strip set: `iat, exp, auth_time, session_state, sid, nbf`, and the
UUID portion of `jti` after the colon. Plus `at_hash` on ID tokens
(derived from the access-token signature).

The `organization` claim and the literal `scope` claim are NOT in
the strip set. If two mints of the same request produce different
values for either, the fixture is non-deterministic and the seam
must be redesigned.

For request 3 specifically: the determinism check is on the HTTP
response. Two requests, same form body, must produce identical
status codes and identical error codes (if applicable). Body text
beyond the JSON `error_description` may legitimately vary (Keycloak
sometimes includes trace IDs) and is stripped before comparison.

Each request is minted twice back-to-back. All six mints (3 × 2)
get bracketed logs. The "scoring" copies go in `actual-*.json`
files; mint-2 copies are kept as `*-mint2.json` companions outside
the public artefact set.

## Resolution after capture

Captured tokens at `actual-token-specific.json`,
`actual-id-token-specific.json`, `actual-token-wildcard.json`,
`actual-id-token-wildcard.json`. For request 3, the request
failed pre-flight; the full HTTP response (status + body) is
captured in `actual-response-nonexistent.json`. Mint-2 companions
for determinism are written alongside with `-mint2` suffixes
(`actual-token-specific-mint2.json`, etc; same forbidden-files
treatment for the predictor). Logs at `log-specific.txt`,
`log-wildcard.txt`, `log-nonexistent.txt` plus `-mint2` companions.
Surprises in `surprises.md`.

Headline observations:

- **Request 1 (specific `organization:acme`)**: HTTP 200.
  `organization: ["acme"]` on both access AND ID tokens.
  Literal `scope` claim multiset: `{openid, email, profile,
  organization:acme}` (4 tokens; bare `organization` NOT
  present — dedup rule L22-28 fired). Exact string varies across
  mints — mint 1: `"openid organization:acme email profile"`;
  mint 2: `"openid email organization:acme profile"`. **Trap
  index: 1a + 1-scope-A.**

- **Request 2 (wildcard `organization:*`)**: HTTP 200.
  `organization: ["globex", "acme"]` on both access AND ID
  tokens — note the order is `globex` FIRST despite `acme` being
  the user's first membership. Stable across 7 back-to-back mints
  (2 official + 5 confirmation). Literal `scope` claim multiset:
  `{openid, email, profile, organization:*}` (4 tokens; bare
  `organization` NOT present — dedup also fired on the
  wildcard). Exact string varies across mints. **Trap index:
  2b + 2-scope-A.**

- **Request 3 (nonexistent `organization:nonexistent`)**: HTTP
  400 with body
  `{"error":"invalid_scope","error_description":"Invalid scopes:
  openid organization:nonexistent"}`. No token, no claims.
  Keycloak log shows `LOGIN_ERROR` WARN with
  `error="invalid_request"` (note: event-log `error` field
  differs from HTTP-body `error` field — a separate observation
  in `surprises.md` §5). **Trap index: 3a + 3-scope-A.**

- **Determinism check**: clean on all three seam targets.
  `organization` claim identical across mints in both surfaces.
  `scope` claim **multiset** identical; **string order** varies
  across mints (HashSet-iteration shaped; documented in
  `surprises.md` §2 and §6). Request 3 HTTP response bytewise
  identical between mints.

Pre-mint trap menu had all three actual outcomes enumerated. No
5th trap had to be added. The order observation in request 2
(`globex`-first despite `acme`-first insertion) refutes adv-5's
"insertion-order" hypothesis and is one of the secondary signals
this fixture produces; see `surprises.md` §1.

Verdict decision deferred to the diff phase by the Predictor's
output.
