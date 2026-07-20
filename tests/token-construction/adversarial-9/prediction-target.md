# Prediction target

A standard token-exchange request (`request-2.json`) is issued against
realm `adv-9`: client `adv9-client` exchanges the subject access token
(published decoded as `subject-token.json`; its raw JWT is embedded
verbatim in `request-2.json`'s `form.subject_token`) with
`audience=adv9-target-a`, **no** `requested_token_type`, and **no**
`scope` parameter. The inputs are `realm-config.json`, `request-1.json`,
`subject-token.json`, and `request-2.json`. The subject token is a
*given input* to the exchange — nothing about it is a prediction target.
The prediction concerns ONLY the exchanged access token minted by
`request-2.json`.

The skill must commit to two values for the exchanged access token:

1. **`aud_set`** — the exact SET of audience values present in the
   exchanged access token's `aud` claim. This is order-free: list the
   members in any order. Whether a single-member audience serializes on
   the wire as a JSON string or a one-element JSON array is explicitly
   NOT scored — only set membership is scored.

2. **`resource_access_keys`** — the exact SET of top-level keys of the
   `resource_access` claim in the exchanged access token (order-free).
   If the prediction is that `resource_access` is absent entirely,
   commit to the empty set and say the claim is absent.

## Required output shape

```json
{
  "outcome": "token_minted | http_400_no_token",
  "aud_set": ["<clientId>", "..."],
  "resource_access_keys": ["<clientId>", "..."],
  "reasoning": "<citations of the SKILL.md invariants / references passages each commitment is sourced from>"
}
```

- `outcome` is `"token_minted"` if a 200 response with an access token
  is predicted; `"http_400_no_token"` if the prediction is that the
  exchange is rejected and no token is minted. If `outcome` is
  `"http_400_no_token"`, the two set fields must be `null`.
- `aud_set` and `resource_access_keys` are JSON arrays used as sets
  (order ignored; duplicates illegal).
- `reasoning` must cite the specific SKILL.md invariant(s) and/or
  references/ passages relied on, per commitment.

## What does NOT count as a prediction

- "Depends on `requested_token_type`" without resolving it for THIS
  request. `request-2.json` is public and sends no
  `requested_token_type`; whatever role that parameter plays must be
  resolved against the literal request, not hedged over.
- "Depends on whether audience narrowing fires" without deciding, for
  this exact request, whether it fires.
- "Either {a, b, account} or {a}" (or any either/or across trap-menu
  rows) without picking one.
- Committing to `aud_set` while leaving `resource_access_keys` hedged
  (or vice versa). Both sets must be concrete.
- Set-shaped answers with placeholders ("target-a plus possibly
  others").

If the skill genuinely mandates a hedge, the prediction must cite the
specific invariant or reference passage that requires it and explain
why it applies to this request while still committing to everything
that remains derivable.

## Plausible outputs (the trap menu)

A partially-correct skill might land on any of the following. The rest
are traps a vague reading would let through.

1. **`aud_set = {adv9-target-a, adv9-target-b, account}`,
   `resource_access_keys = {adv9-target-a, adv9-target-b, account}`** —
   would be predicted by a reader who concluded that no audience
   narrowing fires on this request, so the exchanged token keeps the
   full mapper-resolved audience set.

2. **`aud_set = {adv9-target-a}`,
   `resource_access_keys = {account, adv9-target-a, adv9-target-b}`** —
   would be predicted by a reader who applied the audience intersect to
   `aud` but missed that the same post-mapper transform also prunes
   `resource_access` entries.

3. **`aud_set = {adv9-target-a, account}`, `resource_access_keys`
   pruned to match (`{adv9-target-a, account}`)** — would be predicted
   by a reader who thinks built-in / service audiences like `account`
   are exempt from the intersect and always survive.

4. **`outcome = http_400_no_token`** — would be predicted by a reader
   who over-applied the "requested audience not available" rejection to
   an audience the subject actually reaches.

5. **`aud_set = {adv9-target-a}`,
   `resource_access_keys = {adv9-target-a}`.**

## Minimum specificity to pass

Both sets must be filled with concrete client IDs (or `outcome` set to
`"http_400_no_token"` with both sets `null`). Every member must be
named; no "possibly", no ranges, no either/or across trap rows. The
`reasoning` field must trace each commitment to skill text. A
prediction that resolves `aud_set` but hedges `resource_access_keys`
fails the specificity bar, and vice versa.
