# Prediction target

Two token requests are issued against the same client `adv3-client` in realm
`adv-3` — one via `client_credentials`, one via the Resource Owner Password
Credentials (`password`) grant. Each request produces an access token whose
payload is captured. For **each of the two tokens**, the skill must commit
to two values:

1. **`sid` presence** — is the `sid` claim present in the access-token
   payload? Two states: `"present"` (the claim exists with a non-null
   string value) or `"absent"` (the claim is missing from the payload, or,
   equivalently, was nulled in memory and dropped by `JsonInclude.NON_NULL`
   on the wire).

2. **`jti` prefix** — the substring of `jti` *before* the first `:`. The
   skill cites these prefixes by name in invariant 12 and
   `references/post-mapper.md`'s "Diagnostic — read the `jti` prefix"
   table. Commit on every letter of the prefix; the prefix is built from
   three two-letter components per `TokenContextEncoderProvider.encodeTokenId`
   and `AccessTokenContext.SessionType`:

   | Position | Letters | Meaning |
   | --- | --- | --- |
   | Session type | `tr` / `on` / `of` | TRANSIENT / ONLINE / OFFLINE |
   | Refresh-token | `rt` / `ft` | refresh-token-context (default) / refresh-token-free |
   | Grant family | `cc` / `ro` / `co` / `…` | client-credentials / ROPC password / authorization-code / … |

   Example known values from the existing positive controls:
   `trrtcc:` (transient client_credentials, sid absent),
   `onrtcc:` (online client_credentials with refresh, sid present),
   `onrtro:` (online ROPC password with refresh, sid present).

## Required output shape

```json
{
  "client_credentials": {
    "predicted_sid_presence": "<present|absent>",
    "predicted_jti_prefix":   "<six chars before the colon, e.g. trrtcc>"
  },
  "password": {
    "predicted_sid_presence": "<present|absent>",
    "predicted_jti_prefix":   "<six chars before the colon, e.g. onrtro>"
  }
}
```

Plus a `reasoning` field per token citing the SKILL.md / references passages
the commitment is sourced from.

## What does **not** count as a prediction

- "depends on whether refresh tokens are enabled" without resolving the
  default for this client config.
- "either present or absent" / "either `trrtcc:` or `onrtcc:`" without a
  pick.
- Refusing to commit on the prefix because "the skill mentions the prefix
  letters but doesn't fully decompose them" — invariant 12 plus the
  diagnostic table in `references/post-mapper.md` plus the existing fixture
  pair (`token-openid.json` → `trrtcc:`, `token-with-refresh-openid.json` →
  `onrtcc:`) jointly anchor the `cc` / `tr` / `on` letters. The `ro` letter
  for ROPC is not directly anchored by an existing fixture but is named in
  SKILL.md invariant 12 and is derivable as the only choice that
  distinguishes the password grant from client_credentials in the
  prefix-namespace described.

If the skill mandates a hedge for one of the two tokens, the prediction
must cite the specific invariant or reference passage that requires the
hedge, and explain why that passage applies here while not applying to the
positive-control fixtures.

## Plausible outputs (the trap menu)

A partially-correct skill might predict any of the following. Exactly one
combination is correct (to be confirmed by minting). The rest are traps a
vague reading would let through.

1. **Both have `sid`, both prefixes are `onrt…`** — would be predicted by a
   reader who didn't read the conditional in invariant 12 and assumed
   "every Keycloak access token has `sid`," or who saw only the
   `with-refresh-openid` positive-control fixture and generalised. Wrong on
   the client_credentials token: with the default
   `client_credentials.use_refresh_token` (unset → "false"), the transient
   branch fires and `sid` is nulled.

2. **Neither has `sid`** — would be predicted by a reader who over-applied
   the nulling rule from `token-openid.json`'s service-account fixture to
   the password grant too. Wrong on the password token: ROPC password
   grant's `useRefreshToken()` is `true` by default
   (`OAuth2GrantTypeBase.java:398`), so the L120 if-branch fires and the
   transient null path is never even evaluated.

3. **Got `sid` right but mispredicts `jti` prefix** — e.g., predicts
   `oftcc:` for the client_credentials token because the realm has
   `offline_access` listed as an optional client scope (it is, but the
   request doesn't ask for it, so the session is online/transient, not
   offline), or predicts `onrtpw:` for the password grant because the
   reader invented a letter.

4. **Predicts `sid` is present on the client_credentials token because
   "the session is created server-side, why would it be null on the wire"
   — a plausible misread that ignores the post-mapper nulling step at
   `OAuth2GrantTypeBase.java:128-135`.** This is the precise trap invariant
   12 is written to defeat: a reader who reasons about session
   construction without reading the post-construction null assignment will
   land here.

5. **Correct combination — `client_credentials` → sid absent, `jti`
   `trrtcc:`; `password` → sid present, `jti` `onrtro:`.**

## Minimum specificity to pass

Both `(sid_presence, jti_prefix)` pairs must be filled with a concrete
value (not a hedge). The `jti_prefix` must be exactly six characters; e.g.
`trrtcc` is six chars before the colon.
