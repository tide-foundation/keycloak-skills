# adversarial-4 — `organization` claim wire shape (skill gap probe)

## The seam

The target skill (`keycloak-token-construction`) is **silent on the
wire shape of the `organization` claim**. Its only references to
organisations are three short paragraphs in
`references/scope-resolution.md` (L22-28, L35-37, L74-77) about
dedup and dynamic resolution of the `organization` client scope —
nothing about the mapper that produces the claim, nothing about its
JSON serialisation, nothing about the empty-membership case.

This fixture probes the **gap**, not a stated invariant. The most
adjacent stated invariants are:

- **Invariant 2** — `scope` claim composition. The predictor should
  trivially derive that the `scope` claim contains `openid` (because
  `openid` is in the scope param) and `organization` (because the
  `organization` built-in client scope has `include.in.token.scope`
  unset/true; same logic as adv-2). No surprise expected on this leg.
- **Invariant 11** — NON_NULL drops null claims. For the non-member
  case (zero memberships), if the mapper emits `null` (vs. an
  explicit empty container), the wire result is "claim absent." This
  is one branch of the trap menu (shape #1).
- **Invariant 7** — ID-token base claims sourced from transformed
  access token. If the access token's `organization` claim has shape
  X, the ID token's should have the same shape X (modulo per-surface
  mapper toggles, but the OOTB `oidc-organization-membership-mapper`
  has uniform-by-default toggles per the built-in scope). Shape #9
  (different shape per surface) would contradict invariant 7 and is
  expected to be wrong.

The question forced by this fixture's realm config: what is the exact
JSON wire shape of the `organization` claim for a one-org member, and
what is it for a zero-org user, on both the access token and the ID
token, from a single mint with `scope=openid organization`?

