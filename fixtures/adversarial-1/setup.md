# adversarial-1 — collision between two mappers writing the same claim

## The seam

Two protocol mappers, living in two **separate** client scopes that are both assigned as **default** scopes on the same client, are configured to write to the **same access-token claim name** with **different scalar values**. Both mappers target only the access token (no ID-token / userinfo / introspection toggles enabled to keep the surface narrow). The seam being probed is whether a skill can predict, deterministically and concretely, which value lands in the issued token — i.e. whether the skill commits to a specific cross-scope mapper iteration order, or hedges by saying "depends on order." A vague description that says "later mappers overwrite earlier ones" is only useful if the skill also names which one runs later; otherwise it's not a prediction.

## Realm / client / scope / mapper / user configuration

Realm: `adv-1` (fresh, prefixed `adv-` per instructions; existing `myrealm` left alone).

Client: `adv1-client`
- Confidential client, `directAccessGrantsEnabled=true` (so we can use Resource Owner Password Credentials grant — gives us a real, named user in the token without needing a browser flow).
- `fullScopeAllowed=false` — we want scope to be governed exclusively by the assigned client scopes, not by full-scope passthrough; this isolates the seam.
- `defaultClientScopes`: built-in defaults (`profile`, `email`, etc.) plus `adv1-scope-zulu` and `adv1-scope-alpha`.
- `optionalClientScopes`: empty (other than Keycloak built-ins we don't request).
- Rationale for using two custom default scopes rather than two mappers in one scope: the most adversarial form of this seam is **cross-scope** ordering. Within a single scope, ordering is at least clearly "two mappers in one container." Across scopes, the question of which scope's mappers run first is a deeper internal-API detail and the most likely place for a skill to hand-wave.

User: `adv1-user-collision`
- Username `adv1-user-collision`, password `password`, enabled, email verified, plus `firstName=Adv1`, `lastName=Collision`, `email=adv1-user-collision@example.invalid`.
- The first three attributes were initially omitted on the theory that "no custom attributes = zero ambiguity about user state" — but the password grant failed with `error="resolve_required_actions" reason="Account is not fully set up"` until firstName/lastName/email were populated. The default Keycloak `verify-profile` authenticator demands them at runtime even though `userProfileMetadata` reports them as `required: false`. This is documented in `surprises.md`. The mappers are Hardcoded, so the values themselves still don't influence the seam — they exist purely to satisfy the auth flow.

Client scope: `adv1-scope-alpha`
- Protocol `openid-connect`, includeInTokenScope `false` (to keep `scope` claim out of the question — we are not testing scope-string composition here; we want only the `collision_claim` to vary).
- One mapper:
  - Name `collision-mapper-alpha`
  - Type: `oidc-hardcoded-claim-mapper`
  - `claim.name` = `collision_claim`
  - `claim.value` = `value-from-alpha`
  - `jsonType.label` = `String`
  - `access.token.claim` = `true`
  - `id.token.claim` = `false`
  - `userinfo.token.claim` = `false`
  - `introspection.token.claim` = `false`

Client scope: `adv1-scope-zulu`
- Same shape; `includeInTokenScope` `false`.
- One mapper:
  - Name `collision-mapper-zulu`
  - Type: `oidc-hardcoded-claim-mapper`
  - `claim.name` = `collision_claim`
  - `claim.value` = `value-from-zulu`
  - `jsonType.label` = `String`
  - Same surface toggles as alpha (access only).

Why Hardcoded Claim mapper specifically: it has zero dependency on user state, group state, role state, or any other realm data. The value it writes is fixed at configuration time. Two Hardcoded mappers writing to the same claim name is the *purest* form of the collision — anything else (User Attribute, User Property, etc.) would introduce a confound where one mapper might silently produce nothing because the source is missing, and we couldn't tell whether collision-resolution or source-missing semantics produced the result.

Why naming `alpha` / `zulu`: deliberately at opposite ends of the alphabet so that any of the following candidate orderings produce a different observable outcome:
- Alphabetical-by-scope-name → `alpha` first, `zulu` last.
- Insertion order on scope creation → I will create `zulu` first, then `alpha`. So insertion order = zulu first, alpha last. (Opposite of alphabetical.)
- Insertion order on `defaultClientScope` assignment → I will assign `zulu` first, then `alpha`. (Same as creation order: zulu first.)
- UUID-string ordering → effectively random; if this is the discriminant the result will look arbitrary.

Note that the mapper-name letters (`alpha` / `zulu`) are also at alphabet extremes, so if mappers are ordered by mapper name across the merged set rather than by their containing scope, that ordering is also observable.

## The request

A single token request via Resource Owner Password Credentials grant against `adv-1`'s token endpoint:

```
POST /realms/adv-1/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv1-client
client_secret=<generated>
username=adv1-user-collision
password=password
scope=openid
```

`scope=openid` only — the two custom scopes are default-assigned, so they apply automatically without being named in the request. We capture the resulting `access_token`, base64-decode the payload segment, and inspect `collision_claim`.

## Plausible outputs (the trap menu)

A partially-correct skill might predict any of the following. Exactly one is correct (to be discovered by minting); the rest are traps a vague description would let through.

1. **`collision_claim: "value-from-alpha"`** — would be predicted by a skill that believes cross-scope mapper ordering follows the alphabetical order of scope names, OR that mapper iteration is alphabetical by mapper name and "alpha" sorts before "zulu" (so "zulu" — being later — overwrites "alpha"... wait, that prediction would actually be `"value-from-zulu"`; the alphabetical-then-last-write-wins case predicts `zulu`, while alphabetical-then-first-write-wins predicts `alpha`).
2. **`collision_claim: "value-from-zulu"`** — would be predicted by a skill that believes ordering follows insertion order (zulu created and assigned first, alpha last) AND the resolution rule is "first write wins, later writes are dropped"; OR by a skill that believes alphabetical ordering AND "last write wins."
3. **`collision_claim: ["value-from-alpha", "value-from-zulu"]`** (or the reverse order) — would be predicted by a skill that believes Hardcoded Claim mappers merge into an array when the claim name collides, by analogy with multivalued user-attribute behavior.
4. **`collision_claim` absent entirely** — would be predicted by a skill that believes Keycloak detects the conflict at config time or runtime and refuses to emit either value.
5. **Non-deterministic across mints** — would invalidate the fixture; flagged as a possibility because the resolution might genuinely depend on JVM HashMap iteration order, which can vary by Keycloak version but is normally stable within a process. This will be checked explicitly by the two-mint determinism step.

The combinatorics of "ordering rule × resolution rule" mean a skill that hedges on either dimension cannot land on a single outcome. To pass, the skill must commit on **both** dimensions.

## Minimum specificity to pass

The skill must, given `realm-config.json` and `request.json`, predict a single concrete value for `collision_claim` from the menu above (one specific string, the array form with a specific element order, or "absent"). Hedges of the form "depends on mapper order," "either A or B," "the last-applied mapper wins" without naming which mapper is last-applied, or "implementation-defined" do not pass. The whole point of the fixture is to deny the skill the comfort of those hedges.

## Determinism check plan

After capturing the first token, I will mint a second one with an identical request and `jq -S` both payloads. Diff must be empty after stripping `iat`, `exp`, `jti`, `auth_time`, and `nbf` if present. If the diff includes `collision_claim`, the fixture is non-deterministic and I will redesign (most likely by collapsing the two mappers into a single scope to remove HashMap-iteration variance, or by switching to mapper types whose order is more clearly defined).

## Resolution after capture

Actual observed value: **`collision_claim: "value-from-zulu"`** (string). See `actual-token.json`. Both mints in the determinism check produced the same value (diff after stripping `iat`/`exp`/`jti`/`auth_time`/`session_state`/`sid` was empty).

The resolution rule is therefore **last-write-wins**: each scope contributes its `collision_claim` value via `setOtherClaim`, and a later contribution overwrites an earlier one. Confirmed by the log evidence below.

The iteration order is **NOT** what my pre-mint reasoning assumed. From the TRACE log (`log.txt`), the order in which Keycloak processes default client scopes for this client is:

```
roles → basic → adv1-scope-alpha → null → web-origins → profile → email → adv1-scope-zulu → acr
```

This is neither alphabetical (would be `acr → adv1-scope-alpha → adv1-scope-zulu → basic → email → profile → roles → web-origins`), nor insertion-on-creation (zulu was created first), nor insertion-on-default-scope-assignment (zulu was assigned first; the JSON export's `defaultClientScopes` array correctly shows `[..., adv1-scope-zulu, ..., adv1-scope-alpha, ...]`). The runtime order looks like JVM HashSet iteration on scope IDs (i.e. UUID hash-bucket order). In this iteration, `adv1-scope-alpha` happens to come before `adv1-scope-zulu`, so under last-write-wins, `zulu` is the value that survives.

My pre-mint guess "if iteration is alphabetical AND resolution is last-write-wins, then `zulu` wins" landed on the right value for the wrong reason. The mechanism is HashMap-iteration-based, not alphabetical. See `surprises.md` for the implications — most importantly, that this fixture's answer would be reproducible from `realm-config.json` only on a Keycloak instance that happens to assign UUIDs that hash to the same bucket order. A skill that predicts based on UUID hash order is over-fitting; a skill that predicts based on a documented contract should commit to whatever Keycloak's actual contract is, and the log here is part of the evidence corpus the skill consumer can reason from.
