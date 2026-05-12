# Diff — adversarial-3 prediction vs actual (regression rerun)

## Headline

| Grant | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| `client_credentials` | `sid` absent, `jti` prefix `trrtcc` | `sid` absent, `jti` prefix `trrtcc:` | ✓ |
| `password` (ROPC) | `sid` present, `jti` prefix `onrtro` | `sid` present, `jti` prefix `onrtro:` | ✓ |

**Fixture verdict: PASS — no regression** from the pre-org-docs baseline.

## Harness note

Fresh-context Agent spawned at parent level against the post-edit skill text. Forbidden file list excluded siblings and own `actual-token-cc.json`, `actual-token-pwd.json`, `setup.md`, `surprises.md`, `log-cc.txt`, `log-pwd.txt`, `prediction-fresh.before-org-docs.json`, `diff-fresh.before-org-docs.md`. Pre-edit artifacts preserved at the `.before-org-docs.*` paths.

## Regression check

Pre-edit verdict: PASS. Post-edit verdict: **PASS**. Both pairs `(absent, trrtcc)` and `(present, onrtro)` derived from invariant 12's grant-defaults table + post-mapper.md's `jti` decomposition. The docs edit does not affect this fixture — invariant 12, `OAuth2GrantTypeBase.useRefreshToken()` defaults, `AccessTokenContext.SessionType` enumeration all anchor unchanged.

## Verdict rationale

`adv3-client` has no `client_credentials.use_refresh_token` attribute set → defaults to `false` per `OIDCConfigAttributes.java:77`. For cc: both conditions of `OAuth2GrantTypeBase.L128-135` fire (useRefreshToken=false AND TRANSIENT) → `setSessionId(null)` → NON_NULL drops `sid` from the wire; `jti` prefix is `tr`(TRANSIENT) + `rt`(refresh-token-context) + `cc`(client-credentials) = `trrtcc`. For password: `OAuth2GrantTypeBase.useRefreshToken()` hardcoded `true` at L398 → L120 if-branch fires, the L130 transient check never runs, `sid` retained; `jti` = `on`(ONLINE) + `rt` + `ro`(ROPC) = `onrtro`.

## Recommendation

None. This fixture continues to anchor invariant 12's grant-defaults distinction (`useRefreshToken()` per grant) and the `jti` decomposition.
