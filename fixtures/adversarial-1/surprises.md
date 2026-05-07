# Surprises encountered while building adversarial-1

## 1. The runtime scope iteration order is not what the JSON export suggests

`setup.md` framed three plausible iteration orders: alphabetical-by-scope-name, insertion-on-creation, and insertion-on-default-scope-assignment. The actual order observed in TRACE logs (`log.txt`) is none of those. The order in which `org.keycloak.protocol.oidc.TokenManager` processes default scopes for `adv1-client` is:

```
roles → basic → adv1-scope-alpha → null → web-origins → profile → email → adv1-scope-zulu → acr
```

Whereas the JSON export's `clients[].defaultClientScopes` array preserves assignment-insertion order: `[web-origins, acr, adv1-scope-zulu, roles, profile, adv1-scope-alpha, basic, email]`. The two orders disagree both on relative position of the custom scopes (`zulu` before `alpha` in the JSON, `alpha` before `zulu` at runtime) and on the position of the built-ins. The runtime order looks like JVM `HashSet` iteration over the underlying scope-by-id map, which depends on UUID hash codes.

Implication for the fixture: this fixture's answer (`value-from-zulu`) is reproducible **on this specific Keycloak instance with the specific scope UUIDs that happen to be assigned**. If the realm were re-imported and the scopes received different UUIDs whose bucket order put `zulu` before `alpha`, the answer would flip to `value-from-alpha`. The fixture file `realm-config.json` preserves the UUIDs (Keycloak's export includes them as `id` fields), so a re-import that preserves IDs should reproduce the result on the same JVM/Keycloak version. A re-import that regenerates IDs (or a different Keycloak version with different `HashMap` implementation) might not.

This is a useful adversarial property, not a bug in the fixture: it forces a skill consumer to either (a) commit to an answer based on a documented Keycloak contract, in which case the skill must say what the contract is and apply it, or (b) acknowledge that the answer depends on UUID hash order and is only knowable from execution evidence. Hedges of the form "depends on order" without naming the order are still excluded by `prediction-target.md`.

## 2. The "no required actions" user still failed login until profile fields were set

`setup.md` originally specified the user with only `username`, password, `enabled=true`, and `emailVerified=true`. The first two mint attempts failed with:

```
error="resolve_required_actions" reason="Account is not fully set up"
```

Even though:
- `users[].requiredActions` is `[]` on the user
- `userProfileMetadata` reports `firstName`/`lastName`/`email` as `required: false`
- The realm's required-actions list shows none with `defaultAction: true`

Setting `firstName=Adv1`, `lastName=Collision`, and `email=adv1-user-collision@example.invalid` cleared the error. The implicated component is the realm's `verify-profile` authenticator, which runs as part of the browser/direct-grant authentication flow and applies user-profile validation independently of the user's stored required-action list. This was a setup gotcha rather than a seam-property — but it is worth recording because it changed the user record from "minimal" to "fully populated," and a careless reader of `setup.md` might wonder why the user has firstName/lastName when the seam doesn't depend on them. Answer: the auth flow demanded them.

This does not affect the seam-property the fixture probes (the mappers are Hardcoded; user attributes are irrelevant to `collision_claim`). But it is a reminder that "minimal user setup" in Keycloak 26 is not as minimal as it looks from the admin REST API alone.

## 3. The Hardcoded Claim mapper does not log at TRACE

`OIDCAttributeMapperHelper` and the Hardcoded Claim mapper itself emit no TRACE statements during execution. The only TRACE evidence we get for the per-mapper run order on this surface is:

- `org.keycloak.protocol.oidc.TokenManager` "Adding client scope role mappings of client scope 'X'" lines, which iterate scopes in the same order used elsewhere
- `org.keycloak.protocol.oidc.mappers.AcrProtocolMapper` lines, which only fire for that one specific mapper

This means a skill cannot rely on log evidence alone to determine which mapper wrote the claim — it must reason from the iteration order combined with the resolution rule. Both inferences are required to predict the final value.

## 4. A mysterious "null"-named scope in the iteration

The TRACE log includes `Adding client scope role mappings of client scope 'null' to client 'adv1-client'`. There is no scope named `null` in the realm. This is likely the client itself iterated as a "scope-shaped" object whose name-as-string is the client's clientScope-name field, which is `null` for the client itself when iterated through the per-client scope-mapping API. It does not affect the collision (the client itself has no protocol mappers writing `collision_claim`), but it appears in the iteration and is preserved in `log.txt` for completeness.
