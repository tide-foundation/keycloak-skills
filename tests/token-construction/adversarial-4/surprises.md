# Surprises encountered while building adversarial-4

## 1. `partial-export` does not include organisations or memberships

Anticipated by the builder prompt, and confirmed here:
`GET /admin/realms/adv-4/partial-export?exportClients=true&exportGroupsAndRoles=true`
returns a JSON document with no `organizations` key at all (verified
via `jq '.organizations? // "MISSING_ORGANIZATIONS_KEY"'` on the
export — returned the sentinel). Empty arrays were not emitted
either; the key is simply absent.

Mitigation: captured organisations and memberships separately to
`realm-organizations.json` via
`GET /admin/realms/adv-4/organizations` and
`GET /admin/realms/adv-4/organizations/{id}/members`. The Predictor
must read **both** `realm-config.json` AND `realm-organizations.json`
to see the full picture.

Implication for the harness: the seam-design.md operational note
"export the full realm via partial-export … that export is
realm-config.json — the public artifact the predictor sees" is
**incomplete for organisation-touching fixtures**. The harness
should either (a) update the note to mention the
`realm-organizations.json` companion file, or (b) note this caveat
in a per-feature operational-notes appendix. Flagging as a candidate
edit to `keycloak-token-fixture-build/SKILL.md` operational notes.

## 2. The realm-level `organizationsEnabled` toggle is OFF by default even when the `ORGANIZATION` server feature is enabled

The builder prompt said "ORGANIZATION feature is already enabled" —
confirmed via `GET /admin/serverinfo`'s `features` list
(`{"name":"ORGANIZATION","enabled":true}`). However, the realm I
created via `POST /admin/realms {"realm":"adv-4","enabled":true}`
came up with `organizationsEnabled: false` on the realm
representation. The org-creation endpoint
(`POST /admin/realms/adv-4/organizations`) probably would have
either failed or stayed silently inert if I'd attempted it
pre-toggle.

Mitigation: explicitly PUT the realm with
`{"organizationsEnabled": true}` before creating organisations.
HTTP 204 confirmed acceptance; subsequent GET on the realm shows
`organizationsEnabled: true`.

Implication: the seam-design.md "build the realm, then export"
step (Step 7) does not call out per-feature realm-level toggles
that gate other admin endpoints. Worth adding to the operational
notes — every Keycloak feature with a realm-toggle (organisations,
admin permissions v2, etc.) needs the two-step "enable feature +
toggle realm" before its endpoints work.

## 3. The `scope` claim contains `organization` TWICE on the member's token (and ONCE on the non-member's)

Pre-mint expectation: `scope` claim contains a single occurrence of
each scope name that contributes a mapper, per invariant 2.
Observed:

- Member's access token: `"scope": "openid profile organization organization email"` (note **two** `organization` tokens).
- Non-member's access token: `"scope": "openid profile organization email"` (one `organization`).

This is unexpected and is itself a probable skill gap, separate
from the seam under test. Hypothesis (un-verified against source):
Keycloak's dynamic-organization-scope resolution
(scope-resolution.md L74-77 of the target skill mentions this)
attaches a *second* synthetic `organization` scope for the member
case — once because the static `organization` client scope is in
the default list, and once because the user has a membership that
triggers the dynamic-resolution path. The non-member case skips the
dynamic path (no membership), leaving only the static one.

For this fixture, the duplicate-token in `scope` is a side-effect,
not the seam under test. It is captured here so the diff-phase can
note it but should not score the fixture's primary commitment on
it. If the Predictor's commitment for `access_token_scope_claim_set`
treats `scope` as a SET (per the prediction-target.md instruction),
the dedup will hide this surprise from the diff. That's intentional
— the duplicate-string surprise warrants a *separate* fixture
(perhaps adv-5 or adv-6) to probe specifically.

## 4. The `id.token.claim` toggle on the OOTB mapper does cascade to `userinfo.token.claim` and `introspection.token.claim` defaults

Confirmed by inspection of the `organization` client scope's mapper
config (visible in `realm-config.json`):

```
"id.token.claim": "true",
"introspection.token.claim": "true",
"access.token.claim": "true",
"claim.name": "organization",
"jsonType.label": "String",
"multivalued": "true"
```

Note `userinfo.token.claim` is NOT in the config map. Per the target
skill's invariant 5, an unset `userinfo.token.claim` falls back to
`id.token.claim` — so the claim would also appear in the userinfo
response. This fixture doesn't probe userinfo; documenting for
completeness.

Also note `jsonType.label: "String"` combined with
`multivalued: "true"` produced a JSON array of strings. The mapper
serialiser interprets `jsonType.label` per-element, then wraps in
an array when `multivalued=true`. This is the mechanism behind the
observed shape #4 (`["acme"]`), but is **not stated anywhere in the
target skill** — that's the gap.

## 5. Determinism confirmed

Two mints per user, payloads `jq -S`'d, diffed after stripping
`iat, exp, auth_time, session_state, sid, nbf, jti`:

- Member access token: empty diff.
- Member ID token: only `at_hash` differs (expected: derived from
  the access-token signature whose `jti` UUID is per-mint).
- Non-member access token: empty diff.
- Non-member ID token: only `at_hash` differs.

The `organization` claim itself (the seam target) is stable across
mints. Fixture is deterministic.

## Reusable observations

1. **Partial-export gaps**: at minimum, organisations are not in
   the partial-export. Other Keycloak feature surfaces (authz
   resources?, fine-grained admin permissions?, workflows?) likely
   have the same issue. Future builders should `grep` the export
   for the entity they configured and fall back to per-resource
   GET if missing.

2. **Two-step feature enablement**: feature-flagged Keycloak
   functionality has both a server-level feature flag (via
   `--features=...` or `KC_FEATURES`) AND a per-realm toggle on
   the realm representation. Don't assume the realm-level toggle
   defaults to the server-level value.

3. **Duplicate scope tokens in the `scope` claim**: a real
   observable in Keycloak 26.5.5 when both static-attachment and
   dynamic-resolution paths contribute the same client scope. This
   is a candidate for adv-5 to probe — but it requires a different
   trap menu (sets vs. strings vs. dedup'd strings) and is out of
   scope for adv-4's seam.