The trap a skill-only reader would fall for: the skill's "Static
client scopes" path (scope-resolution.md L74-77) tells the reader the
`organization` scope's mapper-set is folded in for a member, but
doesn't tell them what the mapper outputs. A skill reader who guesses
"`["acme"]`" (shape #4) is making a reasonable but ungrounded guess;
a skill reader who guesses `{"acme": {}}` (shape #5) is doing the
same. The fixture exists to show whether the skill's silence is
*correct hedging* (the predictor refuses to commit and cites the
gap) or *latent commitment* (the predictor commits to one shape with
no skill backing, and either lucks out or doesn't).

## Realm / client / scope / mapper / user configuration

Realm: `adv-4` (fresh; doesn't collide with `master`, `adv-1`,
`adv-2`, `adv-3`, `myrealm`, `orgtest` per the builder prompt).

Client: `adv4-client`
- Confidential (`publicClient=false`).
- `directAccessGrantsEnabled=true` — enables Resource Owner Password
  Credentials grant.
- `serviceAccountsEnabled=false`, `standardFlowEnabled=false`,
  `implicitFlowEnabled=false` — out of scope.
- `fullScopeAllowed=false` — deterministic scope governance per
  invariant 6; the only scopes that fire are those explicitly
  attached.
- `defaultClientScopes`: Keycloak's OIDC built-ins (created with the
  client by default — `web-origins`, `acr`, `profile`, `roles`,
  `basic`, `email`) PLUS the realm's built-in `organization` client
  scope as a default. This is the lever that makes
  `scope=organization` "fire statically": with `organization` on the
  default list, the scope's mapper-set is folded in regardless of
  the `scope` request param — and `scope=openid organization` is
  requested anyway for explicitness.
- `optionalClientScopes`: whatever Keycloak attaches by default;
  `organization` deliberately NOT here, because that would force
  dynamic resolution and add noise to the seam.
- No custom protocol mappers. The OOTB
  `oidc-organization-membership-mapper` baked into the built-in
  `organization` scope is the only thing producing the claim.

Organisations (two; one with the test user as a member, one as a
control to defeat trap #8):
- `acme` — alias `acme`, name `Acme Corp`, one domain `acme.test`.
  Member: `adv4-member`.
- `globex` — alias `globex`, name `Globex Inc`, one domain
  `globex.test`. Member: **none**. Exists purely so that a "claim
  lists all realm orgs" trap can be defeated by the non-member's
  token NOT containing `globex` either (and the member's token NOT
  containing `globex` despite `globex` existing).

Users:
- `adv4-member` — username `adv4-member`, password `password`,
  `enabled=true`, `emailVerified=true`, `firstName=Adv4`,
  `lastName=Member`, `email=adv4-member@example.invalid`. Member of
  `acme` only.
- `adv4-nonmember` — username `adv4-nonmember`, password `password`,
  `enabled=true`, `emailVerified=true`, `firstName=Adv4`,
  `lastName=Nonmember`, `email=adv4-nonmember@example.invalid`. Not
  a member of any organisation.

Why first/last/email populated: required for password grant to clear
the `verify-profile` authenticator even when `requiredActions=[]`
(same surprise documented in adversarial-1's `surprises.md`).

Why two users in one realm, same client, same scope: the only
variable is membership. This isolates the empty-membership leg of
the trap menu cleanly.

## The two requests

### Request 1 — member's password grant

```
POST /realms/adv-4/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv4-client
client_secret=<adv4-secret>
username=adv4-member
password=password
scope=openid organization
```

Captured to `request-member.json`. Expectation: per invariant 2 the
`scope` claim contains both `openid` and `organization` (or strips
`openid` if `include.in.token.scope=false` for the built-in `openid`
scope, but I expect `openid` to be present). The `organization`
claim is filled by the OOTB mapper from the user's membership of
`acme` — wire shape **unknown** pre-mint, will be observed.

### Request 2 — non-member's password grant

```
POST /realms/adv-4/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv4-client
client_secret=<adv4-secret>
username=adv4-nonmember
password=password
scope=openid organization
```

Captured to `request-nonmember.json`. Expectation: the OOTB mapper
sees zero memberships. Either (a) it emits null → NON_NULL drops
the claim (shape #1), or (b) it emits an explicit empty container
(shape #2 or #3). Pre-mint guess is (a), but I'm explicitly leaving
the trap menu open on (b).

## Plausible outputs (the trap menu)

Same as `prediction-target.md`'s trap menu — nine numbered shapes
plus the non-determinism escape hatch (#10). Summary:

1. Claim absent
2. Empty array `[]`
3. Empty object `{}`
4. Array of alias strings (e.g. `["acme"]`)
5. Object keyed by alias with empty bodies (e.g. `{"acme": {}}`)
6. Object keyed by alias with full bodies (e.g. `{"acme": {"id": ...}}`)
7. Array of org-rep objects (e.g. `[{"alias": "acme", ...}]`)
8. Realm-wide list of all orgs regardless of membership
9. Different shape across access vs ID token
10. Non-deterministic across mints — invalidates fixture

Pre-mint best guess for the member: shape #5 or shape #4 — both are
plausible. For the non-member: shape #1 (absent).

## Minimum specificity to pass

The predictor must commit a trap index per surface (access token /
ID token, for each of member / non-member — four commitments total).
If the trap index is 2-8, the value field must be filled with the
exact JSON value with `acme` (and only `acme`) named correctly.

The `scope` claim leg is mostly a control to confirm the predictor
understands invariant 2 — straightforward `pass` is expected there.
The interesting commitment is the `organization` claim shape.

## Determinism check plan

Strip set: `iat, exp, auth_time, session_state, sid, nbf`, and the
UUID portion of `jti` after the colon.

The `organization` claim is **not** in the strip set. If two mints
of the member's token produce different `organization` claim values,
the fixture is non-deterministic and the seam is broken. Same for
the non-member.

Plan: mint each user's token a second time, base64-decode payload,
`jq -S` both, diff modulo the strip set. If clean, note in
`surprises.md`. If dirty (on the `organization` claim), document and
do not proceed to the predictor phase.

## Resolution after capture

Captured tokens at `actual-token-member.json`,
`actual-id-token-member.json`, `actual-token-nonmember.json`,
`actual-id-token-nonmember.json`. Logs at `log-member.txt`,
`log-nonmember.txt`. Surprises in `surprises.md`.

Headline observations:

- **member access token**: `organization` claim shape = **#4**
  (`["acme"]` — a JSON array of alias strings).
- **member ID token**: `organization` claim shape = **#4**
  (`["acme"]`). Same shape across access and ID surfaces, confirming
  invariant 7 (ID-token base claims sourced from transformed access
  token; no per-surface mapper toggle on the OOTB mapper produces
  divergent shapes here).
- **non-member access token**: `organization` claim shape = **#1**
  (claim ABSENT from the payload). Confirmed via `jq 'has("organization")'`
  → `false`.
- **non-member ID token**: `organization` claim shape = **#1**
  (claim ABSENT). Same.
- **determinism check**: clean. Two mints per user; diff modulo
  `iat, exp, auth_time, session_state, sid, nbf, jti` was empty on
  both access tokens. ID tokens differed only on `at_hash` (expected
  — derived from the access-token signature whose per-mint `jti`
  UUID and `iat` change). The `organization` claim itself is stable
  across mints.

The pre-mint trap menu correctly anticipated the answer for both
users. No 5th trap had to be added. Shape #4 (array of alias
strings) was one of two pre-mint best-guess shapes; shape #1
(absent) was the pre-mint best guess for the non-member.

A secondary surprise turned up: the `scope` claim on the member's
token contains the substring `organization` **twice**
(`"openid profile organization organization email"`) — see
`surprises.md` §3. This is a separate skill-gap candidate worth
its own fixture; it is NOT the seam under test here and the
prediction-target asks for `scope` claims as a **set**, which dedups
the duplicate. The duplicate is flagged for the diff phase but
should not influence the verdict on the `organization`-claim shape
commitment.
