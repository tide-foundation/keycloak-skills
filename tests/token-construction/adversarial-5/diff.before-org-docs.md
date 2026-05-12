# Diff — adversarial-5 prediction vs actual

## Headline

| | Value |
| --- | --- |
| Skill prediction (`prediction.json`) | Access + ID: trap **7**, `["acme", "zeta"]` as a set commitment with invariant-10 order hedge. `scope` literal `"openid profile organization email"` (order-hedged), multiset `{openid:1, profile:1, organization:1, email:1}`, `organization` appears **once**. |
| Actual on the wire | Access + ID: trap **1**, `organization` claim **absent entirely**. `scope` literal `"openid profile email organization"`, multiset `{openid:1, profile:1, organization:1, email:1}`, `organization` appears **once**. |
| Fixture verdict | **FAIL-SKILL-GAP** — predictor committed to claim being PRESENT with both aliases (trap 7) and ruled out trap 1 (absent) explicitly using invariant 11 + the mapper's non-null input. Actual is trap 1. The skill text does not document that the unqualified static `scope=organization` path emits null (and NON_NULL drops the claim) when the user is a member of more than one org. Alias-qualified dynamic resolution (`scope=organization:*` or `scope=organization:<alias>`) is required to surface multi-membership — a behaviour completely undocumented in the skill. |

## Harness note

The prediction was produced by a fresh-context Agent spawned at the parent level, with no access to `actual-token.json`, `actual-id-token.json`, `actual-token-mint2.json`, `actual-id-token-mint2.json`, `log*.txt`, `setup.md`, or `surprises.md`. The agent was also forbidden from reading any adv-2/3/4 files (cross-fixture contamination protection — adv-4 covers the single-membership baseline and would have leaked the array-of-strings shape if read). The agent's tool call to write `prediction.json` was the first time the prediction was committed to the file.

## Dim 1 — `organization` claim wire shape and value (the seam)

| Surface | Predicted trap | Predicted value | Actual trap | Actual value | Match? |
| --- | --- | --- | --- | --- | --- |
| Access token | 7 | `["acme", "zeta"]` (set with order hedge) | 1 | absent | ✗ |
| ID token | 7 | `["acme", "zeta"]` (set with order hedge) | 1 | absent | ✗ |

The predictor reasoned about the wrong dimension. It correctly identified that the skill doesn't pin order (hedge via invariant 10 by analogy to within-mapper Set iteration — a defensible extension), and correctly ruled out object shapes via `jsonType.label="String"`. It did NOT anticipate that the mapper could write *null* for a multi-membership user under the unqualified static-scope path. The predictor explicitly ruled out trap 1 with this reasoning in `shapes_ruled_out_by_skill`:

> "The mapper config has access.token.claim=true and id.token.claim=true. multivalued='true' means the mapper is configured to emit a collection, not a scalar that could be null-suppressed for the N>1 case. There is no skill passage suggesting oidc-organization-membership-mapper short-circuits to null on multi-membership. Invariant 11 (NON_NULL drop) only fires if the in-memory value is null; with two memberships there is content to write."

That reasoning is internally coherent and the skill provides no anchor that would refute it. **The skill is silent on the entire alias-qualifier mechanism**: the static `scope=organization` invokes a different mapper code path than the dynamic `scope=organization:*` / `scope=organization:<alias>` resolution, and only the latter is wired to handle multi-membership. The static path's behaviour for multi-membership users is to emit null → NON_NULL drop → claim absent on the wire.

