# adversarial-5 — `organization` claim wire shape for multi-org membership (skill gap probe)

## The seam

The target skill (`keycloak-token-construction`) is **silent on the
wire shape of the `organization` claim**. The only references to
organisations are three short paragraphs in
`references/scope-resolution.md` about dedup of the `organization`
client scope and the static-vs-dynamic resolution path — nothing
about the mapper output, its JSON serialisation, or what happens
when a user is a member of more than one organisation.

This fixture probes the **gap** for multi-membership specifically.
The previous fixture (adversarial-4, NOT visible to the Predictor)
nailed the single-membership case at the alias-string-array shape
(`["acme"]`), but no fixture has yet asked: when a user belongs to
N>1 organisations, does the claim:

- emit BOTH aliases in a single multivalued array container (most
  likely, given the OOTB mapper has `multivalued: "true"` per the
  realm-config export);
- emit only one alias (e.g. "primary" picked by some heuristic, or
  the first member of the iteration);
- collapse into an object (`{"<alias>": {}, ...}`) keyed by alias;
- drop to absent (per invariant 11) because the mapper can't pick;
- emit something more elaborate like an array of org-rep objects;
- or vary across mints (invariant-10-shaped, JVM-iteration-
  dependent — the secondary question this fixture asks).

The misread a skill-only reader could fall for: assuming "the same
pattern Keycloak uses for `roles` and `groups` claims applies here"
and committing to `["acme", "zeta"]` (alphabetical) — without the
skill text actually pinning that. The fixture's order commitment is
the dimension where a hedge-with-invariant-10-citation may be
admissible.

Stated invariants invoked by this fixture:

- **Invariant 2** — `scope` claim composition. The predictor should
  derive that `scope` contains `openid` (request param) and
  `organization` (built-in scope, `include.in.token.scope=true`).
  adversarial-4's findings (not visible to predictor) flagged that
  the **member's** `scope` claim contains `organization` *twice*
  due to the dynamic-organization-scope resolution path adding a
  synthetic copy. We ask the predictor to commit on the literal
  scope-claim string AND on the multiset, so the duplicate
  observation is scoreable.
- **Invariant 7** — ID-token base claims sourced from transformed
  access token. The OOTB mapper has `id.token.claim=true,
  access.token.claim=true`; both tokens should carry the same shape.
- **Invariant 10** — mapper sort tie non-determinism + the
  HashSet-iteration shape generally. Used as the hedge anchor for
  the order commitment if (and only if) the determinism check
  shows volatile ordering.
- **Invariant 11** — NON_NULL drops null claims. Not expected to
  fire here (membership is non-empty), but kept on-menu.

## Realm / client / scope / mapper / user configuration

Realm: `adv-5` (fresh; doesn't collide with `master`, `adv-1`,
`adv-2`, `adv-3`, `adv-4`, `myrealm`, `orgtest`).

Realm-level `organizationsEnabled=true` (toggled AFTER realm
creation per the adv-4 surprise §2 — server-level `ORGANIZATION`
feature is enabled, but realm-level toggle defaults to false).

Client: `adv5-client`
- Confidential (`publicClient=false`), secret `adv5-secret-cafebabe`.
- `directAccessGrantsEnabled=true` — for ROPC password grant.
- `serviceAccountsEnabled=false`, `standardFlowEnabled=false`,
  `implicitFlowEnabled=false` — out of scope.
- `fullScopeAllowed=false` — deterministic scope governance per
  invariant 6.
- `defaultClientScopes`: Keycloak's OIDC built-ins (`web-origins`,
  `acr`, `profile`, `roles`, `basic`, `email`) PLUS the realm's
  built-in `organization` client scope as a **default**. The org
  scope was created as a default-optional on the client; an admin
  call moved it to default-default to make the seam fire statically.
- `optionalClientScopes`: Keycloak defaults minus `organization`
  (which is moved to default).
- No custom protocol mappers. The OOTB
  `oidc-organization-membership-mapper` baked into the built-in
  `organization` scope is the only thing producing the claim.

Organisations (two, both with the test user as a member):

