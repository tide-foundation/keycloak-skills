# Surprises encountered while building adversarial-6

## 1. The `organization` claim for `scope=organization:*` is in REVERSE INSERTION ORDER, not insertion order

Adv-5's surprises.md §1 reported `["zeta", "acme"]` for a user
inserted into `zeta` THEN `acme` with `scope=organization:*`. Adv-5
characterised this as "insertion-order, stable across 5 mints."

Adv-6 inserts `adv6-multimember` into `acme` FIRST, then `globex`
SECOND. The wildcard request returned `["globex", "acme"]` across
seven back-to-back mints (2 official + 5 confirmation). If adv-5's
"insertion-order" reading were correct, the expected adv-6 output
would have been `["acme", "globex"]`.

Reconciling the two observations:

- adv-5: `zeta`-first, `acme`-second → `["zeta", "acme"]`
- adv-6: `acme`-first, `globex`-second → `["globex", "acme"]`

Both observations are consistent with **REVERSE-of-insertion-order**
(equivalently, "most-recently-added first"). They are NOT both
consistent with insertion-order. They are also both consistent with
**reverse-alphabetical** by alias (`zeta > acme`, `globex > acme`),
but that's only because each fixture has just two orgs where the
two readings collide.

To disambiguate REVERSE-INSERTION from REVERSE-ALPHABETICAL, a
future fixture would need an insertion order like
`alpha`→`gamma`→`beta` (3 orgs, alphabetical and reverse-insertion
disagreeing). For adv-6 the observation is stable; the
order-mechanism remains under-determined between these two
candidates but the FIRST hypothesis adv-5 advanced (insertion-
order) is now refuted.

**Implication for the seam**: this fixture's pre-mint trap menu
listed shape **2a** (alphabetical `["acme", "globex"]`) and shape
**2b** (reverse-alphabetical `["globex", "acme"]`) — the actual
result lands on **2b**. The Predictor will be scored against this.

**Implication for the target skill**: scope-resolution.md does NOT
document the wildcard `organization:*` mechanism at all. A skill
edit candidate is to add the wildcard syntax, what claim it
produces, and an invariant-10-shaped hedge on the order (since two
fixtures' data are insufficient to nail down reverse-insertion vs
reverse-alphabetical). The honest documentation is "the order is
not contract-derivable from the configured organisations alone."

## 2. The `scope` claim STRING ORDER is non-deterministic across mints

A noteworthy fixture-level surprise: while the SET of scopes in the
`scope` claim is stable across mints, the **string order is not**.

Mint 1 specific:  `"openid organization:acme email profile"`
Mint 2 specific:  `"openid email organization:acme profile"`
Mint 1 wildcard:  `"openid email profile organization:*"`
Mint 2 wildcard:  `"openid email organization:* profile"`

All four scope strings contain the same multiset
`{openid, email, profile, organization:<qualifier>}` but the order
varies per mint. The `openid` token appears to be reliably first
(consistent with `TokenUtil.attachOIDCScope` prepending `openid` if
absent — scope-resolution.md L104-111), but the order of the rest
is HashSet-iteration-shaped (invariant 10 territory).

**Implication for `prediction-target.md`'s scoring**: the
prediction-target asks the predictor to commit to the **exact**
literal scope-claim string. Since the order is volatile across
mints, the literal-string commitment is **only partly scoreable**:
- The MULTISET commitment (which tokens are present) is fully
  scoreable and deterministic.
- The EXACT STRING commitment is not scoreable as written because
  no fixed string is correct on all mints.
- The `openid`-first ordering anchor IS scoreable (matches both
  mints).
- The relative order of `organization:<qualifier>` vs static
  `email` / `profile` IS NOT scoreable as a fixed string.

