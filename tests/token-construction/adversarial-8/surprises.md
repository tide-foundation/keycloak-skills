# Surprises encountered while building adversarial-8

## 1. `partial-export` is POST, not GET

Pre-mint expectation (from the harness skill's "Operational notes"):
`GET /admin/realms/{realm}/partial-export?exportClients=true&exportGroupsAndRoles=true`
returns the realm config.

Actual: at Keycloak 26.5.5, `GET` returns `HTTP 404 Not Found`. The
correct method is `POST` (with the same query parameters, no body).
`POST` returns 200 with the full JSON realm export.

Implication for the fixture: none for determinism or seam validity. But
the harness skill's `tide-stack`/operational-notes guidance was based on
the older `GET` pattern. The capture script for this fixture used `POST`
to recover.

Action: noted here so future fixture builders don't waste time
debugging an empty `realm-config.json`. Candidate edit: update the
`keycloak-token-fixture-build` skill's "Operational notes" line about
realm export to specify `POST` and reference KC 26.5.5. (No
behavioural impact on this fixture; logging-only.)

## 2. `jq` / `json.loads` collapse the duplicate `sid` key — cannot use as primary evidence

Pre-mint expectation: I planned to use `jq -S` to canonicalize the
decoded token bodies for the determinism diff.

Actual: parsers that produce a single map per JSON object collapse
duplicate keys to last-wins. `python3 json.loads`, `jq`, and any
ECMA-script `JSON.parse` all lose the first `sid` value. The duplicate-
key emission is only visible in the raw decoded base64-url string.

Implication: the canonical evidence for the seam's collision case (c)
is `actual-token-access-raw.txt` / `actual-token-id-raw.txt` (raw
strings preserving order), not `actual-token-access.json` /
`actual-token-id.json` (which are the jq-parsed, last-wins views).
Both files are kept in the fixture: the jq-parsed JSONs are for
human sanity (they show the rest of the token body cleanly) and the
raw .txt files are for the duplicate-key evidence.

The determinism check used `re.findall(r'"sid"\s*:', raw)` on the raw
string from each of the two mints. Both mints produced exactly 2
`"sid":` matches on both surfaces. The mapper-value half
(`OVERRIDDEN-SID`) was deterministic across mints; the dedicated-field
half (real session UUID) varied per mint as expected (each ROPC mint
yields a fresh `userSession.getId()`). The fixture's seam tests the
**count and ordering**, not the value of the first key, so this
variation is not a determinism failure.

Action: documented in `setup.md` Determinism check plan. The
keycloak-token-construction skill's `references/inputs-and-outputs.md`
already mentions wire-serialization caveats, but the specific "parsers
collapse duplicate keys" warning is implicit. A one-line addition to
the `references/mapper-execution.md` (c) section noting "decoded token
bodies must be inspected as raw strings, not jq-canonicalised, for
duplicate-key evidence" would be defensive but not strictly necessary.

## 3. `aud` is absent from the access token but present on the ID token

Pre-mint expectation: `aud` would appear on both surfaces (any token
typically has an audience).

Actual: access-token body has no `"aud":` key at all; ID-token body has
`"aud":"adv8-client"`.

Mechanism: `fullScopeAllowed=false` on `adv8-client` plus the user
holding no client roles whose owning client should be added →
`AudienceResolveProtocolMapper` writes null on the access token →
NON_NULL drops the claim (invariant 11). The ID-token `aud` is a
base-claim assignment in `generateIDToken` directly
(`idToken.aud ← client.getClientId()`, base-claims.md L80), so it
survives independently.

Implication for the fixture: none — the seam is about `azp`/`iss`/`sid`,
not `aud`. But this is a useful collateral demonstration of invariants
6 and 11 working together. The predictor's chain-of-thought noted that
`fullScopeAllowed=false` was a configuration choice "to keep role-based
mapping irrelevant to the seam," which it correctly was.

Action: none required. Noted as a foundation-soundness data point.

## 4. WARN logs at default `INFO` level for the OIDC-mappers category

Pre-mint expectation: the running Keycloak container's
`KC_LOG_LEVEL` environment variable includes
`org.keycloak.protocol.oidc.mappers:trace`, which is finer-grained than
the WARN threshold. I expected to see the WARN lines regardless of
that override.

Actual: the WARN lines appeared in the logs as expected — the
`notAllowedInToken` sentinel logs at WARN regardless of category-level
verbosity. The `:trace` override doesn't suppress WARN messages; it
adds finer-grained TRACE/DEBUG lines on top.

Implication: the WARN cardinality of 2-per-mint is observable in any
production Keycloak with default logging. Operators don't need to bump
the category to debug; the WARN is at INFO threshold or higher.

Action: none. This is consistent with what `references/mapper-
execution.md` subsection (b) already states ("appears at WARN
regardless of the `org.keycloak.protocol.oidc.mappers` log level").

## Reusable observations

- **The two-Python-stdin-via-heredoc bug.** Pattern `echo "$RESP" |
  python3 <<'PY' ... PY` does **not** work — the heredoc claims stdin
  and the piped data is discarded. Always pipe through a temp file
  (`echo "$RESP" > /tmp/r; python3 - <<'PY'\nimport json; ... open("/tmp/r")\nPY`)
  or use `python3 -c '...'` inline. Three of my capture commands ate
  cycles on this. Worth a note in the keycloak-token-fixture-build
  skill's capture-script guidance.

- **Admin token expires mid-fixture.** Long-running fixture builds
  (multiple curl calls spanning a few minutes) outlive the admin
  token's default 60s lifespan. Refresh the token before each major
  phase (realm setup, mint, export) rather than caching it once at
  the start. Already a known pattern; reinforced here.

- **Default `partial-export` excludes users.** The realm export does
  NOT include user records, only realm config + clients + roles +
  client scopes + protocolMappers. The predictor cannot see
  `adv8-user`'s email/firstName/lastName from `realm-config.json`
  alone — they have to infer from `request.json`'s username +
  password-grant context that the user exists with the credentials in
  the request body. This was not a problem for this fixture (the user
  data is irrelevant to invariant 15), but for fixtures whose seam
  depends on user attributes, an explicit user export step would be
  needed. Worth a note in seam-design.md.
