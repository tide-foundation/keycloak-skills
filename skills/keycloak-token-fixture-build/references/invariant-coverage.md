# Invariant coverage

Maps each numbered invariant in the target skill's SKILL.md to the
fixtures (if any) that probe it. Update this when adding a new fixture
or retiring an old one.

## Coverage table

| # | Invariant (paraphrase) | Probed by | Status |
| --- | --- | --- | --- |
| 1 | `sub` only set by initToken on transient sessions | — | gap |
| 2 | `scope` claim composition (allowed scopes, isIncludeInTokenScope, openid re-attach, default-true on missing attr, ClientModel filter) | adversarial-2 | covered (PASS) |
| 3 | Lightweight access-token uses `lightweight.claim` toggle | — | gap |
| 4 | Introspection fallback ignores lightweight | — | gap |
| 5 | Userinfo fallback uses `id.token.claim`, not `access.token.claim` | — | gap |
| 6 | `fullScopeAllowed` short-circuits role intersection, not mapper dispatch | adversarial-2 (collateral) | partial — explicitly invoked by predictor; no dedicated fixture |
| 7 | ID-token base claims sourced from transformed access token | — | gap |
| 8 | `restrictRequestedAudience` runs after access-token mappers | — | gap |
| 9 | `at_hash`/`c_hash`/`s_hash` out of model | — | not worth a fixture (out of skill scope) |
| 10 | Mapper sort ties are not deterministic | adversarial-1 | covered (FAIL-BY-DESIGN, by design) |
| 11 | NON_NULL drops null claims | adversarial-1 (collateral), adversarial-2 (collateral) | partial — invoked by predictor on every fixture; no dedicated probe |
| 12 | Transient `sid` nulling on `useRefreshToken=false` + TRANSIENT | adversarial-3 | covered (PASS) |

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
5. **Invariant 8 (restrictRequestedAudience)** — hard. Token exchange
   flow. Defer until easier ones land.
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