The builder's out-of-band probes (documented in `surprises.md`) confirmed this empirically:
- `scope=openid organization` (this fixture's request) → `organization` claim absent.
- `scope=openid organization:*` → `["zeta", "acme"]` (insertion order, stable across 5 mints).
- `scope=openid organization:acme` → `["acme"]`.

Single-membership adv-4 saw `["acme"]` under unqualified `scope=organization` only because the auto-resolution path happened to converge on the unique membership. With N=2, that path has no rule to pick and emits null.

## Dim 2 — `scope` claim composition

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Multiset | `{openid:1, profile:1, organization:1, email:1}` | `{openid:1, profile:1, organization:1, email:1}` | ✓ |
| `organization` count | 1 | 1 | ✓ |
| Literal order | `"openid profile organization email"` | `"openid profile email organization"` | ✗ on literal (but predictor pre-hedged this as not-pinned per invariant 10) |

The predictor nailed the multiset, the once-vs-twice question, and explicitly pre-hedged the literal string order with an invariant-10-style citation. The literal-order mismatch is a **legitimate hedge**, not a fail: the prediction-target's framing explicitly admits a multiset commitment + acknowledged order hedge as a structurally complete answer. This is the same shape adv-2's scope-order hedge took.

This dimension is a clean pass on multiset, with a contract-derivable hedge on string-order. No skill change needed for the scope-claim dimension.

The contrast against adv-4 is also notable: adv-4 saw `organization` appear **twice** in the literal scope string for the single-membership user, but **once** here for the multi-membership user. The difference is the static-default vs dynamic-resolution attachment paths — both attach for single-membership (collision in the scope name aggregation), only static attaches here (because the dynamic-resolution path on unqualified `organization` doesn't match a single org). That cross-fixture observation belongs in `references/organizations.md`.

## Dim 3 — collateral claims (sanity check on the foundation)

| Claim | Actual (access) | Skill-derivable? | Notes |
| --- | --- | --- | --- |
| `iss` | `http://localhost:8080/realms/adv-5` | ✓ | `initToken` |
| `sub` | UUID `2ad079d8-…` | ✓ | `SubMapper`, invariant 1 (non-transient) |
| `azp` | `adv5-client` | ✓ | `initToken` |
| `jti` prefix `onrtro:` | persistent session | ✓ | invariant 12 — password grant default |
| `sid` populated | persistent session | ✓ | invariant 12 |
| `acr` | `"1"` | ✓ | `AcrProtocolMapper` |
| `typ` | `Bearer`/`ID` | ✓ | `formatTokenType` |
| `preferred_username`, `name`, given/family/email | populated | ✓ | profile/email mappers |
| no `realm_access`/`resource_access` | absent | ✓ | `fullScopeAllowed=false` + no scopeMappings → empty roles → NON_NULL drop |

The wider construction pipeline is solid; only the org-membership-mapper-specific behaviour escapes the skill.

## Where the skill held / where it failed

**Held.** Invariants 1, 2, 6, 7, 9, 11, 12 all anchored correct collateral commitments. The predictor's reasoning chain — scope-resolution.md Step 1-3, mapper-set-assembly, mapper-execution decision matrix, NON_NULL serialisation — was applied cleanly and would have produced the right answer if the mapper's null-emission behaviour were documented.

**Failed.** Two distinct gaps converged on this fixture:

1. **The biggest one (unique to adv-5)**: the skill text contains no mention of the alias-qualifier requirement for the `organization` claim under multi-membership. The static `scope=organization` works only when the user has exactly one membership (lucky-path); for multi-membership, the static path emits null and NON_NULL drops the claim. The skill's three current paragraphs about organisations (scope-resolution.md L22-28, L35-37, L74-77) are about the dedup rule and feature-flag, not about this fundamental behaviour. A skill reader writing a JWT mock for a multi-member Keycloak user would get this wrong every time.

2. **The shape gap (shared with adv-4)**: even when the claim IS present (under `:*` or `:<alias>`), the wire shape `["alias", ...]` is not pinned by the skill — predictor confidently inferred it from `multivalued=true`+`jsonType.label=String` conventions but committed at LOW–MEDIUM confidence per its own note.

The order-hedge on the scope literal string is correct hedging behaviour (invariant 10 / HashSet iteration shape) — adv-2 demonstrated this is the right shape of hedge.

## Recommendation: skill changes from this fixture

Adv-5 elevates the recommendation from "document the wire shape" to "document the entire alias-qualifier mechanism". Concretely, `references/organizations.md` should include:

1. **Static `scope=organization` (unqualified)**: emits the `organization` claim only when the user has exactly one organisation membership; emits null (→ NON_NULL drop) for zero membership AND for multi-membership. Single-membership behaviour: `["alias"]` (array of one alias string). Multi-membership behaviour under this path: claim absent.

2. **Dynamic `scope=organization:*`**: emits the `organization` claim with all the user's memberships as `["alias1", "alias2", ...]`. Order is **insertion-order on membership creation**, stable across mints (per adv-5's 5-mint determinism probe — cite the empirical evidence). This is the path multi-membership users must take to surface all their memberships.

3. **Dynamic `scope=organization:<alias>`**: narrows to that specific alias; emits `["<alias>"]` if the user is a member, or claim absent if not.

4. **The dedup rule clarification (scope-resolution.md L22-28)**: the rule drops a default scope from candidates when its `name + ":"` appears as a dynamic-scope prefix in `scopeParam`. Worked example: `scope=openid organization:acme` matches the dedup prefix `organization:` for the static `organization` scope, so the static one is dropped and the dynamic-resolved one replaces it. Without this clarification the rule is opaque.

5. **The `scope` claim duplicate (cross-fixture observation)**: when the static-default and dynamic-resolution paths both attach the same `organization` client scope (e.g. when the dynamic-resolution sees a single membership and converges with the static-default), `organization` can appear twice in the literal `scope` string. The current scope-resolution.md Step 1 algorithm shows `.distinct()` (L41 / L666) — this is a refinement to that algorithm's documented dedup semantics. Worth adding a note: the `.distinct()` happens over `ClientScopeModel` instances, not by name; if both paths produce distinct model instances with the same name, both survive into the joined string.

6. **Add a numbered invariant to SKILL.md's "Critical invariants" list** summarising 1-3 in one sentence with a forward link to `references/organizations.md`. Possible wording: "**Static `scope=organization` only emits the `organization` claim for single-membership users.** Multi-membership requires `scope=organization:*`; specific-org requires `scope=organization:<alias>`. The static path emits null (→ NON_NULL drop) for zero or multi membership. See [references/organizations.md](references/organizations.md)."

The minimum text change that would have flipped this fixture to PASS: a single sentence in the new references/organizations.md saying the unqualified path emits null for non-single-membership users → NON_NULL drops the claim. The order/shape/dedup clarifications are additional value but not strictly required for this fixture's verdict.
