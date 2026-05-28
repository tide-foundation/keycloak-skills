# Diff — adversarial-7 (`oidc-hardcoded-role-mapper`)

## Headline

**Fixture verdict (post-edit): PASS.** After the skill edit (SKILL.md
invariant 14 + the role-injection-class subsection in
`references/mapper-execution.md` + `source-pointers.md` entries), a fresh
predictor committed 9/9 correct and reported the skill **text alone was
sufficient — no WebFetch needed**. Baseline run (pre-edit, preserved as
`prediction-precedit.json`) was the FAIL-SKILL-GAP below.

---

## Baseline headline (pre-edit)

**Pre-edit verdict: FAIL-SKILL-GAP.** The predictor committed correctly on
all nine fields, but only by invoking SKILL.md L8's WebFetch license to
read upstream source (`HardcodedRole`, `RoleResolveUtil`,
`AudienceResolveProtocolMapper`, `AbstractUserRoleMappingMapper`). The
predictor states plainly that the decisive seam is **not resolvable from
the SKILL.md text alone**: the skill catalogs `HardcodedClaim` but never
`HardcodedRole` (mapper-execution.md L161-191), and its toggle-gate
decision matrix (L99-106), read literally, forces **trap 1 — everything
absent on every surface**. A faithful reader who applies the documented
`fires_on_surface` pseudocode to a mapper whose config has no
`*.token.claim` key lands on the wrong answer. That a diligent predictor
reached the right answer via the source-fallback does not absolve the
text; the catalog gap is real and reproducible.

## Prediction vs. actual

| Field | Predicted | Actual | Match |
| --- | --- | --- | --- |
| access_token.realm_role | present | present (`realm_access.roles=["unassigned-realm-role"]`) | ✅ |
| access_token.client_role | present | present (`resource_access["adv7-resource"].roles=["resource-reader"]`) | ✅ |
| access_token.aud_resource | present | present (`aud="adv7-resource"`) | ✅ |
| id_token.realm_role | present | present (`realm_access.roles=["unassigned-realm-role"]`) | ✅ |
| id_token.client_role | absent | absent (no `resource_access`) | ✅ |
| id_token.aud_resource | absent | absent (`aud="adv7-client"`) | ✅ |
| userinfo.realm_role | present | present (`realm_access.roles=["unassigned-realm-role"]`) | ✅ |
| userinfo.client_role | absent | absent (no `resource_access`) | ✅ |
| bypass_relevance | irrelevant | irrelevant (user holds neither role; `fullScopeAllowed=false`; both injected anyway) | ✅ |

9/9 exact. Determinism check: access + ID tokens identical across two
mints after stripping volatile claims. `jti` prefix `onrtro:` (online,
refresh-token-context, ROPC) stable.

## Why this is FAIL-SKILL-GAP and not PASS

Per `references/verdict-rubric.md`, `pass` means "committed correctly
with skill citations." Here the load-bearing citation is to **upstream
source**, not the skill — the predictor's `fixture_target_compliance_note`
and final report both say the skill text would, read literally, force the
wrong answer. The rubric's `fail-skill-gap` covers "the skill's documented
contract should have been sufficient" but was not. The minimum corrective
edit is to add `HardcodedRole` to the catalog with the three structural
facts the predictor had to reconstruct from source.

## What the actual token revealed beyond the trap menu

Access-token `aud` is the bare string `"adv7-resource"` — the audience is
*only* the hardcoded client role's owning client, not `adv7-client`. The
audience-resolve mapper is the sole `aud` contributor here, and it adds
exactly the owning client of the injected client role. This confirms the
priority-20 → priority-30 ordering empirically: the client role injected
by `HardcodedRole` is in the resolved-roles cache before
`AudienceResolveProtocolMapper` reads it.

## Recommended edit (carried out)

Add a new SKILL.md invariant for role-injection mappers
(`oidc-hardcoded-role-mapper`, and by the same mechanism
`oidc-role-name-mapper`) capturing:

1. No surface toggles — overrides the transform methods and calls
   `setClaim` unconditionally; gated only by which surface *interfaces*
   it implements (`OIDCAccessTokenMapper` / `UserInfoTokenMapper` /
   `TokenIntrospectionTokenMapper`; **not** `OIDCIDTokenMapper`).
2. Writes into the `RoleResolveUtil` resolved-roles cache (`addRole`),
   not a claim path — surfaces only through the consumer role-list
   mappers (`UserRealmRoleMappingMapper` / `UserClientRoleMappingMapper`)
   and `AudienceResolveProtocolMapper`, each governed by **their** toggles.
3. The cache is session-scoped (keyed `RESOLVED_ROLES:<sessionId>:<clientId>`,
   surface-agnostic), so a role injected on the access-token pass is
   visible to the ID-token consumer even though `HardcodedRole` never
   runs on the ID surface.
4. Priority 20 (`PRIORITY_HARDCODED_ROLE_MAPPER`) < 30 (audience-resolve)
   < 40 (role-list mappers) makes the routing deterministic.
5. Bypasses `fullScopeAllowed` and the role allowlist — the injected role
   need not be held by the user.

Plus a catalog entry in `references/mapper-execution.md` and a note that
the `fires_on_surface` pseudocode applies only to toggle-gated
`AbstractOIDCProtocolMapper` mappers that do not override the transform
methods.
