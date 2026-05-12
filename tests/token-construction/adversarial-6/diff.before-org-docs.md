# Diff — adversarial-6 prediction vs actual

## Headline

| Request | Predicted | Actual | Verdict |
| --- | --- | --- | --- |
| `:acme` | trap 1a / 1-scope-A; `["acme"]` both surfaces; scope `"openid profile email organization:acme"` | trap 1a / 1-scope-A; `["acme"]` both surfaces; scope `"openid organization:acme email profile"` | **PASS** — wire shape exact, dedup behaviour exact, HTTP 200 exact. Scope-literal order varies per mint per builder's `surprises.md` §2 — legitimate invariant-10-shape hedge applies. |
| `:*` | trap 2a / 2-scope-A; `["acme", "globex"]` both surfaces; scope `"openid profile email organization:*"` | trap 2a / 2-scope-A; `["globex", "acme"]` both surfaces; scope `"openid email profile organization:*"` | **FAIL-SKILL-GAP** on order — predictor committed `["acme","globex"]` (alphabetical / insertion-order convergent for this fixture); actual is `["globex","acme"]`. Set + dedup + HTTP all correct. Predictor flagged the gap honestly: invariant 10 governs mapper-sort ties but not intra-mapper Set-iteration over user-state collections (membership UUIDs in this case). |
| `:nonexistent` | trap 3b / 3-scope-C; HTTP 200, claim absent, scope `"openid profile email"` | trap 3a (`HTTP 400 invalid_scope`) | **FAIL-SKILL-GAP** — predictor read scope-resolution.md L156-159 as "registered prefix → silent skip, mint succeeds with absent claim." Actual: pre-flight `isValidScope` calls into `tryResolveDynamicClientScope` and rejects on unresolvable alias even when the prefix is registered. The skill's L86-97 vs L156-159 boundary is ambiguous on this case. |

**Overall fixture verdict: FAIL-SKILL-GAP** (mixed). Request 1 is a clean PASS. Requests 2 and 3 expose two distinct skill-text ambiguities — both flagged by the predictor in `open_skill_gaps_flagged_for_maintainer` *before* the diff was scored.

## Harness note

Fresh-context Predictor spawned at parent level. Forbidden file list explicitly included all sibling adversarial fixtures (adv-2/3/4/5) to prevent cross-fixture contamination — in particular the predictor could not read adv-5's `["zeta","acme"]` order observation, which would have hinted that intra-mapper order is non-alphabetical. The predictor's `fixture_target_compliance_note` confirms it consulted only the seven permitted inputs.

## Dim 1 — request 1 (`scope=openid organization:acme`)

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Outcome | success (HTTP 200) | success (HTTP 200) | ✓ |
| Access-token `organization` | `["acme"]` | `["acme"]` | ✓ |
| ID-token `organization` | `["acme"]` | `["acme"]` | ✓ |
| Scope claim — multiset | `{openid, profile, email, organization:acme}` | `{openid, profile, email, organization:acme}` | ✓ |
| Scope claim — `organization` (bare) present? | no (dedup'd) | no (dedup'd) | ✓ |
| Scope claim — literal order | `"openid profile email organization:acme"` | `"openid organization:acme email profile"` | ✗ on literal — hedge-eligible per invariant 10 |
| HTTP 4xx fields | n/a | n/a | ✓ |

The predictor nailed the dedup rule (scope-resolution.md L22-28 — drops the static default `organization` because `organization:` prefix is in scopeParam), the dynamic-scope resolution via `tryResolveDynamicClientScope` (L36, L679-695), the mapper-set assembly (mapper-set-assembly.md L17-27), the per-surface mapper firing under `access.token.claim=true` + `id.token.claim=true`, and the NON_NULL non-drop on a non-empty array. The scope-claim composition was exact on multiset; the literal-string order is an invariant-10-shaped hedge — the same shape adv-2 successfully hedged on.

**Pass on this dimension.** The skill text was sufficient.

## Dim 2 — request 2 (`scope=openid organization:*`)

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Outcome | success (HTTP 200) | success (HTTP 200) | ✓ |
| Org claim — set | `{acme, globex}` | `{acme, globex}` | ✓ |
| Org claim — order | `["acme", "globex"]` | `["globex", "acme"]` | ✗ on order |
| ID-token order | `["acme", "globex"]` | `["globex", "acme"]` | ✗ on order |
| Scope claim multiset | `{openid, profile, email, organization:*}` | `{openid, profile, email, organization:*}` | ✓ |
| Scope claim — bare `organization` present? | no (dedup'd) | no (dedup'd) | ✓ |

