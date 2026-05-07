# adversarial-2 — composition of the `scope` claim under `isIncludeInTokenScope` defaults

## The seam

The fixture probes invariant 2: **"the `scope` claim is not the requested scope param."** A careless reader of the wire protocol thinks "I sent `scope=openid`, so the token's `scope` claim is `openid`." A careful reader of the skill knows the answer is `DefaultClientSessionContext.getScopeString()` — a projection over the *allowed* client scopes filtered by `ClientScopeModel.isIncludeInTokenScope()` (DCSC.L188-212), with the `ClientModel`-typed entry removed (DCSC.L200), and `openid` re-prepended via `TokenUtil.attachOIDCScope` if the original request matched `isOIDCRequest`.

Three counter-intuitive bits that a partial reading misses:

1. **An unset `include.in.token.scope` attribute defaults to `true`** (`ClientScopeModel.java:109-112`), not `false`. Most engineers reading "include in token scope" expect explicit-opt-in semantics. The Keycloak default is the opposite.
2. **Built-in scopes vary in their default value.** `profile` and `email` carry `include.in.token.scope=true` in this realm's export (so they appear). `roles`, `web-origins`, `basic`, `acr` carry `=false` (so they are filtered out). A prediction that lumps "all built-in default scopes" together is wrong.
3. **The DCSC.L200 self-filter is type-based, not name-based.** The filter is `.filter(NOT instanceof ClientModel)`, on the Java type. A `ClientScopeModel` named identically to the client's `clientId` is a different object — it survives the filter. A reader who conflates "the client itself is filtered out" with "anything named like the client is filtered out" mispredicts.

## Realm / client / scope / user configuration

Realm: `adv-2` (fresh, prefixed `adv-` per the parallel-agent coordination protocol).

Client: `adv2-client`
- Confidential, `directAccessGrantsEnabled=true` (Resource Owner Password Credentials grant — produces a real, named user without a browser flow).
- `fullScopeAllowed=false` so that scope is governed strictly by the assigned client scopes.
- `defaultClientScopes`: built-in defaults that Keycloak attaches automatically for OIDC clients (`web-origins`, `acr`, `roles`, `profile`, `basic`, `email`) plus four custom scopes assigned via the admin REST API:
  - `adv2-scope-attr-unset` — `include.in.token.scope` deliberately omitted (probes the default-true). Should appear.
  - `adv2-scope-attr-true` — explicit `true`. Should appear.
  - `adv2-scope-attr-false` — explicit `false`. Should be filtered out.
  - `adv2-client` — name deliberately equal to `clientId`. Probes whether DCSC.L200's `instanceof ClientModel` filter is type-based (correct skill reading) or name-based (incorrect). Per the skill's reading the type-based filter only removes the actual `ClientModel`; a `ClientScopeModel` with the same name is a distinct object and should survive. Should appear.

User: `adv2-user`
- Username `adv2-user`, password `password`, enabled, email verified, plus `firstName=Adv2`, `lastName=Scope`, `email=adv2-user@example.invalid`. The first/last/email fields are required for the password grant to succeed (per adversarial-1's `surprises.md` — Keycloak's `verify-profile` authenticator demands them at runtime even with `requiredActions=[]`). The user has no roles or attributes other than these, so there is no role-mapping interaction with scope resolution.

No protocol mappers configured beyond Keycloak's built-ins; the seam is purely about scope-claim composition.

## The request

```
POST /realms/adv-2/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=adv2-client
client_secret=<generated>
username=adv2-user
password=password
scope=openid
```

The custom scopes are assigned as **default**, so they apply automatically without naming. `scope=openid` in the request param triggers the OIDC re-attach path (`isOIDCRequest` → true → `attachOIDCScope` prepends `openid` to the projected string per DCSC.L207-209).

## Pre-mint reasoning — what should appear

Working through `getScopeString()` (DCSC.L188-212) on the union of attached default scopes:

