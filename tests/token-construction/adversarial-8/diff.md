# Diff — adversarial-8 prediction vs actual

## Headline

| | Value |
| --- | --- |
| Skill prediction (fresh-context agent, `prediction.json`) | All 13 fields committed concretely (per-claim per-surface routing/wire-shape/value, WARN count, logger category, "in IDToken" semantics) |
| Actual on the wire (`actual-token-access-raw.txt`, `actual-token-id-raw.txt`, `log.txt`) | All 13 fields match the prediction exactly |
| Fixture verdict | **PASS** — fresh predictor reasoned from SKILL.md invariant 15 + the new `references/mapper-execution.md` claim-name-routing section and landed every commitment, including the duplicate-key ordering, the "IDToken Java class" semantics, and the exact WARN count. Skill text alone was sufficient. |

## Harness note

This prediction was produced by a fresh-context Agent spawned at the
parent level (`general-purpose` subagent), with no access to
`actual-token-access.json`, `actual-token-id.json`,
`actual-token-access-raw.txt`, `actual-token-id-raw.txt`, `log.txt`,
`setup.md`, or any other adversarial-N actual-token files. The agent's
final report and `prediction.json` write were the first time the
prediction was committed. The agent's reasoning narrative shows it
walked the construction pipeline from scope-resolution through
generateIDToken (steps 1-6) before scoring each commitment.

## Dim 1 — Per-claim, per-surface routing and wire shape

| Surface | Claim | Predicted routing | Actual routing | Predicted wire shape | Actual wire shape | Predicted last-wins value | Actual last-wins value | Match? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| access_token | azp | modifiable | modifiable | single_key_mapper_value | single_key_mapper_value (1 `"azp":` key in raw) | `OVERRIDDEN-AZP` | `OVERRIDDEN-AZP` | ✓ |
| access_token | iss | non-modifiable | non-modifiable | single_key_base_value | single_key_base_value (1 `"iss":` key) | `http://localhost:8080/realms/adv-8` | `http://localhost:8080/realms/adv-8` | ✓ |
| access_token | sid | collision | collision | duplicate_keys | duplicate_keys (2 `"sid":` keys in raw) | `OVERRIDDEN-SID` | `OVERRIDDEN-SID` | ✓ |
| id_token | azp | modifiable | modifiable | single_key_mapper_value | single_key_mapper_value | `OVERRIDDEN-AZP` | `OVERRIDDEN-AZP` | ✓ |
| id_token | iss | non-modifiable | non-modifiable | single_key_base_value | single_key_base_value | `http://localhost:8080/realms/adv-8` | `http://localhost:8080/realms/adv-8` | ✓ |
| id_token | sid | collision | collision | duplicate_keys | duplicate_keys (2 keys) | `OVERRIDDEN-SID` | `OVERRIDDEN-SID` | ✓ |

The predictor's `reasoning` field walks the pipeline step-by-step
(initToken sets base sid as real UUID; transformAccessToken runs the
three hardcoded-claim mappers; mapClaim routes each name through
`tokenPropertySetters` lookup with the correct outcome per category;
generateIDToken seeds the IDToken from the transformed access token and
re-runs the mappers on the ID surface). Every step's logical
consequence aligned with the raw-body evidence.

## Dim 2 — sid duplicate-key serialization order

