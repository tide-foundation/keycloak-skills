# adversarial-3 — multi-grant `sid` nulling on the same client (invariant 12)

## The seam

A single confidential client `adv3-client` is configured to accept **two**
grants — `client_credentials` (via `serviceAccountsEnabled=true`) and
Resource Owner Password Credentials (via `directAccessGrantsEnabled=true`).
The client deliberately leaves the attribute
`client_credentials.use_refresh_token` **unset** (default `"false"` per
`OIDCConfigAttributes.java:77` /
`ClientCredentialsGrantType.java:154-156`).

Two requests are made against the same client. The seam is whether a skill
reader can predict, **per token**, both:

- the presence/absence of `sid` in the access-token payload, and
- the exact six-char prefix of `jti` (the substring before the first `:`).

The trap is that a careless reader looks at the persistent positive-control
fixture `token-with-refresh-openid.json` and concludes "client_credentials
on a confidential client → `sid` present, prefix `onrtcc:`," forgetting that
`token-with-refresh-openid.json` was minted **after** the
`client_credentials.use_refresh_token=true` toggle was applied (see
`capture-with-refresh.sh`). On a default-configured client, the
client_credentials path takes the transient branch in
`OAuth2GrantTypeBase.java:128-135` and `sid` is nulled. The same client,
hit with the password grant, does **not** take the transient branch
(`useRefreshToken()` is `true` by default for ROPC per
`OAuth2GrantTypeBase.java:398`), so `sid` is retained.

The two predictions per token (4 commitments total) form a 2×2 matrix.
Only one of the 16 plausible four-tuples matches reality. The fixture
exists to deny a skill the comfort of any of the cells in the trap menu.

## Realm / client / user / scope configuration

Realm: `adv-3` (fresh, prefixed `adv-` per the skill's coordination
convention; `adv-1` and `adv-2` are owned by other fixture-builders).

Client: `adv3-client`
- Confidential (`publicClient=false`), secret `adv3-secret-deadbeef`.
- `serviceAccountsEnabled=true` — enables `client_credentials` and creates
  the service-account user `service-account-adv3-client` automatically.
- `directAccessGrantsEnabled=true` — enables Resource Owner Password
  Credentials.
- `standardFlowEnabled=false`, `implicitFlowEnabled=false` — out of scope
  for this seam.
- `fullScopeAllowed=true` — minimises scope-resolution noise. The seam
  here is post-mapper `sid` handling, not scope-resolution.
- **`client_credentials.use_refresh_token`: UNSET on the client.**
  Verified post-export: the realm-config.json's `attributes` block on
  `adv3-client` contains only the default Keycloak housekeeping
  attributes (`realm_client`, `backchannel.logout.session.required`,
  `backchannel.logout.revoke.offline.tokens`) and *not* the
  `client_credentials.use_refresh_token` key. This is the heart of the
  seam — the default is "false," so the client_credentials path takes the
  transient nulling branch.
- `defaultClientScopes`: Keycloak built-ins (`web-origins`,
  `service_account`, `acr`, `profile`, `roles`, `basic`, `email`).
- `optionalClientScopes`: Keycloak built-ins (`address`, `phone`,
  `organization`, `offline_access`, `microprofile-jwt`).

User: `adv3-user`
- Username `adv3-user`, password `password`, `enabled=true`,
  `emailVerified=true`, `firstName=Adv3`, `lastName=User`,
  `email=adv3-user@example.invalid`. The first/last/email fields are
  populated for the same reason as in `adversarial-1/setup.md` — the
  realm's `verify-profile` authenticator demands them for the password
  grant even when `requiredActions=[]`.

Service account: auto-created by `serviceAccountsEnabled=true`. Username
`service-account-adv3-client`, no firstName/lastName/email (default).

Why the same client serves both grants instead of two clients: the
seam-property under test is that **the same client config** produces
opposite `sid` outcomes depending only on the grant. Splitting into two
clients would let a careless reader hand-wave "the two clients differ
somehow," when in fact the only relevant difference is the grant code path
and the per-grant `useRefreshToken()` default. One client maximises the
trap.

