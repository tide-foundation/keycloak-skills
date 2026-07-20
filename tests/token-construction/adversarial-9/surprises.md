# Surprises encountered while building adversarial-9

No claim-level surprises: both committed targets (`aud_set`,
`resource_access_keys`) matched the pre-mint expectation (trap-menu
entry #5), the determinism pair was byte-identical after the strip set,
and the subject token never needed re-minting. The items below are
smaller observations worth recording.

## 1. The TOKEN_EXCHANGE event logs a `requested_token_type` the request never sent

`request-2.json` deliberately omits `requested_token_type` — that
omission is load-bearing for the seam (the trigger-attribution
discrepancy in the target skill's post-mapper.md). Yet the
`type="TOKEN_EXCHANGE"` event line in `log-2-a.txt` / `log-2-b.txt`
contains `requested_token_type="urn:ietf:params:oauth:token-type:access_token"`.
The event records the server-side *defaulted* value, not the wire
request.

Implication: none for determinism or the seam itself (logs are on the
predictor's deny-list, and the request artifact is authoritative for
what was sent). But anyone auditing this fixture from the logs alone
could wrongly conclude the parameter was present on the wire and that
the narrowing-trigger question was never isolated. The `form` object in
`request-2.json` is the ground truth: no `requested_token_type`, no
`scope`.

Action taken: noted here and cross-referenced from setup.md's
resolution section.

## 2. Exchange envelope carries `session_state` but no refresh token

The leg-2 response envelope has `refresh_expires_in: 0` and no
`refresh_token` (expected — `requested_token_type` defaults to
`access_token`, and the refresh variant needs two extra client flags),
yet it still includes `session_state: "kMdCV-…"` equal to the token's
`sid` and the subject session. Mildly counter-intuitive to see
session-binding fields on a refresh-less response; consistent with the
exchanged token riding the *existing* online user session (also why
`sid` is identical across both determinism mints and equal to the
subject token's `sid`, and why the `jti` prefix is `onrtte:` —
ONLINE, not transient).

Implication: reinforces the token-exchange.md note that the
`STEP.L279-281` sid-nulling fires only on TRANSIENT. No action needed.

## 3. Protocol note: setup.md's resolution section was drafted pre-mint

Deviation from the setup template's "filled in AFTER minting"
instruction: the builder drafted the "Resolution after capture"
bullets together with the rest of setup.md at the commitment point
(pre-mint, as expectations), then verified them against the captures
and edited in the concrete values (`sid`, `jti` suffixes, log-line
facts) post-mint. Every pre-drafted claim held, so no content had to
be retracted. The harness commitment invariant was NOT affected —
`prediction-target.md` and the trap menu were on disk before any leg-2
mint, and `request-2.json` was frozen by hand before setup.md was
written. Recorded for transparency.

## Reusable observations

- **Event-log fields are post-default, not wire-echo.** Keycloak
  26.5.5's events (`org.keycloak.events` INFO lines) serialize resolved
  values — a defaulted `requested_token_type` appears as if sent. When
  a fixture's seam hinges on a parameter being *absent from the
  request*, only the frozen `request-*.json` proves absence; logs
  cannot.
- **This stack logs `TokenManager` at TRACE** ("Using full scope for
  client …" appears in every bracketed slice). Handy free evidence that
  the full-scope path ran, for any fixture whose seam involves
  `fullScopeAllowed`.
- **The exchanged token inherits the subject session wholesale**:
  same `sid` across subject token, both exchange mints, and the
  envelope `session_state`. For two-leg fixtures this makes `sid` a
  useful pinned-input sanity check even though it sits in the
  determinism strip set.
