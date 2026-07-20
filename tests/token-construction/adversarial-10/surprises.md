# Surprises encountered while building adversarial-10

## 1. The exchange `scope` parameter does NOT down-scope on stock 26.5.5 — the builder's expected trap (#3) was falsified; the actual outcome is trap #1

Pre-mint, the builder committed (setup.md) to `adv10_marker = ABSENT`,
`sub = ABSENT`, `scope_claim_multiset = {profile}` — the uniform
`restrictedScopes` filter chain (trap 3). The captured exchanged token
instead kept **everything**: `adv10_marker: "present"`, `sub` present,
`scope: "email adv10-scope profile"` — byte-identical claim content to
an unrestricted issuance (trap 1's shape). The `scope=profile` param
was provably on the wire (frozen `request-2.json`; pre-flight TRACE
`scopes: profile` in `log-2-*.txt`) and provably ignored as a
restrictor.

Mechanism (source-verified at tag 26.5.5 after capture):

- `StandardTokenExchangeProvider` L232-233 does pass a restricted-scope
  set into `TokenManager.attachAuthenticationSession(...)` →
  `DefaultClientSessionContext.fromClientSessionAndClientScopes(...,
  restrictedScopes, ...)` → the `isAllowed` filter at DCSC.L253. The
  plumbing is real.
- But the value passed is `context.getRestrictedScopes()` — a field of
  `TokenExchangeContext` whose **only setter call site in the entire
  codebase** is `DownscopeAssertionGrantEnforcerExecutor.executeOnEvent`
  (`services/src/main/java/org/keycloak/services/clientpolicy/executor/
  DownscopeAssertionGrantEnforcerExecutor.java` L60-66), a **client
  policy executor** on the `TOKEN_EXCHANGE_REQUEST` event. The request
  `scope` param NEVER populates it directly.
- This realm (like any stock realm) has no client policies —
  `realm-config.json` shows `clientPolicies.policies: []` — so
  `restrictedScopes == null`, the DCSC.L253 branch is inert, and the
  allowed-scope set is the ordinary candidate set: all default scopes
  ∪ {client}. The exchange `scope` param's only effects are (a) the
  pre-flight `TokenManager.isValidScope` gate and (b) the SCOPE_PARAM
  auth-session note (`AbstractTokenExchangeProvider` L267) feeding
  `getRequestedClientScopes`, which can only **add optional scopes**
  to the candidates, never subtract defaults.

Implication for the fixture: none for validity — the commitment was
pre-mint, the trap menu contained the actual outcome (row 1), and the
determinism pair was byte-identical. But the fixture's *discriminating
power* is inverted from the design intent: it now punishes a reader
who over-applies `restrictedScopes` (trap 3) rather than one who
under-applies it.

Implication for the target skill (verdict is the parent's call, but
flagging loudly): `references/mapper-set-assembly.md` L98-100
("**`restrictedScopes` (token exchange)** changes which scopes pass
`isAllowed` … Token exchange can therefore see a strictly smaller
mapper set") attributes `restrictedScopes` to token exchange
unconditionally. As a description of the plumbing it is true; as a
behavioural claim about a stock-config exchange request carrying a
`scope` param it misleads — the filter never fires without the
Downscope client-policy executor. `scope-resolution.md`'s `isAllowed`
pseudocode is correct as written (it hedges on `restrictedScopes !=
null` and never claims the exchange scope param populates it). A
predictor reasoning strictly from the skill text could land on trap 3
via the mapper-set-assembly.md sentence, or on trap 1/5 by noting no
skill passage ever says the *scope param* becomes `restrictedScopes`.
Separately, the **fixture-build skill's** `references/token-exchange.md`
request-surface table (row `scope`: "feeds `restrictedScopes` into the
DCSC ctor — exchange can shrink the allowed-scope set and therefore
the mapper set", cited L186-200, L233) states the wrong-at-stock
reading as fact and needs an edit; that file is on the predictor
deny-list, so no contamination.

## 2. When the Downscope executor IS active, the traps re-arrange

Read post-capture from `DownscopeAssertionGrantEnforcerExecutor.checkDownscope`:

- It enforces requested-scopes ⊆ subject-token `scope` claim, else
  `invalid_scope` — i.e. **trap 4's "subset of the subject token's
  scope" intuition is exactly what this policy executor enforces**
  (and only it; stock exchange validates against the client's
  registered scopes instead).
- The `restrictedScopes` set it builds is *not* just the requested
  names: it is {default scopes with `include.in.token.scope=false`}
  ∪ {subject-token scope-claim names}. Built-ins `basic`, `roles`,
  `acr`, `web-origins` are deliberately whitelisted — **trap 2's
  "built-ins are immune" intuition is also encoded upstream**, so
  `sub` would survive even under the policy.
- Corollary for future fixture design: even with the policy active,
  THIS request would filter nothing — restrictedScopes would be
  {web-origins, acr, roles, basic} ∪ {email, adv10-scope, profile} =
  all seven attached defaults. To make the filter bite, the *subject
  token* must carry a narrower `scope` claim than the client's
  defaults (e.g. leg 1 minted with an explicit scope param), and the
  realm needs a client policy wiring the executor. That is the
  adversarial-11 candidate seam if the restrictedScopes filter itself
  is to be observed live.

## 3. Protocol note: the pre-drafted resolution section had to be replaced wholesale

Same deviation as adversarial-9's surprises.md §3 — the builder
pre-drafted setup.md's "Resolution after capture" bullets at the
commitment point as expectations — but with the opposite outcome:
here every claim-level expectation was falsified and the section was
rewritten from the captures. The harness commitment invariant was NOT
affected (`prediction-target.md` + trap menu + `request-2.json` were
on disk before any leg-2 mint, and the trap menu already contained
the actual outcome as row 1), but this fixture is a live warning
against pre-drafting "resolutions": had the builder skipped
re-verification, setup.md would have shipped describing a token that
does not exist.

## 4. The TOKEN_EXCHANGE event logs the resolved scope, not the wire param

`log-2-*.txt` events carry `scope="email adv10-scope profile"` — the
*outcome* — while the wire request sent `scope=profile`. Extends
adversarial-9's observation (defaulted `requested_token_type` logged
as if sent) from defaulted-absent to transformed-present parameters.
The only in-log trace of the wire param is the pre-flight TRACE pair
(`Scopes to validate requested scopes against: …` / `scopes:
profile`). The frozen `request-2.json` remains the sole authoritative
record of what was sent.

## Reusable observations

- **Client-policy executors are an invisible-input hazard for seam
  design.** A code-level mechanism (`restrictedScopes`) can exist,
  be cited with accurate line numbers, and still be dead on every
  stock-config path because its only writer is an opt-in client
  policy. When a seam depends on a context field, grep for the
  field's *setter call sites* before committing expectations — the
  partial export does capture the absence
  (`clientPolicies.policies: []`), so the fact is predictor-visible.
- **The exchange scope param is add-only on stock 26.5.5**: pre-flight
  validation against the client's registered scopes, then optional-
  scope addition via the ordinary `getRequestedClientScopes` path.
  RFC 8693-style down-scoping of default scopes requires the
  `DownscopeAssertionGrantEnforcerExecutor` client policy (added
  2025, present at 26.5.5).
- **Event-log `scope` is post-resolution** — pair with adversarial-9's
  "event fields are post-default" note: Keycloak event lines are
  outcome serializations, never wire echoes.