The set commitment is exact. The dedup-on-wildcard finding is exact. The order commitment is wrong — and importantly, this disambiguates the skill's invariant 10 in a way the predictor explicitly flagged.

Adv-5 observed `["zeta", "acme"]` (zeta inserted first, then acme) for a different multi-membership fixture; adv-6 observes `["globex", "acme"]` (acme inserted first, then globex). Both fixtures are deterministic across many mints, but the two orderings together rule out *every* simple rule: insertion-order, reverse-insertion, alphabetical, reverse-alphabetical. The only remaining explanation that fits both observations is **HashSet iteration over the orgs' UUIDs** — exactly the same mechanism the skill describes under invariant 10 for mapper-sort ties.

The predictor explicitly cited this gap in `open_skill_gaps_flagged_for_maintainer` item 3: "Invariant 10 governs mapper-sort ties, not intra-mapper value-list ordering. Request 2 requires picking an order; the skill text does not anchor the choice." That's exactly right. The fix is to extend invariant 10 (or note in `references/organizations.md`) that the same HashSet contract governs the organisation-membership iteration emitted by `oidc-organization-membership-mapper` under wildcard resolution.

**Fail-skill-gap on the order sub-dimension; pass on set + dedup + HTTP.**

## Dim 3 — request 3 (`scope=openid organization:nonexistent`)

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Outcome | success | **HTTP 400** | ✗ |
| HTTP status | n/a | 400 | n/a |
| Error code | n/a | `invalid_scope` | n/a |
| Trap index | 3b (silent skip → mint with absent claim) | 3a (pre-flight reject) | ✗ |

This is the cleanest skill-text-ambiguity result in the entire three-fixture sweep. The predictor's reasoning chain:

1. Dedup rule (L22-28) drops static `organization` because the prefix matches — **correct**.
2. `tryResolveDynamicClientScope('organization:nonexistent')` returns null because the alias doesn't exist — **correct**.
3. L156-159 says "Dynamic scope rejected by `tryResolveDynamicClientScope`: silently skipped by Step 1. **If the name is otherwise unknown, pre-flight isValidScope still rejects.**"
4. Predictor's reading: "'organization:' prefix is registered, so the name is NOT 'otherwise unknown' → silent skip, request succeeds." → predicted HTTP 200 + claim absent.

The actual behaviour is the opposite: pre-flight `isValidScope` invokes the same resolver and rejects on the unresolvable alias even when the prefix is registered. So "otherwise unknown" in the skill text actually means "the alias does not resolve" rather than "the prefix is not registered." This is a load-bearing ambiguity in a single phrase — exactly the kind of thing a worked example would harden.

The predictor caught this gap themselves: `open_skill_gaps_flagged_for_maintainer` item 4: "A worked example showing exactly which inputs route to which outcome (e.g., 'org:nonexistent → silently skipped because the prefix is registered; bogus-scope-without-prefix → pre-flight reject') would be more defensible." They flagged the right gap; they just guessed wrong on which side of the line `organization:nonexistent` lands.

**Fail-skill-gap on outcome.** The fix is a worked example in scope-resolution.md (or `references/organizations.md`) showing that `tryResolveDynamicClientScope` returning null on a registered-prefix dynamic scope still triggers pre-flight rejection, contrary to a natural reading of "otherwise unknown."

## Dim 4 — collateral claims

Same shape across all three requests' tokens (where they succeeded): `iss`, `sub` (via SubMapper, invariant 1), `azp`, `jti` prefix `onrtro:` (invariant 12, password grant persistent session), `sid` populated, `acr`, `typ`, `preferred_username`, profile/email fields. No `realm_access`/`resource_access` (fullScopeAllowed=false + no scopeMappings → invariant 6 + 11). All consistent with the rest of the construction pipeline being well-anchored in the skill.

## Where the skill held / where it failed

