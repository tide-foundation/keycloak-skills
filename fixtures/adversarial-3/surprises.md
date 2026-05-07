# Surprises encountered while building adversarial-3

## 1. The transient-nulling step itself emits no log line

Per invariant 12, `OAuth2GrantTypeBase.java:128-135` calls
`accessToken.setSessionId(null)` on the transient branch. The skill
already notes the related observation (the Hardcoded Claim mapper does
not log at TRACE) — adversarial-3 confirms the **same is true** of the
post-mapper sid-nulling site. With the realm running at
`KC_LOG_LEVEL: "INFO,org.keycloak.protocol.oidc.TokenManager:trace,…"`
(per `docker-compose.yml`), the captured `log-cc.txt` and `log-pwd.txt`
contain only:

- An `AcrProtocolMapper` TRACE pair (when the mapper inspects/sets the
  `acr`).
- A `TokenManager` TRACE line `Using full scope for client adv3-client`
  (because `fullScopeAllowed=true` short-circuits the role intersection,
  per invariant 6).
- A single `org.keycloak.events` INFO line per grant.

There is **no TRACE** at the `OAuth2GrantTypeBase` package level (it is
not in the explicit `:trace` allowlist in docker-compose.yml). Even if
it were, the source code at L120-135 has no log call to surface — the
nulling is silent.

This is consistent with the skill's existing claim that "Mapper internals
are not logged at any level — token bodies are the authoritative output."
Adversarial-3 extends that claim to the post-mapper transient nulling
step.

## 2. The events-listener output **does** show the L133 sibling clearing

Although L132's `accessToken.setSessionId(null)` produces no log, the
**very next line** (L133) is `event.session((String) null)` — clearing
the sessionId on the audit-event object. This is **observable** in the
captured logs:

- `log-cc.txt` (transient branch): the `CLIENT_LOGIN` event line has
  **no** `sessionId="…"` field. Compare to a default `CLIENT_LOGIN`
  event from a non-transient flow, which does include `sessionId`.
- `log-pwd.txt` (online branch): the `LOGIN` event line **does**
  include `sessionId="47kTGgur5MzdlPXrEmc5vbyE"`, matching the `sid`
  on the access-token payload.

So the L133 sibling line is **directly observable** in the events log.
This is a useful operator-facing diagnostic that the skill does not
currently mention — see the diff.md "Recommendation" section.

A verifier could in principle use the absence of `sessionId="…"` in
the JBoss-logging events output as a secondary anchor for "the
transient branch fired" without decoding the JWT.

## 3. The realm-config export masks `secret` but does not redact `attributes`

`adv3-client.secret` in `realm-config.json` is `"**********"` (the
admin REST API masks it on export — same behaviour as adversarial-1's
export). The actual secret used in the requests is
`adv3-secret-deadbeef`, captured verbatim in `request-cc.json` and
`request-pwd.json`.

For the skill seam this is irrelevant — the prediction target is `sid`
presence + `jti` prefix, neither of which depends on the secret value.
But a downstream re-importer of `realm-config.json` would need to set
the secret separately (or accept a regenerated one). Documented here
because the masking is non-obvious from a quick inspection of the
export.

## 4. The partial-export endpoint omits non-service-account users

Calling `POST /admin/realms/adv-3/partial-export?exportClients=true&exportGroupsAndRoles=true`
returned a JSON document whose `.users` array contained **only** the
auto-created `service-account-adv3-client` user — not `adv3-user`. To
produce a self-contained `realm-config.json` matching the shape of
adversarial-1's export (which includes the seam-relevant user), I had
to manually add `adv3-user` to the `.users` array via `jq`, sourcing
the fields from `GET /admin/realms/adv-3/users` and
`GET /admin/realms/adv-3/users/{id}/credentials`. The credentials
representation in the export is the credentialData JSON (argon2
parameters), not a re-importable plaintext.

This is a quirk of the admin REST API rather than a seam-property, but
worth noting because:

- The exported `realm-config.json` is **not** a round-trip realm import
  (it lacks the `secret` value, lacks the user's password hash beyond
  metadata, and would need post-import manual fix-up of both).
- A downstream consumer using the `realm-config.json` purely for skill
  reasoning (i.e., to predict tokens given the config) is unaffected:
  all the fields invariant 12 needs (`fullScopeAllowed`,
  `serviceAccountsEnabled`, `directAccessGrantsEnabled`, `attributes`)
  are present and accurate.

## 5. `client_credentials.use_refresh_token` is genuinely absent in the export, not represented as `"false"`

A potential reader concern: maybe Keycloak emits `"false"` as the
explicit value for absent attributes? Empirically, no. The post-export
`adv3-client.attributes` block contains only:

```json
{
  "realm_client": "false",
  "backchannel.logout.session.required": "true",
  "backchannel.logout.revoke.offline.tokens": "false"
}
```

No `client_credentials.use_refresh_token` key at all.
`jq '.attributes | has("client_credentials.use_refresh_token")'` returns
`false`. This is a useful confirmation for the skill: invariant 12's
"default" claim ("false" by default per
`OIDCConfigAttributes.java:77`) maps to **literally absent from the
exported attributes map**, not "explicitly set to false." A verifier
that reasons from a realm export must treat absence-of-key as
equivalent to `"false"` for this attribute, per the Java default.

## 6. The prediction did not need any hedge

A skill that lacks invariant 12 in this form would have hedged on the
client_credentials token's `sid` ("could be present or absent depending
on whether refresh_token is enabled, which is not visible from the
realm-config..."). Invariant 12 explicitly resolves the default to
`"false"` when the attribute is unset, so the hedge is not needed.

The only place a hedge **could** have been justified is on the exact
six-character form of the password-grant prefix — `onrtro:` is named in
invariant 12's prose but is not in the post-mapper.md prefix table
(which lists `trrtcc:`, `onrtcc:`, `oftcc:` — all `cc`-suffix). A
prediction agent reading only the prefix table without invariant 12's
prose would be unable to commit to `ro` versus an invented suffix. The
prediction here did consult the prose and so committed cleanly. This is
the one *small* skill-strengthening lever surfaced by adversarial-3 —
extending the prefix table to include the `ro` row.
