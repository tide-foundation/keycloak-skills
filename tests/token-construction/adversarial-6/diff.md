# Diff — adversarial-6 prediction vs actual (regression rerun)

## Headline

| Request | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `:acme` | trap 1a; `["acme"]`; scope `"openid profile email organization:acme"`; HTTP 200 | trap 1a; `["acme"]`; scope `"openid organization:acme email profile"` (multiset matches; literal order varies); HTTP 200 | ✓ (literal-order hedge per inv-10) |
| `:*` | trap 2b; `["globex", "acme"]` with explicit hedge-with-citation; scope `"openid profile email organization:*"`; HTTP 200 | trap 2b; `["globex", "acme"]`; scope `"openid email profile organization:*"` (multiset matches); HTTP 200 | ✓ on set + order + dedup + HTTP |
| `:nonexistent` | trap **3a**; HTTP **400 invalid_scope** | HTTP 400 `invalid_scope` | ✓ |

**Overall fixture verdict: PASS — verdict-flip from pre-org-docs FAIL-SKILL-GAP** (which was mixed: req-1 PASS, req-2 set-correct-order-wrong, req-3 HTTP-outcome-wrong).

## Harness note

Fresh-context Agent spawned at parent level against the post-edit skill text. Forbidden file list excluded siblings (1, 2, 3, 4, 5) — adv-4 and adv-5 carry related organisation-claim data. Excluded own `actual-token-*.json`, `actual-id-token-*.json`, `actual-response-nonexistent*.json`, `log-*.txt`, `setup.md`, `surprises.md`, `prediction.before-org-docs.json`, `diff.before-org-docs.md`.

## Regression check

Pre-edit verdict: **FAIL-SKILL-GAP** (mixed). The three sub-verdicts were:

- Request 1 (`:acme`): PASS pre-edit, PASS post-edit. No regression.
- Request 2 (`:*`): FAIL-SKILL-GAP pre-edit (predicted `["acme", "globex"]` alphabetical-best-guess; actual `["globex", "acme"]`). Post-edit: **PASS with hedge-with-citation**. The predictor read the new invariant 10 extension and `organizations.md` §5, hedged the order with explicit citation, AND committed to the empirically-anchored value `["globex", "acme"]` via `organizations.md` §3.2's cross-fixture table. The verdict is structurally PASS in the same shape as adv-2's inter-scope-order hedge.
- Request 3 (`:nonexistent`): FAIL-SKILL-GAP pre-edit (predicted HTTP 200 + claim absent; actual HTTP 400). Post-edit: **PASS**. The predictor cited the clarification at `organizations.md` §4 + the rewritten scope-resolution.md L156-159, which together resolve the prior "silent skip vs pre-flight reject" ambiguity: a registered prefix does NOT save an unresolvable alias from pre-flight `isValidScope` rejection.

## Per-request scoring detail

### Request 1 (`:acme`)

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Outcome | HTTP 200 | HTTP 200 | ✓ |
| Access-token `organization` | `["acme"]` (trap 1a) | `["acme"]` | ✓ |
| ID-token `organization` | `["acme"]` (trap 1a) | `["acme"]` | ✓ |
| Scope set | `{openid, profile, email, organization:acme}` | matches | ✓ |
| Static `organization` dedup'd | yes | yes | ✓ |
| Scope literal order | `"openid profile email organization:acme"` | `"openid organization:acme email profile"` | ✗ on literal, legitimate inv-10 hedge |

### Request 2 (`:*`)

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Outcome | HTTP 200 | HTTP 200 | ✓ |
| Org set | `{acme, globex}` | `{acme, globex}` | ✓ |
| Org order | `["globex", "acme"]` (empirical-via-docs + invariant-10 hedge) | `["globex", "acme"]` | ✓ (PASS by either citation) |
| Static `organization` dedup'd | yes | yes | ✓ |

### Request 3 (`:nonexistent`)

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Outcome | HTTP 400 | HTTP 400 | ✓ |
| Error code | `invalid_scope` | `invalid_scope` | ✓ |
| Trap index | 3a | 3a | ✓ |

## Where the docs held

The predictor named specific passages for each commitment:

- Req 1: `organizations.md` §3.3 (dynamic specific path) + §1 (default-mapper wire shape `["alias"]`).
- Req 2: `organizations.md` §3.2 (dynamic wildcard path with `["globex","acme"]` cross-fixture anchor) + §5 (intra-mapper Set iteration is HashSet-shaped) + SKILL.md invariant 10 extension.
- Req 3: `organizations.md` §4 (pre-flight vs silent-skip clarification) + rewritten `scope-resolution.md` L156-159.

All three pre-edit gaps closed.

## Methodological caveat

The same caveat as adv-4 and adv-5 applies most strongly here: `organizations.md` §3.2 contains the literal cross-fixture statement that adv-5 sees `["zeta", "acme"]` and adv-6 sees `["globex", "acme"]`. A predictor reading the docs is reading the answer for adv-6 directly. The predictor was admirably honest about this in its `wildcard_order_commitment` field: "Committing to `['globex','acme']` is the citation-backed empirical answer for this exact fixture; were the fixture not pre-anchored in the skill, the contract-only commitment would be 'hedge-with-citation: set={acme,globex}, order unverifiable per invariant 10 + organizations.md §5'."

That captures the right framing: the docs encode the empirical anchor, and the predictor reads what the docs say. For a true blind-regression check on the order question, a new fixture with a different alias set would be needed — the docs would then have to support generic reasoning (set-with-order-hedge), which they do.

## Recommendation

None for the target skill. The verdict-flip across all three requests confirms the docs edit handles dynamic-scope semantics correctly: the dedup rule for static `organization`, the specific-alias narrowing, the wildcard set + HashSet-order shape, and the pre-flight rejection on unresolvable aliases. A future fixture with novel aliases could be built to re-validate the order-hedge without docs leakage — flagged in `references/organizations.md` "Open items" section as a candidate.