| Scope | `include.in.token.scope` | Survives filter? |
| --- | --- | --- |
| `web-origins` | `false` (in this realm export) | no |
| `acr` | `false` | no |
| `roles` | `false` | no |
| `profile` | `true` | **yes** |
| `basic` | `false` | no |
| `email` | `true` | **yes** |
| `adv2-scope-attr-unset` | `<unset>` → defaults true | **yes** |
| `adv2-scope-attr-true` | `true` | **yes** |
| `adv2-scope-attr-false` | `false` | no |
| `adv2-client` (a scope) | `true` | **yes** (the DCSC.L200 filter is `instanceof ClientModel`, by type, not name; this is a `ClientScopeModel`) |
| The actual client (filtered to candidate set as a ClientModel) | n/a | filtered by DCSC.L200 |

Surviving set: `{profile, email, adv2-scope-attr-unset, adv2-scope-attr-true, adv2-client}`. Then `attachOIDCScope` prepends `openid`.

So the **set** in the `scope` claim is unambiguously `{openid, profile, email, adv2-scope-attr-unset, adv2-scope-attr-true, adv2-client}`. Six tokens.

## Order — is this fixture deterministic on order?

Per `scope-resolution.md` and DCSC.L188-212, `getScopeString` joins names by `" "` from a stream over `allowedClientScopes`. That backing collection is a `Set<ClientScopeModel>` (the allowed-set lazily computed from the `requestedClientScopes` set in DCSC). The skill does not commit to an iteration order over this `Set` — same shape as invariant 10's "HashSet iteration is JVM-dependent." The empirical evidence in adversarial-1's `log.txt` shows the runtime iteration order over the analogous scope set for that fixture is neither alphabetical, nor insertion-order on creation, nor insertion-order on default-scope assignment — it appears to be JVM `HashMap` bucket order over UUID hash codes.

That means the **set** of names in the `scope` claim is contract-derivable, but the **order** of the non-`openid` tokens is **not** derivable from the documented contract alone. `openid` itself is anchored: `attachOIDCScope` "prepends `openid` if absent" (per `scope-resolution.md` L110 and `research-notes.md` L252), so `openid` is first.

This produces an interesting per-fixture decision for the prediction agent: should the prediction commit to a specific permutation of the five non-`openid` tokens, or only to the *set* (ignoring order)? `prediction-target.md` clarifies the precise commit criterion below. Briefly: order is part of the wire `scope` claim, but the skill text alone does not nail it down. The honest skill response should commit on:

- **Set membership**: yes, the six names listed above.
- **`openid` position**: yes, first (prepended).
- **Order of the other five**: skill cannot derive from documented contract; this is an invariant-10-shaped ambiguity (HashSet iteration over allowedClientScopes).

## The trap menu

A partially-correct skill reading might commit to one of the following. Exactly one is correct as a *set*; the *order* of the wins is what splits the matches further.

1. `"openid"` — predicted by someone who reads the `scope` claim as the request param echoed back. Misses invariant 2 entirely.
2. `"openid profile email"` — predicted by someone who knows about the projection but believes only built-ins make it (forgets the four custom scopes attached as defaults).
3. `"openid profile email adv2-scope-attr-true"` — predicted by someone who assumes unset `include.in.token.scope` defaults to **false**. Misses `ClientScopeModel.java:109-112`'s default-true.
4. `"openid profile email adv2-scope-attr-true adv2-scope-attr-unset adv2-scope-attr-false adv2-client"` — predicted by someone who didn't read the `isIncludeInTokenScope` filter at all (lumps every default scope in).
5. `"openid profile email adv2-scope-attr-true adv2-scope-attr-unset"` — predicted by someone who correctly applies the filter but conflates DCSC.L200's type-based filter with name equality, removing `adv2-client` because its name matches the clientId.
6. `"profile email adv2-scope-attr-true adv2-scope-attr-unset adv2-client"` (no `openid`) — predicted by someone who missed the OIDC re-attach.
7. **Set** = `{openid, profile, email, adv2-scope-attr-true, adv2-scope-attr-unset, adv2-client}` with **`openid` first**, but the order of the remaining five is JVM-dependent — predicted by a skill that correctly applies invariant 2 *and* honors invariant 10's "HashSet iteration is non-deterministic" caveat.

