# Surprises — adversarial-7

Pre-mint expectations (from `setup.md`) vs. what minting actually showed.

## No surprises in the nine committed outcomes

All nine fields matched the builder's pre-mint table exactly. The
source-derived model (HardcodedRole injects into a session-scoped
resolved-roles cache at priority 20; consumer role-list / audience-resolve
mappers render it per their own per-surface toggles) held without
exception.

## Minor surprise: access-token `aud` is the owning client *only*

`aud` on the access token is the bare string `"adv7-resource"` — it does
**not** include `adv7-client`. The audience-resolve mapper was the only
`aud` contributor, and it adds exactly the owning clients of resolved
client roles (excluding the token's own client). There was no separate
"add the requesting client to aud" step on the access token for this
config. Worth remembering: an access token can have an `aud` that omits
the client it was issued to, when the only audience source is
audience-resolve over an injected client role.

## Minor surprise: flipping `id.token.claim` also set `userinfo.token.claim`

When the realm `roles`-scope `realm roles` mapper had `id.token.claim`
flipped to `true` via the admin REST API, Keycloak also stored
`userinfo.token.claim=true` on that mapper. This was incidental to the
fixture (it only strengthened the userinfo signal) but is captured here so
the realm-config export is not mistaken for hand-authored. The `client
roles` and `audience resolve` mappers were left at defaults.

## Logs empty

`docker logs --since/--until` produced zero lines for the bracket window.
Consistent with the target skill's standing note that mapper internals are
not logged at any level — token bodies are the authoritative output. The
`log.txt` is retained (empty) for artifact-shape parity with other
fixtures.