Why no custom client scopes / mappers: invariant 12 is post-mapper, after
the per-mapper loop completes. Adding mappers would only add noise. The
only things that matter for `sid` presence are the
`OAuth2GrantTypeBase.processTokenResponse` branch decision (L120 vs L130)
and the `AccessTokenContext.SessionType` of the encoded token id (which
`TokenContextEncoderProvider.encodeTokenId` reflects in the `jti` prefix).

## The two requests

### Request 1 — client_credentials

```
POST /realms/adv-3/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
client_id=adv3-client
client_secret=adv3-secret-deadbeef
scope=openid
```

Captured to `request-cc.json`. Expectation: `useRefreshToken()` resolves
to `false` (client_credentials default + attribute unset → "false").
`ClientCredentialsGrantType` creates a TRANSIENT session
(`ClientCredentialsGrantType.java:111-115`). Both branches of the
`OAuth2GrantTypeBase.L130` check fire → `accessToken.setSessionId(null)`.
Wire result: `sid` absent, `jti` prefix `trrtcc:`.

### Request 2 — password (ROPC)

```
POST /realms/adv-3/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv3-client
client_secret=adv3-secret-deadbeef
username=adv3-user
password=password
scope=openid
```

Captured to `request-pwd.json`. Expectation: `useRefreshToken()` is `true`
by default for ROPC (`OAuth2GrantTypeBase.java:398`). The L120 if-branch
fires; the L130 transient check is **never evaluated**. Session is online,
sid is retained. Wire result: `sid` present, `jti` prefix `onrtro:`.

`scope=openid` on both requests so the surface includes all the standard
OIDC claims and the `id_token` is also issued (interesting because, per
invariant 12, the access-token nulling propagates to id_token's `sid` via
`TokenManager.L1275/L1290`).

## Plausible outputs (the trap menu)

See `prediction-target.md`'s "Plausible outputs" section. The same five
trap classes apply.

## Minimum specificity to pass

Both `(sid_presence, jti_prefix)` pairs must be filled with a concrete
six-character prefix and a `present`/`absent` for `sid`.

## Determinism check plan

After capturing the first set, mint a **second** of each grant and `jq -S`
both payloads. Diff modulo `iat`, `exp`, `jti` after the prefix (the
prefix itself must be stable; only the post-`:` UUID portion may vary),
`auth_time`, `session_state`, `sid` (UUID-valued, will differ across mints
even when present), and `nbf` if present. If the diff includes the
**prefix** of `jti` or the **presence/absence** of `sid` (i.e. one mint
has the key, the other doesn't), the fixture is non-deterministic and I
must redesign. The prefix is built from
`AccessTokenContext.SessionType`, which is decided at session-creation
time and pinned in the encoded token id — it must not vary across mints.

## Resolution after capture

Captured tokens at `actual-token-cc.json` and `actual-token-pwd.json`.

Headline observations (filled in post-mint):

- **client_credentials**: `sid` **absent**, `jti` prefix **`trrtcc:`**.
  `refresh_token` absent from the response envelope. Determinism
  cross-check: two mints, both produce `sid` absent and prefix `trrtcc:`;
  diff modulo `iat`/`exp`/post-`:` `jti` UUID was empty.
- **password**: `sid` **present** (value `47kTGgur5MzdlPXrEmc5vbyE` on
  the captured mint), `jti` prefix **`onrtro:`**. `refresh_token` and
  `session_state` both present in the response envelope. Determinism
  cross-check: two mints, both produce `sid` present and prefix
  `onrtro:`; diff modulo `iat`/`exp`/`sid`/`session_state`/post-`:` `jti`
  UUID was empty.

Both observations match the pre-mint expectations. See
`actual-token-cc.json`, `actual-token-pwd.json`, `log-cc.txt`,
`log-pwd.txt`. Surprises (small ones; mainly around log evidence) are
documented in `surprises.md`.
