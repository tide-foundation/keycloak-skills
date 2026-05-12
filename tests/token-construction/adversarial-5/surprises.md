# Surprises encountered while building adversarial-5

## 1. The `organization` claim is ABSENT on multi-membership when `scope=organization` is requested without an alias qualifier

This is the headline finding and the seam payoff.

**Pre-mint expectation**: with the OOTB `oidc-organization-membership-mapper`
configured `multivalued: "true"`, a user who is a member of two
organisations would see both aliases in the claim — either
`["acme", "zeta"]` (alphabetical) or `["zeta", "acme"]` (insertion-
order) or a JVM-iteration permutation (hedge with invariant 10).
Trap-menu shapes #5, #6, and #7 were the three plausible-correct
candidates.

**Observed**: the `organization` claim is **absent** from both the
access token and the ID token (shape #1) on a `scope=openid
organization` mint when the user is a member of TWO organisations
in the realm. Verified via `jq 'has("organization")'` → `false` on
both surfaces, both mints.

Cross-checked against the prior fixture (adv-4, which the Predictor
must not see): the single-membership case with the same request
shape produced `["acme"]` (shape #4 in adv-4's enumeration). So the
mapper's wire shape changes from "array with one alias" at N=1 to
"absent" at N=2 — the multi-membership case requires a different
request idiom.

**Mechanism (probed out-of-band, NOT part of the seam)**: Keycloak
supports a request-param idiom `scope=organization:<alias>` to
request a specific organisation's membership, or
`scope=organization:*` to request ALL of the user's organisation
memberships. I ran out-of-band probes (not captured as official
fixture artefacts) to confirm:

- `scope=openid organization` (the seam under test) → `organization`
  claim absent.
- `scope=openid organization:acme` → `organization: ["acme"]`,
  `scope` claim contains `organization:acme` (not `organization`).
- `scope=openid organization:*` → `organization: ["zeta", "acme"]`,
  insertion-order stable across five back-to-back mints, `scope`
  claim contains `organization:*`.

The deduction: the unqualified `organization` scope token is a
**static** attachment that does NOT auto-resolve to "all of the
user's memberships." When the user has zero memberships, the
mapper has nothing to emit and the claim is dropped (consistent
with invariant 11 NON_NULL). When the user has exactly one
membership, the mapper auto-picks that single org (probably via
a domain-matching heuristic against email, OR via a "if only one,
just emit it" branch). When the user has more than one membership,
the mapper apparently cannot pick and emits null → claim dropped.

This is **the gap**: the target skill's three paragraphs on
organisation scope (in `references/scope-resolution.md`) describe
neither the alias-qualifier syntax nor the multi-membership-with-
unqualified-scope behaviour. A SKILL.md edit candidate.

**Implication for the verdict**: the trap menu in
`prediction-target.md` already includes shape #1 (absent). A
Predictor that lands on #1 with a NON_NULL-based reasoning is a
PASS by trap-menu construction; a Predictor that lands on #5/#6/#7
with insertion-order reasoning is a FAIL-SKILL-GAP and warrants a
SKILL.md edit explaining the alias-qualifier idiom. Either verdict
is informative.

## 2. The `scope` claim contains `organization` exactly ONCE on the multi-membership user (not twice)

Pre-mint expectation (NOT in `prediction-target.md`, but in the
builder's internal hypothesis): adv-4's findings showed that the
member's `scope` claim contained `organization` TWICE due to a
hypothesised dynamic-organization-scope resolution path adding a
synthetic copy. I expected the same here — twice, possibly thrice
for two memberships.

**Observed**: the `scope` claim is `"openid profile email
organization"` — `organization` appears exactly ONCE. This is
*different* from adv-4's member-case observation.

Hypothesised mechanism: the dynamic-organization-scope resolution
path that added a synthetic second `organization` token in adv-4
appears to be triggered by **single-membership auto-resolution**
(N=1) — the same code path that auto-picks `acme` for the
adv-4 member, registers a synthetic `organization` scope as having
fired. When N=2, the auto-pick path does NOT fire (claim absent),
so the synthetic scope-name doesn't get added either. This is
consistent with both observations.

**Implication**: the duplicate-`organization`-in-scope-claim
finding from adv-4 was conditional on the auto-resolution path
having succeeded. With multi-membership + unqualified scope, the
auto-resolution path fails silently and the synthetic copy is
absent too. A future fixture probing the `scope` claim under
`scope=organization:*` (which exercises a different path) would
also be informative — likely another candidate for adv-6 or
later.

## 3. The admin REST API's `partial-export` endpoint is POST, not GET

The seam-design.md operational note says:

> Realm export: `GET /admin/realms/{realm}/partial-export?exportClients=true&exportGroupsAndRoles=true`

This is wrong. A `GET` returns `HTTP 404 Not Found`. The correct
verb is `POST`. Confirmed by experiment:

- `GET .../partial-export?...` → `HTTP 404 Not Found`
- `POST .../partial-export?...` → `HTTP 200`, returns the export
  JSON.

Mitigation: used `POST` for this fixture; the resulting
`realm-config.json` is well-formed.

Implication: the seam-design.md operational note for export should
be corrected from `GET` to `POST`. Flagging as a candidate edit to
`keycloak-token-fixture-build/references/seam-design.md` (Step 7
and the operational notes section). Adv-4 happened to have the
correct verb because its builder used a different tool path.

## 4. The admin REST API's organisation-membership endpoint expects a JSON-string body (NOT an object)

Same shape adv-4 observed: `POST
/admin/realms/{realm}/organizations/{id}/members` takes a body of
the form `"<user-uuid>"` — a single JSON string literal — not an
object like `{"id": "<user-uuid>"}`. This is documented (now) in
adv-4's surprises and reused here. No new info — flagging only to
keep the trail of admin-API quirks together.

## 5. The admin REST API listing `GET /organizations` returns alphabetised order, NOT creation order

`GET /admin/realms/adv-5/organizations` returns:

```
[ {acme, ...}, {zeta, ...} ]
```

Despite `zeta` having been created first (HTTP 201 #1), the API
returns the list with `acme` first. This is alphabetical-by-alias.

**Implication for the fixture**: the `realm-organizations.json`
file I wrote uses the API's natural return order, which is
alphabetical. To document the actual creation order, I added a
`_note` field at the top of the file and rely on each member's
`createdTimestamp` field to convey insertion order. The
`adv5-multimember` user has `createdTimestamp` of `1778553709008`
across BOTH zeta and acme org-membership records — they're
identical down to the millisecond, because the user's
`createdTimestamp` is the user's creation moment, not the
membership-creation moment. So `createdTimestamp` does NOT actually
disambiguate the order in which the user was added to each org.

The only durable evidence of insertion-order is in *this surprises
file* and `setup.md`. The Predictor will see neither — only
`realm-organizations.json`, which presents the orgs alphabetically.
**This means the Predictor will reasonably default to alphabetical
order** if they assume the API list-order reflects the mapper
output order — a reasonable but ungrounded inference.

This is fine for the seam's primary commitment (set membership) but
limits the discriminative power of the order-vs-alphabetical
distinction. Since the actual claim is ABSENT, the order question
is moot for the scoring rubric anyway.

## 6. Determinism check: clean

Two mints with `scope=openid organization` produced byte-identical
payloads after stripping `iat, exp, jti, sid, session_state,
auth_time, nbf`:

- Access token diff: empty.
- ID token diff (also stripped `at_hash`): empty.

The `organization` claim is absent from both mints (consistent
absence is itself determinism). The `scope` claim is identical
across mints.

Five additional mints with the out-of-band `scope=organization:*`
probe also produced identical `organization: ["zeta", "acme"]` —
insertion-order stable, no JVM-iteration variability observed.

## Reusable observations

1. **Multi-membership + unqualified `organization` scope = absent
   claim.** This is a Keycloak 26.5.5 behaviour worth documenting
   in the target skill. The OOTB
   `oidc-organization-membership-mapper` does NOT enumerate all
   memberships under the unqualified scope; it requires the
   alias-qualifier idiom (`organization:<alias>` or
   `organization:*`).

2. **`organization:*` request-param syntax.** Not described in the
   target skill at all. Triggers a "request all memberships"
   resolution path that emits the full alias list in insertion-
   order. Worth a dedicated reference passage.

3. **The `partial-export` endpoint is POST, not GET.** The
   seam-design.md operational note is wrong. Correct in a future
   edit.

4. **Admin API list endpoints alphabetise.** Both
   `/organizations` and (per adv-4) `/users` return their
   collections alphabetised, not in insertion order. Fixture
   builders relying on insertion-order for discrimination must
   capture that order out-of-band (in `setup.md` /
   `surprises.md`); it is NOT visible to the Predictor via the
   admin export.
