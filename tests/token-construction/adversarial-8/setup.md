# adversarial-8 — `mapClaim` three-category routing for base-claim names

## The seam

Probes **invariant 15** of `keycloak-token-construction/SKILL.md` and the
new "Claim-name routing inside `setClaim`" section in
`references/mapper-execution.md`. Invariant 15 partitions single-segment
claim-path writes inside `OIDCAttributeMapperHelper.mapClaim` into three
categories: (a) **modifiable** — `sub`, `azp`, `acr`, `auth_time`, `aud`,
each dispatched through a dedicated property setter on the token object
(the mapper's value replaces the base value, single JSON key); (b)
**non-modifiable** — `jti`, `typ`, `iat`, `exp`, `iss`, `scope`, `nonce`,
`session_state`, each dispatched to a sentinel that logs `WARN Claim 'X'
is non-modifiable in IDToken. Ignoring the assignment for mapper 'M'.`
and drops the write; (c) **collision** — names that are dedicated
`@JsonProperty` fields on `JsonWebToken`/`IDToken`/`AccessToken` but are
absent from both maps (canonical case `sid`), where Jackson emits both
the dedicated field and the `otherClaims` entry, producing a duplicate
JSON key on the wire with no WARN.

The question the seam isolates: given a single ROPC password-grant
request that triggers three `oidc-hardcoded-claim-mapper` instances —
one writing each category — predict for each claim on each of two
surfaces (access token, ID token):

1. Which routing category applies.
2. The wire shape (`single_key_mapper_value` | `single_key_base_value` |
   `duplicate_keys` | `absent`).
3. The exact value a permissive last-wins parser would observe.

Plus the total count of WARN log lines per mint, the exact logger
category that emits them, and whether the literal phrase "in IDToken"
in the WARN message refers to the ID-token surface or the `IDToken`
Java class.

The misreads this seam catches:

- Reader treats every `oidc-hardcoded-claim-mapper` that passes the
  toggle gate as "mapper wins" (ignores the `tokenPropertySetters` /
  `notAllowedInToken` split entirely). Lands on trap 1.
- Reader knows `azp`/`iss`/`exp` are "server-owned" without distinguishing
  modifiable vs non-modifiable; treats all base claims as protected.
  Lands on trap 2.
- Reader applies the two-category split (modifiable + non-modifiable)
  but misses the third (collision); predicts `sid` cleanly takes the
  mapper's value. Lands on trap 3.
- Reader knows `sid` is special but predicts the dedicated-field write
  is suppressed instead of duplicating. Lands on trap 4.
- Reader reads "in IDToken" in the WARN message as referring to the
  ID-token surface and predicts only one WARN per mint. Lands on trap 5.

The correct combination (trap 6) requires applying every dimension of
invariant 15 plus the new mapper-execution.md section's explicit
clarification that the WARN's "in IDToken" refers to the Java class, not
the surface.

This fixture is the only one in the suite that probes claim-name routing
inside `setClaim` itself (prior fixtures all probe the upstream gate or
the downstream mapper output, not the helper's internal name dispatch).

## Realm / client / scope / mapper / user configuration

Realm: `adv-8` (fresh, prefixed `adv-` per the harness convention).

Client: `adv8-client`
- Confidential, `clientAuthenticatorType=client-secret`, secret
  `adv8-secret`.
- `directAccessGrantsEnabled=true` (ROPC).
- `serviceAccountsEnabled=false` (not needed; we want a regular user
  session for `sid` to be populated — invariant 12).
- `fullScopeAllowed=false` — keeps role-based mapping irrelevant to the
  seam; the only claims we care about are the three the hardcoded
  mappers write plus base claims.
- `standardFlowEnabled=true` only because admin REST API rejects clients
  with all flows disabled; doesn't affect this fixture.
- `defaultClientScopes`: realm defaults (basic, openid-related). No
  custom scopes — the seam is per-client mappers, not scope-driven
  assembly.

User: `adv8-user`
- Username `adv8-user`, password `adv8-pw`, email `adv8-user@example.com`,
  firstName `Adv`, lastName `Eight`, `emailVerified=true`. The email +
  firstName + lastName are required because the default
  `verify-profile` authenticator demands them at password-grant runtime
  (per adversarial-1's surprises.md). No realm roles or client roles
  beyond the realm defaults — they are irrelevant to the seam.

Client-level protocol mappers (three, all `oidc-hardcoded-claim-mapper`,
`openid-connect` protocol):

- `override-azp`:
  - `claim.name=azp`
  - `claim.value=OVERRIDDEN-AZP`
  - `jsonType.label=String`
  - `access.token.claim=true`
  - `id.token.claim=true`
  - `userinfo.token.claim=false` (irrelevant; we don't request userinfo
    here, but explicit-false makes the predictor's reading easier and
    eliminates an invariant-5 distraction)
  - `introspection.token.claim=false`

- `override-iss`:
  - `claim.name=iss`
  - `claim.value=https://evil.example.com`
  - `jsonType.label=String`
  - `access.token.claim=true`
  - `id.token.claim=true`
  - others false (same rationale)

- `override-sid`:
  - `claim.name=sid`
  - `claim.value=OVERRIDDEN-SID`
  - `jsonType.label=String`
  - `access.token.claim=true`
  - `id.token.claim=true`
  - others false

Mapper rationale: `oidc-hardcoded-claim-mapper` is the only mapper type
that writes a deterministic literal at a configurable claim path with
zero user/role/session dependency, which is exactly what the seam needs.
Each mapper writes one of the three categories' canonical name.
`override-iss` deliberately picks a value (`https://evil.example.com`)
that is observably distinct from the realm's actual issuer URL, so the
trap-menu distinction between "mapper wins" and "base value stands" is
visible in the wire. `override-sid` writes a literal string that cannot
match the runtime-generated `userSession.getId()`, so a duplicate-key
emission is visually unambiguous.

## The request

```
POST /realms/adv-8/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv8-client
client_secret=adv8-secret
username=adv8-user
password=adv8-pw
scope=openid
```

Single request. Yields `access_token` and `id_token` in the response.
`scope=openid` ensures `id_token` is returned alongside the access token
(the seam needs both surfaces). No `refresh_token` consumption — one
mint per evidence pass.

## Plausible outputs (the trap menu)

(Same six entries enumerated in `prediction-target.md`. The correct
entry is **6** — recorded here, NOT in `prediction-target.md`, so the
predictor can't read this file and short-circuit.)

1. All three mapper values win as single keys on both surfaces; 0 WARNs.
2. All three base values stand as single keys on both surfaces; 6 WARNs.
3. `azp` mapper-value, `iss` base + 2 WARNs, `sid` mapper-value single
   key (no WARN).
4. `azp` mapper-value, `iss` base + 2 WARNs, `sid` base single key (no
   WARN).
5. `azp` mapper-value, `iss` base + 1 WARN (ID surface only), `sid`
   duplicate keys.
6. **`azp` mapper-value single key on both surfaces; `iss` base single
   key on both surfaces + 2 WARNs per mint (one per surface where the
   toggle gate passes); `sid` duplicate keys on both surfaces (real
   session id from `@JsonProperty("sid")` first, then `OVERRIDDEN-SID`
   from `otherClaims` via `@JsonAnyGetter`) with no WARN; WARN logger
   category `org.keycloak.protocol.oidc.mappers.OIDCAttributeMapperHelper`;
   "in IDToken" refers to the `IDToken` Java class.**

## Minimum specificity to pass

See `prediction-target.md`. Briefly: every field concrete, no hedges
unless skill-cited. The predictor must distinguish the three categories,
correctly count WARN lines, name the logger category, and resolve the
"in IDToken" phrasing.

## Determinism check plan

Mint the token twice. After stripping `iat`, `exp`, `jti` suffix
(after `:`), `auth_time`, `session_state`, `sid` (note: this strips
*both* `sid` occurrences in the duplicate case — see below), and `nbf`,
the two decoded bodies must match.

**Critical:** `sid` is in the default strip set, but this fixture's
seam *tests* `sid`. The field under test is **the count of `"sid":`
keys in the raw JSON**, not the value at the (last-wins) key. Both mints
should produce exactly 2 `"sid":` keys; both mints should produce the
mapper-write value `OVERRIDDEN-SID` as one of the two values. The other
`sid` value will be a fresh random `userSession.getId()` UUID per mint
— that's expected and is what the strip handles.

The fixture fails determinism if:
- Either mint produces only one `"sid":` key (the duplicate-key behavior
  is intermittent — would be a Jackson serialization quirk).
- Either mint produces three or more `"sid":` keys (would indicate the
  helper writes the same `otherClaims` key twice, or there's a third
  serialization mechanism).
- The two mints disagree on the routing category for any other claim
  (e.g., one mint has `azp` single-key, the other has `azp`
  duplicate-key — would indicate non-deterministic mapper dispatch).

I'll capture two decoded raw JSON strings (not jq-parsed, because jq
collapses duplicate keys to last-wins) and grep `"sid":` key counts in
each.

## Resolution after capture

[Filled in AFTER minting.]
