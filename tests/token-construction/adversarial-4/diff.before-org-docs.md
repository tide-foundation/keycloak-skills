# Diff — adversarial-4 prediction vs actual

## Headline

| | Value |
| --- | --- |
| Skill prediction (`prediction.json`) | Member access+ID: trap **5**, `{"acme": {}}`. Nonmember access+ID: trap **1**, absent. Member access-token `scope` set `{openid, profile, organization, email}`; ID-token `scope` absent. |
| Actual on the wire | Member access+ID: trap **4**, `["acme"]`. Nonmember access+ID: trap **1**, absent. Member access-token `scope` literal `"openid profile organization organization email"` (set `{openid, profile, organization, email}` — duplicate `organization`). Nonmember access-token `scope` `"openid profile organization email"`. ID-token `scope` absent on both. |
| Fixture verdict | **FAIL-SKILL-GAP** — predictor committed to a specific wire shape for the `organization` claim (trap 5, `{"acme": {}}`) and was wrong (actual trap 4, `["acme"]`). The predictor's own `fixture_target_compliance_note` cites the exact gap: `mapper-execution.md` "Concrete setClaim overrides" L152-188 does not list `oidc-organization-membership-mapper`, so the skill text gives no anchor to pick between traps 4, 5, 6, 7. This is the motivating finding the fixture was built to surface. |

## Harness note

The prediction was produced by a fresh-context Agent spawned at the parent level, with no access to `actual-token*.json`, `actual-id-token-*.json`, `log*.txt`, `setup.md`, or `surprises.md`. The agent's tool call to write `prediction.json` was the first time the prediction was committed to the file. The predictor's final report also confirms it cited only the target-skill source files plus `realm-config.json`, `realm-organizations.json`, `request-*.json`, and `prediction-target.md`.

## Dim 1 — `organization` claim wire shape (the seam)

| Surface | Predicted trap | Predicted value | Actual trap | Actual value | Match? |
| --- | --- | --- | --- | --- | --- |
| Member access token | 5 | `{"acme": {}}` | 4 | `["acme"]` | ✗ |
| Member ID token | 5 | `{"acme": {}}` | 4 | `["acme"]` | ✗ |
| Nonmember access token | 1 | absent | 1 | absent | ✓ |
| Nonmember ID token | 1 | absent | 1 | absent | ✓ |

The predictor was right about the **structural** properties — same shape across access and ID tokens (per invariant 7 / invariant 9 reasoning), nonmember claim absent via NON_NULL drop (invariant 11) — and wrong on the specific JSON shape for the member. The misread was: assuming an object map `{"alias": {...}}` keyed by alias rather than a flat array of alias strings. The predictor was explicit that this commitment was LOW–MEDIUM confidence and cited the gap (`mapper-execution.md` non-exhaustive concrete-mapper catalog) honestly in `fixture_target_compliance_note`. That is precisely the diagnostic the rubric calls a fail-skill-gap rather than a fail-by-design — the prediction-target explicitly forbade "either an array or an object" as a non-prediction, so the predictor was forced to commit.

## Dim 2 — `scope` claim composition

| Surface | Predicted (set) | Actual (set) | Actual (literal) | Match? |
| --- | --- | --- | --- | --- |
| Member access token | `{openid, profile, organization, email}` | `{openid, profile, organization, email}` | `openid profile organization organization email` | ✓ on set; literal contains duplicate `organization` |
| Member ID token | absent | absent | (n/a) | ✓ |
| Nonmember access token | `{openid, profile, organization, email}` | `{openid, profile, organization, email}` | `openid profile organization email` | ✓ |
| Nonmember ID token | absent | absent | (n/a) | ✓ |

Set membership is fully nailed in all four positions. The predictor's chain — invariant 2 + `scope-resolution.md` L99-121 + `ClientScopeModel.java:109-112` default-true + `attachOIDCScope` re-prepend — was applied correctly to the four default scopes with `include.in.token.scope=true` (`profile`, `email`, `organization`, plus `openid` re-attached). The ID-token absence is correctly sourced from `base-claims.md` `generateIDToken` pseudocode (no `idToken.scope ← ...` line).

The **duplicate `organization` in the member's literal `scope` string is a fresh empirical finding** not represented in the prediction-target's commitment shape. It is consistent with the builder's `surprises.md` note that for a *member*, Keycloak attaches the `organization` client scope twice — once via static-default and once via dynamic-resolution against `scope=organization` (the dynamic-resolution path treats `organization` itself as a dynamic-scope namespace-prefix match against `Feature.ORGANIZATION` users with membership). The duplicate does not appear for the nonmember, which lines up — the dynamic resolution probably no-ops when the user has no membership in the named org. This is the right seam for adv-6 to probe directly (with `scope=organization:acme`) — bookmark it; not in scope to score here.

## Dim 3 — collateral claims (sanity check on the foundation)