Outcome 7 is the contract-derivable answer. Outcomes 1-6 each correspond to a specific misreading. The actual on-the-wire string will be exactly one permutation of outcome 7 — the "correct" one is whichever permutation the JVM happens to produce.

## Minimum specificity to pass

The skill must, given `realm-config.json` and `request.json`, identify the `scope` claim's exact set membership AND commit on `openid` being first. It may legitimately hedge on the order of the remaining five tokens — and the hedge is the honest answer per invariants 2 + 10. The fixture's diff will distinguish:

- **Pass**: skill commits to the correct set with `openid` first; explicitly flags the order of the five as JVM-dependent (the diff calls this `fail-by-design` of the strict-string-match criterion, because the skill correctly hedges).
- **Fail-skill-gap**: skill commits to a specific full permutation that turns out to be wrong, OR commits to a wrong set.
- **Lucky pass**: skill commits to a specific permutation that happens to match the JVM's iteration. Treated as `fail-by-design` even though strings match — the commitment was unsound.

## Determinism check plan

After capturing the first token, mint a second with an identical request. `jq -S` both decoded payloads. Diff after stripping `iat`, `exp`, `jti`, `auth_time`, `session_state`, `sid`, `nbf`. If the diff includes the `scope` field, this fixture is non-deterministic across mints (HashSet iteration varies between requests on the same JVM). That would invalidate the fixture's commit-to-an-exact-string framing and force me to redesign — likely by collapsing to scope membership only.

## Resolution after capture

Actual observed value of `scope` claim: **`"openid adv2-scope-attr-true adv2-client email adv2-scope-attr-unset profile"`** (see `actual-token.json`). Determinism check passed: both mints produced the identical scope string after stripping volatile fields.

Set commitment matched the pre-mint reasoning exactly: six tokens, the predicted six.

- `openid` first ✓
- `profile`, `email` survive (built-in `include.in.token.scope=true`) ✓
- `roles`, `web-origins`, `basic`, `acr` filtered (built-in `=false`) ✓
- `adv2-scope-attr-true` survives ✓
- `adv2-scope-attr-unset` survives — confirms `ClientScopeModel.java:109-112` default-true ✓
- `adv2-scope-attr-false` filtered ✓
- `adv2-client` (the scope) survives — confirms DCSC.L200's filter is `instanceof ClientModel` (type-based), not name-based. The same-name `ClientScopeModel` is a different object ✓

Order of the non-`openid` tokens: `adv2-scope-attr-true → adv2-client → email → adv2-scope-attr-unset → profile`. Per `log.txt`, the runtime iteration order over the full default-scope set is:

```
basic → adv2-scope-attr-false → adv2-scope-attr-true → null → adv2-client → email → roles → acr → web-origins → adv2-scope-attr-unset → profile
```

This is neither alphabetical, nor insertion-order on assignment (`["adv2-scope-attr-true", "adv2-client", "web-origins", "acr", "roles", "profile", "basic", "email", "adv2-scope-attr-false", "adv2-scope-attr-unset"]` per the realm export), nor anything else contract-derivable. Same shape as adversarial-1: it looks like JVM `HashMap` bucket order over UUID-derived hashes. The scope-claim-order is a deterministic projection of this iteration through the `isIncludeInTokenScope` filter — the filtered subsequence is exactly `adv2-scope-attr-true, adv2-client, email, adv2-scope-attr-unset, profile`, which matches the wire output. So order is **fully determined by the runtime iteration order over the underlying scope set**, which the skill correctly flags as JVM-dependent (invariant 10 territory).

The `null`-named scope in the log is the client-itself iterated as a `ClientScopeModel` (per adversarial-1's surprises §4) — confirmed here that the *named* scope `adv2-client` (UUID `ba3b5a50-…`) is a separate entry in the iteration, distinct from the client-itself `null` entry. This validates the type-based filter interpretation: there is one entry filtered as `instanceof ClientModel` (which logs as `null`) and one entry that survives as a `ClientScopeModel` named `adv2-client`.