- `zeta` — alias `zeta`, name `Zeta Industries`, domain `zeta.test`.
  **Created FIRST** in chronological insertion order (HTTP 201 came
  back before acme's HTTP 201).
- `acme` — alias `acme`, name `Acme Corp`, domain `acme.test`.
  Created SECOND.

The deliberate `zeta`-then-`acme` insertion-order choice (instead
of alphabetical `acme`-then-`zeta`) is what makes this seam
discriminative: a token emitting `["acme", "zeta"]` is consistent
with **alphabetical-by-alias** ordering; a token emitting
`["zeta", "acme"]` is consistent with **insertion-order** ordering;
a permutation that depends on UUID hash-bucket would be a third
shape; a token emitting only one of the two aliases is a fourth
shape (single-pick). NB: the admin REST API's
`GET /organizations` already returns the list alphabetised by alias
(`acme` then `zeta` — see `realm-organizations.json`), which is a
separate observation from the mapper's emission order.

User: `adv5-multimember`
- Username `adv5-multimember`, password `password`, `enabled=true`,
  `emailVerified=true`, `firstName=Adv5`, `lastName=Multimember`,
  `email=adv5-multimember@example.invalid`.
- Why first/last/email populated: required for password grant to
  clear `verify-profile` even with `requiredActions=[]` (the same
  surprise documented in adversarial-1's `surprises.md`).
- Membership added to `zeta` FIRST, then `acme` SECOND (both HTTP
  201). UNMANAGED membership type.

## The request

```
POST /realms/adv-5/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv5-client
client_secret=adv5-secret-cafebabe
username=adv5-multimember
password=password
scope=openid organization
```

Captured to `request.json`. `organization` is a **default** scope on
the client so the mapper-set fires regardless of whether the scope
is in the request param; `scope=openid organization` is requested
explicitly for clarity (and to set up the invariant-2 commitment on
the `scope` claim).

One mint produces both access_token and id_token; the determinism
check (Step 6 of seam-design.md) replays the mint a second time to
confirm the `organization` claim is stable. Both mints' decoded
payloads are written to `actual-token.json` /
`actual-id-token.json` (first mint) and to a `_mint2_*` companion
held outside the public artefact set (see surprises.md for the
determinism evidence).

## Plausible outputs (the trap menu)

For the `organization` claim on the access token (and the ID token
mirroring per invariant 7), the candidate wire shapes — numbered
exactly as in `prediction-target.md` — are:

1. **Absent.** Claim does not appear in the payload. Would be
   predicted by a reader applying NON_NULL (invariant 11) to a
   mapper that returns null because it can't disambiguate multi-
   membership. Unlikely on its face — the OOTB mapper has
   `multivalued: "true"` per the realm-config, which strongly
   implies it's designed to handle N>1 — but on-menu.

2. **Empty array `[]`.** Mapper short-circuits to an empty
   container on multi-membership. Wrong if any non-null emission.

3. **Single-alias array, alphabetically first: `["acme"]`.** Mapper
   picks one alias by alphabetical order. Would be predicted by a
   reader who assumed the mapper picks a "primary" by deterministic
   ordering, alphabetical-leading.

4. **Single-alias array, insertion-order first: `["zeta"]`.** Same
   as #3 but the mapper picks by insertion order rather than
   alphabetical.

5. **Both aliases, alphabetical order: `["acme", "zeta"]`.** The
   most likely correct shape if the mapper enumerates aliases in
   alphabetical order. Symmetric with how some Keycloak claims are
   sorted.

6. **Both aliases, insertion order: `["zeta", "acme"]`.** Correct
   if the mapper preserves the order in which the user was added to
   each organisation.

7. **Both aliases, HashSet/JVM-iteration order (non-deterministic
   across mints OR across JVM restarts).** Shape is `[X, Y]` where
   the choice of order between mints is not contract-derivable.
   This is the invariant-10-shaped escape hatch — the **only**
   shape that admits a hedge-with-citation in the prediction-
   target.

8. **Both aliases, object keyed by alias with empty bodies:
   `{"acme": {}, "zeta": {}}`.** Would be predicted by a reader who
   assumed Keycloak emits organisations as a per-alias object
   namespace for forward-compat with per-org metadata.

9. **Both aliases, object keyed by alias with non-empty bodies:
   `{"acme": {"id": "<uuid>", ...}, "zeta": {...}}`.** Would be
   predicted by a reader who assumed the OOTB mapper inlines the
   full org representation. The presence of `multivalued: "true"`
   plus `jsonType.label: "String"` in the mapper config argues
   against this — `String` typing implies the value is the alias
   string itself, not an object.

10. **Array of org-rep objects:
    `[{"alias": "acme", ...}, {"alias": "zeta", ...}]`.** Parity
    with the admin REST API's GET `/organizations` shape. Same
    counter-argument as #9 (the `jsonType.label: "String"`).

11. **Different shape per surface (access vs ID).** Invariant 7
    argues against this — but kept on-menu as a rule-out trap.

12. **Realm-wide list of all orgs regardless of membership.** No
    longer a useful trap here (the user IS a member of both orgs
    in this realm — `zeta` and `acme` exhaust the realm), but kept
    on-menu because it's the natural completion of the trap-set
    started in adversarial-4 (and for the predictor a deliberate
    rule-out is signal that they read the membership list).

13. **Per-mint volatility on SET MEMBERSHIP (not just order).**
    Would invalidate the fixture as a regression test. Checked
    explicitly in the determinism step.

The pre-mint best guess is shape #5 (`["acme", "zeta"]`,
alphabetical) OR shape #6 (`["zeta", "acme"]`, insertion-order) OR
shape #7 (hedge-with-citation if the order is JVM-volatile). Shape
#5 has a slight edge because alphabetical sorting is more common in
serializers, but I don't know — that's the whole point of this
fixture.

For the `scope` claim: per invariant 2 the `scope` claim should
contain `openid` and `organization`. The pre-mint hypothesis (NOT
sharing this with the Predictor) from adversarial-4's findings is
that `organization` may appear TWICE in the literal string due to
the dynamic-organization-scope resolution path. The prediction
target asks the predictor to commit on **both** the literal string
AND the multiset count, so the duplicate observation is scoreable
either way.

## Minimum specificity to pass

For the `organization` claim commitments (access AND ID):

- A pass requires a specific trap-menu index per surface (1..13),
  AND, where the index implies a non-empty value, the exact JSON
  value with both alias strings spelled correctly (or one alias
  if the trap is #3 or #4).
- Order commitment: the predictor must EITHER commit to a specific
  order (e.g. `["acme", "zeta"]` or `["zeta", "acme"]`) OR hedge
  with a clean invariant-10 citation explaining why the order is
  JVM-iteration-dependent and outside the documented contract.
  Citing invariant 10 without a specific contract rationale (e.g.
  "I just don't know") is NOT a clean hedge.

For the `scope` claim:

- The literal `scope` string commitment must specify whether
  `organization` appears once or twice.
- The multiset commitment must list the count per token.

## Determinism check plan

Strip set: `iat, exp, auth_time, session_state, sid, nbf`, and the
UUID portion of `jti` after the colon.

The `organization` claim is NOT in the strip set. If two mints
produce different `organization` claim **set membership**, the
fixture is non-deterministic on set and is a fixture bug; redesign.

If two mints produce different `organization` claim **array
order** but the same set, that is acceptable — the order
commitment will be hedged-with-invariant-10 in the prediction
target and the verdict will be a `pass` if the predictor hedges
correctly. Document in `surprises.md`.

## Resolution after capture

Tokens captured at `actual-token.json` / `actual-id-token.json`
(mint 1) and `actual-token-mint2.json` / `actual-id-token-mint2.json`
(mint 2). Logs at `log.txt` and `log-mint2.txt`. Surprises in
`surprises.md`.

Headline observations:

- **access token `organization` claim shape = #1 (ABSENT).** The
  claim does not appear in the payload at all. Confirmed via
  `jq 'has("organization")'` → `false` on both mints.
- **ID token `organization` claim shape = #1 (ABSENT).** Same.
- **`scope` claim on access token** = `"openid profile email
  organization"` — `organization` appears EXACTLY ONCE. Different
  from adv-4's member-case observation of twice.
- **`scope` claim on ID token** = ABSENT (no `scope` claim on ID
  tokens at all — consistent with standard OIDC, the `scope` claim
  lives on access tokens only here).
- **Determinism check**: clean. Two mints diffed modulo
  `iat, exp, auth_time, session_state, sid, nbf, jti`, plus
  `at_hash` on the ID token. Empty diffs in both cases. The
  `organization` claim's absence is stable across mints; the
  `scope` claim's `organization`-once is stable across mints.

The pre-mint trap menu's shape #1 (absent) was on the menu but was
NOT one of the pre-mint best guesses (shapes #5 / #6 / #7 were).
This is the seam paying off: an N=1 → N=2 transition flips the
mapper output from `["acme"]` (per adv-4) to absent. The mechanism
is the alias-qualifier request-param idiom that the target skill
does not document; see `surprises.md` §1 for the out-of-band probe
that confirmed it.

The fixture verdict is the Predictor's call. Anticipated
verdict-paths:

- If Predictor lands on #1 (absent) via NON_NULL reasoning on an
  empty/null mapper output: **PASS** (trap menu correctly
  enumerated, prediction correct).
- If Predictor lands on #5/#6/#7 by extending a `multivalued:
  "true"` mapper config to the natural "both aliases in the
  container" outcome: **FAIL-SKILL-GAP** (the skill text genuinely
  lacks the alias-qualifier rule, and a reasonable read of
  `multivalued` plus the membership list leads to a wrong
  commitment).
- If Predictor refuses to commit and cites a gap in the skill text:
  **FAIL-BY-DESIGN** for the absent-claim case (the skill really
  is silent on this), though the trap menu does enumerate #1 so
  a careful hedge-with-rationale would also be admissible.

Verdict decision deferred to the diff phase.