| Claim | Actual (member access) | Skill-derivable from realm-config + invariants? | Notes |
| --- | --- | --- | --- |
| `iss` | `http://localhost:8080/realms/adv-4` | ✓ | `initToken` (base-claims.md), realm name from config |
| `sub` | UUID `fdda407b-…` | ✓ | `SubMapper` (invariant 1) — non-transient session |
| `azp` | `adv4-client` | ✓ | `initToken` |
| `jti` prefix `onrtro:` | persistent session, password grant | ✓ | invariant 12 — password grant, refresh-token issuance default |
| `sid` populated | persistent session | ✓ | invariant 12 — `useRefreshToken=true` path |
| `acr` | `"1"` | ✓ | `AcrProtocolMapper`, base-claims.md |
| `typ` | `Bearer` (access), `ID` (id) | ✓ | `formatTokenType` |
| `preferred_username`, `name`, `given_name`, `family_name`, `email`, `email_verified` | populated from user fields | ✓ | profile/email scope `UserPropertyMapper`s |
| no `realm_access`/`resource_access` | absent | ✓ | `fullScopeAllowed=false`, no scopeMappings intersect with user roles → empty role set → NON_NULL drop (invariants 6 + 11) |
| no `allowed-origins` | absent | ✓ | `web-origins` mapper no-ops when client has no `webOrigins` configured |
| `at_hash` on ID token only | present on ID, absent on access | ✓ | invariant 9 (`at_hash` out of model — computed over encoded JWS) |

The predictor's grounding in the rest of the construction pipeline is solid. The only place skill text failed it is the specific wire shape of `oidc-organization-membership-mapper`.

## Where the skill held / where it failed

**Held.** Invariants 1 (`sub` via SubMapper for non-transient sessions), 2 (scope claim composition + default-true), 6 (fullScopeAllowed → empty role intersection → NON_NULL-driven absence of `realm_access`/`resource_access`), 7 (ID-token base derived from transformed access token, plus per-surface mapper firing on `id.token.claim=true`), 9 (shape parity across surfaces in the absence of per-surface mapper toggles), 11 (NON_NULL drops null claims — applied cleanly to the nonmember case), 12 (`jti` prefix `onrtro:`, `sid` populated on password grant) all anchored real commitments and all matched the wire.

**Failed.** `mapper-execution.md` "Concrete setClaim overrides" (L152-188 per predictor's citation) is a non-exhaustive catalog that omits `oidc-organization-membership-mapper`. The predictor's `fixture_target_compliance_note` calls this out by name: "the skill provides no other passage that disambiguates between trap shapes 4, 5, 6, 7 for a member or between shapes 1, 2, 3 for a nonmember." With no anchor, the predictor inferred from secondary signals (Keycloak's tendency to namespace by alias for forward-compat, the mapper's `multivalued=true`+`jsonType.label=String` config flags) and landed on trap 5. The actual wire shape is the simpler trap 4 — a flat array of alias strings, the same shape Keycloak uses for the `roles` claim. The other organisation-membership-related signal in the skill (`scope-resolution.md` L22-28 — `OrganizationMembershipMapper` named in the dedup rule) is not about the mapper's output shape, just about its identity as a marker.

**Bonus finding (not scored, but skill-relevant.)** The duplicate `organization` token in the member's access-token `scope` claim is unexplained by current skill text. `scope-resolution.md`'s Step 1 candidate-set algorithm (L12-41) is `.distinct()` at the end (L41), which should suppress duplicates. The duplicate suggests either (a) static-default and dynamic-resolution produce two *distinct* `ClientScopeModel` instances for the same scope name (one from `client.getClientScopes(true)`, one from `tryResolveDynamicClientScope`) so `.distinct()` doesn't see them as equal, or (b) something in `getScopeString` is double-counting. Either way, the current skill text claims `scope-resolution.md` Step 1 deduplicates and would not predict this duplicate. This is a candidate seam for adv-6 to probe in depth — and a candidate clarification in `references/organizations.md`.

## Recommendation: skill changes from this fixture

**Author** a new reference: `skills/keycloak-token-construction/references/organizations.md`. Minimum content to make a fresh-context predictor land trap 4 / trap 1 on this fixture:

1. **Wire shape under default mapper config.** The OOTB `organization` client scope's `oidc-organization-membership-mapper` (with default flags: `claim.name=organization`, `jsonType.label=String`, `multivalued=true`, and `addOrganizationId` / `addOrganizationAttributes` unset / false) emits `organization` as a **flat JSON array of org alias strings**, e.g. `["acme"]`. Same shape on access token, ID token, userinfo, and introspection (per the surface toggles being true together) — invariants 7 and 9 hold.

2. **Zero-membership behaviour.** When the authenticated user holds zero organisation memberships, the mapper emits a null/empty source and NON_NULL (invariant 11) drops the `organization` claim from the wire entirely. The claim does NOT appear as `[]` or `{}`.

3. **Config flags that change the shape.** Note (even briefly) that the mapper exposes `addOrganizationId`, `addOrganizationAttributes` config flags. When unset (the OOTB default), the output is the alias-string array; when set, the shape changes to an object map keyed by alias (the variants the predictor mis-attributed to the default). Note that this fixture only verifies the OOTB-default flags; the flag-on shape is undocumented here and a candidate for a future fixture.

4. **The `scope` claim duplicate observation** — when `Feature.ORGANIZATION` is on and a user is a member of an org, the `organization` scope name can appear more than once in the `scope` claim's literal string because the static-default and dynamic-resolution attachment paths are not deduplicated by name alone. Flag as observed-pending-investigation; tighten in `references/organizations.md` after adv-6.

Also: add a numbered invariant to SKILL.md's "Critical invariants" list (likely #13) summarising the shape + zero-membership behaviour in one sentence with a forward link to `references/organizations.md`. And add `references/organizations.md` to SKILL.md's "Routing" section under a new bullet like "**Why is/isn't the `organization` claim present, and in what shape?**".

The minimum text change that would have flipped this fixture to PASS: a single line in the wire-shape reference saying "default-config emission shape is `["alias", ...]` (flat array of alias strings)". The rest is supporting context. After the docs edit lands, re-spawn this fixture's predictor to confirm it lands on trap 4 / trap 1 with the new anchor.