| Origin | Predicted | Actual (from raw body) | Match? |
| --- | --- | --- | --- |
| First `"sid":` key | `dedicated_jsonproperty_field` (real session UUID) | First `"sid":` in raw is `"cgHk-xITz7JA4-ydf-G_lY72"` (the real session UUID from `JsonWebToken.sid` field's `@JsonProperty("sid")`) | ✓ |
| Last `"sid":` key | `other_claims_anygetter` (`OVERRIDDEN-SID`) | Last `"sid":` in raw is `"OVERRIDDEN-SID"` (the mapper write via `otherClaims["sid"]` serialized through `@JsonAnyGetter`) | ✓ |

The order is the same on both surfaces: dedicated field first, then
`otherClaims` entry. This matches Jackson's default behaviour for
beans with `@JsonAnyGetter` (declared @JsonProperty fields are emitted
during normal bean serialization, then `@JsonAnyGetter`-annotated
methods are appended last).

## Dim 3 — WARN log accounting

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `warn_log_lines_per_mint` | `2` | `2` (`log.txt` contains exactly two lines, timestamps 08:20:47,608 and 08:20:47,612 — 4ms apart, one per surface pass) | ✓ |
| `warn_logger_category` | `org.keycloak.protocol.oidc.mappers.OIDCAttributeMapperHelper` | `[org.keycloak.protocol.oidc.mappers.OIDCAttributeMapperHelper]` (exact string match in both log lines) | ✓ |
| `warn_log_surface_meaning` | `IDToken_java_class` | Confirmed indirectly: the WARN fired twice (once during the access-token mapper pass at 08:20:47,608 and once during the ID-token mapper pass at 08:20:47,612). If the literal "in IDToken" constrained the WARN to the ID-token surface only, we'd see one line per mint, not two. | ✓ |

The WARN message literal in both log lines: `Claim 'iss' is
non-modifiable in IDToken. Ignoring the assignment for mapper
'override-iss'.` — matches the format predicted from invariant 15(b).
The other two mappers (`override-azp`, `override-sid`) emit no log lines,
confirming that the modifiable (a) and collision (c) categories are
silent.

## Dim 4 — Collateral claims (sanity check on the foundation)

| Claim | Actual on AT | Skill-derivable from realm-config? | Notes |
| --- | --- | --- | --- |
| `sub` | `7131faf9-d68c-4e63-8d76-cf0f668aa27b` (real user id) | ✓ | invariant 1: non-transient session → SubMapper writes `sub` from `user.getId()`. The skill correctly anticipates `sub` is populated (the predictor noted SubMapper but didn't need to commit to the exact UUID). |
| `typ` | `Bearer` (AT) / `ID` (ID) | ✓ | base-claims.md L43 / L78 — both base claims, untouched by any mapper here. |
| `acr` | `1` | ✓ | base-claims.md L49 — `STEP_UP_AUTHENTICATION` is off, password grant is fresh auth → `acr=1`. |
| `scope` | `openid profile email` | ✓ | scope-resolution.md + invariant 2 — assigned default scopes with `isIncludeInTokenScope=true`, plus the OIDC `openid` re-attach. |
| `jti` prefix | `onrtro:` | ✓ | invariant 12 — password grant with persistent session, online refresh token route. |
| AT `aud` | absent | ✓ | invariant 6 + invariant 11 — `fullScopeAllowed=false` and the user has no client roles whose owning client would be added by `AudienceResolveProtocolMapper`. The mapper fires but writes null; NON_NULL drops the claim. (Predictor did not explicitly commit to `aud`-absence but the foundation is consistent.) |
| ID `aud` | `adv8-client` | ✓ | base-claims.md L80 — `generateIDToken` seeds `idToken.aud ← client.getClientId()` directly. |

The predictor's `shapes_ruled_out_by_skill` entry on "azp on the ID
token shows the base value (client_id)" cleanly invoked invariant 7
(ID-token base seeded from transformed access token) AND the re-run of
ID-token-surface mappers — the right composition of two invariants.

## Where the skill held / where it failed

The skill's text was sufficient for a fresh-context agent to commit
correctly on every dimension. In particular:

- **Invariant 15(a)** gave the predictor the exact dispatch table for
  modifiable names (`sub`, `azp`, `acr`, `auth_time`, `aud`) and the
  named setter (`token.issuedFor`) for the `azp` case.
- **Invariant 15(b)** gave the exact WARN message format, the
  cardinality rule ("once per surface where the mapper's toggle gate
  passed"), and the explicit clarification that "in IDToken" refers
  to the Java class. The cardinality rule produced the 2-WARN
  prediction directly; the class-vs-surface clarification defeated
  trap 5.
- **Invariant 15(c)** gave the canonical `sid` collision example with
  the empirical token-body shape, which the predictor used to commit
  to both the duplicate-key wire shape and the dedicated-field-first
  serialization order.

The predictor invoked **seven** distinct passages across SKILL.md and
references/ in its `skill_passages_invoked` field. Notably it composed
invariant 15 with invariant 12 (to confirm that `sid` is retained on
password grant, which is the precondition for the duplicate-key
emission — without retained `sid`, NON_NULL would drop the dedicated
field and only `otherClaims["sid"]` would render, giving a single-key
result that would look like a clean override). That composition is
exactly the kind of reasoning the skill is designed to support.

The predictor flagged one minor ambiguity (see Recommendation).

## Recommendation: skill changes from this fixture

**Verdict: PASS.** No required skill changes. This fixture is a positive
regression test — any future edit that weakens invariant 15's category
table, the WARN cardinality rule, the "in IDToken" clarification, or
the empirical `sid` shape pin should flip this fixture to fail.

**Optional one-liner improvement** (predictor flagged this in its final
report and again in its `reasoning` field, item (i)): the skill pins
the duplicate-key serialization order (dedicated `@JsonProperty` first,
`@JsonAnyGetter` last) via the empirical example in
`references/mapper-execution.md` (subsection (c)) but not as a stated
Jackson rule. A predictor that didn't notice the example might have
been unable to commit to `first_key_serialization_origin`. Concrete
suggestion: add one sentence to subsection (c) immediately before or
after the empirical body shape, e.g. "Jackson's default bean
serialization emits declared `@JsonProperty` getters before
`@JsonAnyGetter`-annotated methods, so the dedicated field's value is
always the first occurrence of the duplicate key and the `otherClaims`
entry is always the last." This is a defensive improvement; the
fixture passed without it.

The fixture becomes invariant 15's covered-by entry in
`invariant-coverage.md` (PASS).