This is a **fixture-bug-shaped problem with the prediction target,
not a bug in the realm config**. The seam is still informative if
the predictor commits to a specific order (their commitment is
testable against ONE mint and may or may not match, but the
fixture would have to score "set membership + openid position"
which is what adv-2's verdict rubric already pioneered). The
trap-menu indices (1-scope-A/B/C/D, 2-scope-A/B/C/D) are themselves
defined as MULTISET-level statements (e.g., "contains only
`organization:acme`" or "contains both bare `organization` AND
`organization:acme`") so the trap-index commitment IS still
scoreable cleanly.

**Mitigation**: the diff phase should score the trap-index
commitment and the multiset commitment as primary; treat the
exact-string commitment as informational only (note in diff.md).
The setup.md "Resolution after capture" section flags this.

## 3. For `scope=organization:acme` (specific real alias), the dedup rule (scope-resolution.md L22-28) FIRES — static `organization` is dropped

The literal `scope` claim contains `organization:acme` but does NOT
contain bare `organization`. Set membership across both mints:
`{openid, email, profile, organization:acme}` — exactly four
tokens. The static `organization` default scope was attached to the
client (visible in `realm-config.json` defaultClientScopes), but
the dedup rule L22-28 filtered it out because:

- `scopeParam` contains `organization:acme`.
- The static `organization` scope's `name + ":"` (= `"organization:"`)
  is a prefix of `"organization:acme"`.
- The static `organization` scope carries an
  `OrganizationMembershipMapper`.

All three conditions hold → static `organization` dropped. The
dynamic `organization:acme` synthetic scope (per L35-37) is in the
candidate set and is the sole contributor of the `organization`
claim, which narrows to `["acme"]`.

This is **exactly what scope-resolution.md L22-28 predicts**, and
is one of the few pieces of organisation-scope behaviour the skill
text does cover. Anticipated trap-index commitments: 1a + 1-scope-A.

## 4. For `scope=organization:*` (wildcard), the dedup rule ALSO fires

The literal `scope` claim contains `organization:*` but does NOT
contain bare `organization`. Same mechanism as #3: the static
`organization` scope has `name + ":"` = `"organization:"` which is
a prefix of `"organization:*"`, so dedup drops it.

This is interesting: the dedup rule treats `*` as a
syntactically-valid alias-qualifier suffix, even though `*` is not
a real alias. The wildcard isn't special-cased in the dedup; it's
the *resolution* (whatever `tryResolveDynamicClientScope` does
internally) that special-cases the `*` to mean "all of the user's
memberships."

Anticipated trap-index commitments: 2b + 2-scope-A.

## 5. For `scope=organization:nonexistent`, pre-flight rejects with HTTP 400 invalid_scope

The request returns:

```
HTTP/1.1 400 Bad Request
{"error":"invalid_scope","error_description":"Invalid scopes: openid organization:nonexistent"}
```

The Keycloak log captures:

```
WARN [org.keycloak.events] type="LOGIN_ERROR" realmId="..."
realmName="adv-6" clientId="adv6-client" userId="null"
ipAddress="172.20.0.1" error="invalid_request"
reason="Invalid scopes: openid organization:nonexistent"
auth_method="oauth_credentials" grant_type="password"
client_auth_method="client-secret"
```

This is **exactly the pre-flight branch documented in
scope-resolution.md L86-97**:

> If any token in the param doesn't appear in the union of default
> + optional + dynamic scopes registered for the client, the
> request is rejected with `OAuthErrorException.INVALID_SCOPE` and
> the message `"Invalid scopes: " + scope` (TokenManager.L755-759,
> throw at OAuth2GrantTypeBase.L255). `event.error(Errors.INVALID_REQUEST)`
> produces a `CLIENT_LOGIN_ERROR` WARN. Pre-flight rejection means
> no token, no clientSessionCtx, no mappers.

Two details worth flagging:

a. The HTTP response body's `error` field is `invalid_scope`, but
   the event log's `error` field is `invalid_request`. The skill
   text describes this exact split — the OAuth2 error code returned
   to the client is `invalid_scope` (via the
   `OAuthErrorException.INVALID_SCOPE` constant), while the event
   audit log uses the generic `INVALID_REQUEST` error category.
   A predictor that conflates these two would commit incorrectly.

b. The validation log line right before the error shows the
   candidate set:
   `"Scopes to validate requested scopes against: web-origins acr
   profile roles basic email"`
   — note `organization` is NOT in this list. This is the
   "stripped" candidate set after `openid` removal (per L156-159
   of scope-resolution.md) AND after `organization` has been
   dropped by the dedup rule (because `scopeParam` contains
   `organization:` prefix). With `organization` gone from the
   candidates and no dynamic resolution matching `nonexistent`,
   the validation fails.

   This is an **interesting interaction**: the dedup rule from
   L22-28 fires BEFORE pre-flight validation, even for a bogus
   alias. That means a request `scope=organization:nonexistent`
   removes the static `organization` from the candidate set, and
   then validation fails because `organization:nonexistent` isn't
   itself a registered scope. The skill text (L22-28) is silent on
   whether dedup applies pre- or post-validation; this observation
   pins it as PRE.

Anticipated trap-index commitment: 3a + 3-scope-A.

## 6. Determinism check: clean on the seam targets, dirty on scope-string ordering

Strip set per `setup.md`: `iat, exp, auth_time, session_state, sid,
nbf, jti, at_hash` (last only on ID tokens).

After stripping:

- Request 1 (specific): access-token diff is **non-empty** (only
  the `scope` claim string order differs); ID-token diff is empty.
- Request 2 (wildcard): same shape — access-token `scope` claim
  string differs; ID-token diff empty.
- Request 3 (nonexistent): HTTP response bytewise identical
  between mint 1 and mint 2.

Detail:

```
specific mint1: "scope": "openid organization:acme email profile"
specific mint2: "scope": "openid email organization:acme profile"

wildcard mint1: "scope": "openid email profile organization:*"
wildcard mint2: "scope": "openid email organization:* profile"
```

The `organization` claim itself (the primary seam target) is
identical across mints in all three requests. Set membership of
the `scope` claim is identical across mints. Only the
**positional order** of non-`openid` tokens varies — invariant 10
territory.

Five additional wildcard mints (back-to-back, kept outside the
official artefact set) confirmed `organization: ["globex",
"acme"]` is stable, and the `scope`-claim string order continued
to vary across mints in an apparently random way.

**Implication for the verdict**: the seam's primary commitment
(trap indices for `organization` claim and the multiset of
`scope` claim) is fully scoreable and deterministic. The
exact-string `scope` claim commitment in `prediction-target.md`
is testable only against ONE mint and may produce a false
fail-skill-gap if the predictor commits to mint 1's order but
the scoring compares to mint 2's. The diff phase should treat the
trap indices as primary and the multiset as canonical; the exact
string is informational. See §2 above.

## 7. `id_token` does NOT carry a `scope` claim

Consistent with adv-5's observation and OIDC convention: the
`organization` claim appears on both access and ID tokens with the
same value (invariant 7 satisfied), but the `scope` claim is
present only on the access token. A predictor that commits to an
ID-token `scope` claim string would be wrong. (Not in the trap
menu explicitly because OIDC convention treats `scope` as access-
only, but worth flagging.)

## 8. The admin REST API endpoint `/users/{id}/organizations` returns HTTP 404 in Keycloak 26.5.5

Hit during builder verification. The endpoint
`GET /admin/realms/adv-6/users/{user-uuid}/organizations` returned
`{"error":"HTTP 404 Not Found"}`. Confirmed memberships via the
forward direction instead:
`GET /admin/realms/adv-6/organizations/{org-id}/members`.

Not a blocker for the fixture (forward-direction lookup works
fine), but worth flagging as an admin-API quirk: the org-to-users
direction is available; the users-to-orgs direction is not (or is
on a different path I didn't find — adv-5's setup also didn't use
it). Builders relying on the user-to-orgs view need to enumerate
orgs and check each one's members.

## Reusable observations

1. **The wildcard `organization:*` order is REVERSE of what adv-5
   reported**. Two data points across two fixtures (adv-5: zeta-then-
   acme → `["zeta", "acme"]`; adv-6: acme-then-globex → `["globex",
   "acme"]`) refute insertion-order and are both consistent with
   reverse-insertion OR reverse-alphabetical. A 3-org fixture with
   non-monotonic insertion (e.g., `beta`→`alpha`→`gamma`) would
   disambiguate.

2. **The `scope` claim string is order-non-deterministic across
   mints** but set-deterministic. This affects any fixture that
   commits to an exact `scope` claim string. The standard hedge
   pattern (adv-2's verdict rubric) is "commit to multiset; hedge
   on order with invariant-10 citation."

3. **Dedup rule (L22-28) fires PRE-validation**, even for bogus
   alias qualifiers. This pins the algorithm ordering that the
   skill text leaves ambiguous.

4. **HTTP `error` vs event-log `error` are different fields with
   different values** for the same rejection: HTTP returns
   `invalid_scope`; event log records `invalid_request`. The
   skill text describes this exact split but it's a common source
   of confusion in operator-facing diagnostics.

5. **The admin API users-to-organizations direction is 404** in
   Keycloak 26.5.5. Use orgs-to-members for verification.
