# Invariant coverage

Maps each numbered invariant in the target skill's SKILL.md to the
fixtures (if any) that probe it. Update this when adding a new fixture
or retiring an old one.

## Coverage table

| # | Invariant (paraphrase) | Probed by | Status |
| --- | --- | --- | --- |
| 1 | `sub` only set by initToken on transient sessions | adversarial-10 (collateral) | partial — adv-10's `sub`-presence commitment required invoking SubMapper-in-`basic` on a persistent session; no dedicated transient-vs-persistent contrast fixture yet |
| 2 | `scope` claim composition (allowed scopes, isIncludeInTokenScope, openid re-attach, default-true on missing attr, ClientModel filter) | adversarial-2 | covered (PASS) |
| 3 | Lightweight access-token uses `lightweight.claim` toggle | — | gap |
| 4 | Introspection fallback ignores lightweight | — | gap |
| 5 | Userinfo fallback uses `id.token.claim`, not `access.token.claim` | — | gap |
| 6 | `fullScopeAllowed` short-circuits role intersection, not mapper dispatch | adversarial-2 (collateral) | partial — explicitly invoked by predictor; no dedicated fixture |
| 7 | ID-token base claims sourced from transformed access token | adversarial-4 (collateral) | partial — adv-4 confirmed shape parity across access+ID for the organisation-membership mapper |
| 8 | `restrictRequestedAudience` runs after access-token mappers | adversarial-9 | covered (PASS) — first two-leg (token-exchange) fixture; fresh predictor committed exactly to the intersect + `resource_access` prune. Note in diff.md: the post-mapper.md L42-43 trigger wording (`requested_token_type` vs the actual `audience` param) was flagged ambiguous by the predictor but recovered via the L46-47 catch-all; a clarity edit remains optional, not verdict-mandated. |
| 9 | `at_hash`/`c_hash`/`s_hash` out of model | — | not worth a fixture (out of skill scope) |
| 10 | Mapper sort ties are not deterministic | adversarial-1, adversarial-6 (extension) | covered (FAIL-BY-DESIGN, by design). Adv-6's wildcard order finding extended invariant 10's wording in SKILL.md to cover intra-mapper Set iteration over user-state collections. |
| 11 | NON_NULL drops null claims | adversarial-1 (collateral), adversarial-2 (collateral), adversarial-4 (nonmember case, dedicated), adversarial-5 (multi-member static case, dedicated) | covered — adv-4 + adv-5 both produce intentional NON_NULL drops on the `organization` claim |
| 12 | Transient `sid` nulling on `useRefreshToken=false` + TRANSIENT | adversarial-3 | covered (PASS) |
| 13 | `organization` claim — three scope-param entry paths with materially different behaviour | adversarial-4 (single-member + nonmember, wire shape), adversarial-5 (multi-member unqualified → claim absent), adversarial-6 (specific / wildcard / nonexistent dynamic forms) | covered — three dedicated fixtures, motivated the new `references/organizations.md` |
| 14 | Role-injection mappers (`oidc-hardcoded-role-mapper`, `oidc-role-name-mapper`) bypass the toggle gate, write to the `RoleResolveUtil` resolved-roles cache (not a claim path), surface only via consumer role/audience mappers per *their* toggles, never run on the ID surface, and bypass `fullScopeAllowed` | adversarial-7 | covered — fixture caught a skill gap (HardcodedRole was undocumented; the toggle pseudocode read literally forced "everything absent"), motivated invariant 14 + the role-injection-class subsection in `references/mapper-execution.md`. Pre-edit predictor needed the WebFetch escape; post-edit predictor reported skill text alone sufficient. |
| 15 | `mapClaim`'s three-category routing for base-claim names: (a) modifiable {`sub`,`azp`,`acr`,`auth_time`,`aud`} via `tokenPropertySetters` dedicated setter (single key, mapper wins); (b) non-modifiable {`jti`,`typ`,`iat`,`exp`,`iss`,`scope`,`nonce`,`session_state`} via `notAllowedInToken` sentinel (WARN logged, write dropped, fires once per surface the toggle gate passed; "in IDToken" refers to the Java class, not the surface); (c) collision (e.g. `sid`) — declared `@JsonProperty` field absent from both maps, produces duplicate JSON keys (dedicated field first, `otherClaims` last) with no WARN | adversarial-8 | covered (PASS) — fresh predictor committed to all 13 fields (per-claim per-surface routing + wire shape + value, WARN count, logger category, "in IDToken" Java-class-vs-surface semantics, duplicate-key serialization origin) and matched the actual on every dimension. Skill text alone sufficient. One optional defensive tweak surfaced: state the Jackson serialization order (dedicated `@JsonProperty` getters before `@JsonAnyGetter`) as a rule in mapper-execution.md (c) rather than relying solely on the empirical example pin. |

## What "covered" means

A fixture covers an invariant if its `prediction-target.md` requires the
predictor to apply that specific invariant to commit, AND the predictor
in the most recent verdict actually invoked that invariant by name in
its `skill_passages_invoked` field.

A fixture's collateral coverage of a different invariant (e.g.,
adversarial-2 invoking invariant 11 on `realm_access` absence) doesn't
elevate that invariant to "covered" — the prediction target wasn't
about it. Build a dedicated fixture instead.

## Priority for new fixtures

Pick from the gap rows. Difficulty hints in
`references/seam-design.md` Step 1. Suggested order if working through
the gaps:

1. **Invariant 5 (userinfo fallback)** — easy, high signal. One mapper,
   one userinfo request, one prediction.
2. **Invariant 1 (transient `sub`)** — easy. client_credentials with
   `use_refresh_token=false`, predict whether `sub` is present and what
   value it has (the SubMapper output vs. the initToken absence).
3. **Invariant 7 (ID-token inheritance)** — medium. A mapper that
   mutates the access token with `id.token.claim=false`; predict
   whether the ID token still has the mutated value.
4. **Invariant 3 (lightweight toggle)** — medium. Set
   `client.use.lightweight.access.token.enabled=true`; mapper with
   `access.token.claim=true`, `lightweight.claim=false`; predict claim
   absence.
5. ~~Invariant 8 (restrictRequestedAudience)~~ — **done**:
   adversarial-9 (PASS). The two-leg recipe that built it is in
   `references/token-exchange.md`.

Un-numbered contract covered by **adversarial-10** (PASS with
source-escape): `restrictedScopes` provenance on the standard
token-exchange path. The fixture refuted the seam's own premise —
on stock 26.5.5 the exchange `scope` param does NOT populate
`restrictedScopes` (only the `DownscopeAssertionGrantEnforcerExecutor`
client policy does), so the exchange scope param is add-only and the
mapper set never shrinks on a stock realm. Both the adv-9 and adv-10
predictors flagged the target skill's `mapper-set-assembly.md` L98-100
/ `inputs-and-outputs.md` L72 as misleading here; the candidate edit
batch is recorded in `adversarial-10/diff.md`.
6. **Invariant 4 (introspection fallback ignores lightweight)** — hard.
   Combination of lightweight mode + introspection endpoint flow.
   Defer.

## When to retire a fixture

A fixture is a candidate for retirement if:

- The invariant it probed was removed from SKILL.md (invariant
  semantics changed → the fixture's seam no longer maps to anything).
- A newer fixture supersedes it with a strictly stronger seam (probes
  the same invariant plus more).
- The fixture has been `fail-fixture-bug` for multiple regenerations
  and a redesign is the only path forward; archive the old one and
  build a fresh adversarial-N+1.

Retirement means moving the directory to `fixtures/retired/` (not
deleting), with a one-line note in the fixture's `surprises.md`
explaining why.