**Held.** Invariants 1, 2, 6, 7, 9, 10 (for mapper-sort ties), 11, 12 all anchored correct commitments. The dedup rule (scope-resolution.md L22-28) is a strong anchor — the predictor read it correctly for both request 1 (specific alias) and request 2 (wildcard) and got the dedup behaviour exactly right both times. The dynamic-scope resolution path (L35-37, L679-695) is enough scaffolding for request 1's wire-shape inference even without an explicit mapper catalog entry.

**Failed in three places**:

1. **Intra-mapper iteration order** (request 2). Invariant 10 is scoped to `ProtocolMapperUtils.compare` (mapper-sort ties). The same HashSet-iteration mechanism applies to the org-membership Set inside `oidc-organization-membership-mapper`'s `setClaim`, but the skill doesn't say so. Cross-fixture evidence: adv-5 saw `["zeta","acme"]`, adv-6 sees `["globex","acme"]` — together, these refute all naive ordering hypotheses and confirm a UUID-hash-bucket pattern (invariant 10-shape).

2. **Pre-flight ambiguity** (request 3). The L156-159 phrase "If the name is otherwise unknown" leaves room for the misread that registered-prefix + unresolvable-alias = silent skip. The actual rule is registered-prefix + unresolvable-alias = pre-flight reject. The skill needs a worked example or a clarifying sentence.

3. **No explicit wire-shape catalog entry for `oidc-organization-membership-mapper`** (carried forward from adv-4 / adv-5). The predictor inferred `["alias"]` from `multivalued=true` + `jsonType.label="String"` plus general Keycloak conventions, and it was right — but at LOW–MEDIUM confidence. A `references/organizations.md` entry would close this.

## Recommendation: skill changes from this fixture

Adv-6 adds three more bullet points to the `references/organizations.md` brief that adv-5 motivated. Combining adv-4/5/6 findings, the new reference should include (in addition to the items recommended in adv-4 and adv-5 diffs):

A. **The three scope-param forms** (concrete table):
   - `scope=organization` (unqualified, static path): emits `organization` claim ONLY for single-membership users. Multi-membership and zero-membership both yield NON_NULL drop → claim absent. The static-default scope provides the mapper; no dynamic resolution involved.
   - `scope=organization:*` (wildcard, dynamic path): emits the `organization` claim with all of the user's memberships. Order is HashSet-iteration over org UUIDs (invariant-10-shape, JVM-dependent across fixtures — verified empirically by adv-5 vs adv-6 ordering divergence). The dedup rule at scope-resolution.md L22-28 drops the static-default `organization` from candidates; only the dynamic-resolved scope (named `organization:*`) survives in the literal `scope` claim.
   - `scope=organization:<alias>` (specific, dynamic path): emits `organization` claim narrowed to `["<alias>"]` if the user is a member; if the user is not a member of that org, `tryResolveDynamicClientScope` returns null and the request is rejected pre-flight with HTTP 400 `invalid_scope` (NOT silently skipped, NOT minted with absent claim). The dedup rule also fires here.

B. **Clarify scope-resolution.md L156-159 with a worked example**: pre-flight `isValidScope` calls into `tryResolveDynamicClientScope` for dynamic-scope-shaped tokens. If that returns null (alias doesn't exist for a registered prefix), the pre-flight branch still rejects, not silently skips. The "silently skipped by Step 1" wording in L156-157 refers to Step 1 of the post-auth construction pipeline (which never runs in the rejection case) — pre-flight runs *before* Step 1 and gates whether construction starts at all.

C. **Extend invariant 10 (or add a sibling invariant)** to cover within-mapper iteration over user-state Sets. The skill's current text scopes invariant 10 narrowly to mapper-sort ties; the same HashSet contract governs `oidc-organization-membership-mapper`'s emission order under wildcard resolution. The adv-5 + adv-6 cross-fixture divergence (`["zeta","acme"]` vs `["globex","acme"]`) is the empirical anchor.

The minimum text change that would flip adv-6 to mostly-PASS: (A) — a concrete three-form table in `references/organizations.md`. The order question would still be a legitimate hedge (matching adv-2's scope-order hedge), and the worked example for L156-159 (B) is the additional change needed to close request 3.

After the docs land, re-spawn this fixture's predictor and confirm:
- Request 1 stays PASS.
- Request 2 lands with a clean invariant-10 order-hedge (pass per the rubric — adv-2 precedent).
- Request 3 commits to trap 3a (HTTP 400 `invalid_scope`).
