# Prediction target

A standard token-exchange request (`request-2.json`) is issued against
realm `adv-10`: client `adv10-client` exchanges the subject access token
(published decoded as `subject-token.json`; its raw JWT is embedded
verbatim in `request-2.json`'s `form.subject_token`) with
`scope=profile`, **no** `audience`, and **no** `requested_token_type`.
The inputs are `realm-config.json`, `request-1.json`,
`subject-token.json`, and `request-2.json`. The subject token is a
*given input* to the exchange — nothing about it is a prediction
target (its `adv10_marker: "present"` and its `sub` are givens). The
prediction concerns ONLY the exchanged access token minted by
`request-2.json`.

The skill must commit to three values for the exchanged access token:

1. **`adv10_marker`** — either the exact string `"present"` (the claim
   appears on the wire with that value) or the literal string
   `"ABSENT"` (the claim key is missing from the wire JSON entirely).

2. **`sub`** — either `"PRESENT"` (a `sub` key appears in the exchanged
   access token's wire JSON) or `"ABSENT"` (no `sub` key). The *value*
   of `sub` is NOT scored — only presence/absence of the key.

3. **`scope_claim_multiset`** — the multiset of space-separated names
   appearing in the exchanged access token's `scope` claim. Order is
   NOT scored; every member must be named exactly. If the prediction is
   that the `scope` claim is absent entirely, commit to the empty
   multiset and say the claim is absent.

Hedges of the form "depends on what `restrictedScopes` contains"
without resolving it for THIS request do not count as predictions.
JSON serialization details beyond presence/absence (key order, string
vs. array shapes, whitespace) are not scored.

## Required output shape

```json
{
  "outcome": "token_minted | http_400_no_token",
  "adv10_marker": "present | ABSENT",
  "sub": "PRESENT | ABSENT",
  "scope_claim_multiset": ["<name>", "..."],
  "reasoning": "<citations of the SKILL.md invariants / references passages each commitment is sourced from>"
}
```

- `outcome` is `"token_minted"` if a 200 response with an access token
  is predicted; `"http_400_no_token"` if the prediction is that the
  exchange is rejected and no token is minted. If `outcome` is
  `"http_400_no_token"`, the other three fields must be `null`.
- `scope_claim_multiset` is a JSON array used as a multiset (order
  ignored).
- `reasoning` must cite the specific SKILL.md invariant(s) and/or
  references/ passages relied on, per commitment.

## What does NOT count as a prediction

- "Depends on what `restrictedScopes` contains" without resolving, for
  this literal request (`scope=profile`), what the restricted set is
  and what survives the filter.
- "Depends on whether the exchange inherits the subject token's
  scopes" without deciding it for this request.
- "`adv10_marker` present or absent depending on mapper-set assembly"
  (or any either/or across trap-menu rows) without picking one.
- Committing to `adv10_marker` while leaving `sub` or
  `scope_claim_multiset` hedged (or any other partial commitment). All
  three must be concrete.
- Multiset answers with placeholders ("profile plus possibly others").

If the skill genuinely mandates a hedge, the prediction must cite the
specific invariant or reference passage that requires it and explain
why it applies to this request while still committing to everything
that remains derivable.

## Plausible outputs (the trap menu)

A partially-correct skill might land on any of the following. The rest
are traps a vague reading would let through.

1. **`adv10_marker = "present"`, `sub = PRESENT`,
   `scope_claim_multiset` contains `adv10-scope`** (alongside the other
   subject-token scope names) — would be predicted by a reader who
   thinks the exchanged token inherits the subject token's mapper set /
   scopes ("exchange copies claims").

2. **`adv10_marker = ABSENT`, `sub = PRESENT`,
   `scope_claim_multiset = {profile}`** — would be predicted by a
   reader who applies `restrictedScopes` to custom/optional scopes but
   assumes built-in default scopes (`basic`, and its SubMapper) are
   immune to the filter.

3. **`adv10_marker = ABSENT`, `sub = ABSENT`,
   `scope_claim_multiset = {profile}`** — would be predicted by a
   reader who applies the `restrictedScopes` filter uniformly to every
   candidate scope including `basic`, then applies invariant 1
   (`initToken` does not set `sub` on persistent sessions) plus
   invariant 11 (null claims dropped from the wire).

4. **`outcome = http_400_no_token` (HTTP 400 `invalid_scope`)** —
   would be predicted by a reader who thinks `scope=profile` is invalid
   on the exchange leg because the subject token's scope didn't include
   it / down-scoping must be a subset of the subject token's `scope`
   claim.

5. **`adv10_marker = "present"`, `sub = PRESENT`,
   `scope_claim_multiset = {profile}`** — would be predicted by a
   reader who thinks `restrictedScopes` only affects the `scope` claim
   string, not the mapper set.

## Minimum specificity to pass

All three fields must be filled with concrete values (or `outcome` set
to `"http_400_no_token"` with the three fields `null`). Every multiset
member must be named; no "possibly", no ranges, no either/or across
trap rows. The `reasoning` field must trace each commitment to skill
text. A prediction that resolves `scope_claim_multiset` but hedges
`adv10_marker` or `sub` fails the specificity bar, and vice versa.
