# Seam design

Picking a "seam" means choosing a single, narrow question whose answer is
unambiguously derivable from one specific invariant in the target skill.
A good seam is the smallest realm config that forces the question and
admits exactly one correct answer (or one correct hedge).

## Step 1 — Pick the invariant

Re-read SKILL.md's "Critical invariants" list. Each numbered invariant
is candidate for a fixture. Some are easier to probe than others:

| Invariant | Probe difficulty | Notes |
| --- | --- | --- |
| 1. `sub` only set by initToken on transient sessions | Medium | Need a transient session (client_credentials with `use_refresh_token=false`) and contrast with the SubMapper-set case |
| 2. `scope` claim composition | **Easy** | Mix scopes with `include.in.token.scope` true / false / unset; covered by adversarial-2 |
| 3. Lightweight access-token toggle | Medium | Need `client.use.lightweight.access.token.enabled=true` plus a mapper with conflicting `access.token.claim` / `lightweight.claim` |
| 4. Introspection fallback ignores lightweight | Hard | Requires the introspection endpoint flow + lightweight mode + a mapper with the specific toggle combination |
| 5. Userinfo fallback uses `id.token.claim` | Easy | One mapper with `userinfo.token.claim` unset, `id.token.claim=true`, `access.token.claim=false`; userinfo response has the claim |
| 6. `fullScopeAllowed` short-circuits role intersection | Easy | Two clients identical except for the flag; covered partially by the existing `test-client` / `test-client-restricted` pair |
| 7. ID-token base claims sourced from transformed access token | Medium | A mapper that mutates the access token and check the ID token inherits |
| 8. `restrictRequestedAudience` post-mapper | Hard | Token exchange or requested-audience refresh flow |
| 9. `at_hash`/`c_hash`/`s_hash` out of model | Trivial | Out of skill scope — not worth a fixture |
| 10. Mapper sort tie non-determinism | **Easy** | Two mappers, same priority, same claim; covered by adversarial-1 |
| 11. NON_NULL drops null claims | **Easy** | A mapper with a missing source value; covered indirectly by every fixture |
| 12. Transient `sid` nulling | **Easy** | Single client, two grants (cc vs password); covered by adversarial-3 |

Already covered: 2, 6 (partial), 10, 11 (indirect), 12.

Open coverage gaps as of this writing: 1, 3, 4, 5, 7, 8.

## Step 2 — Identify the trap

For the chosen invariant, identify the most likely **misread**. The seam
should force the misread to produce a different observable answer than
the correct read. If both readings produce the same answer, the fixture
proves nothing.

Examples from existing fixtures:

- **adversarial-1 (invariant 10)**: trap is "later mappers overwrite
  earlier ones" without naming which is later. Two mappers writing the
  same claim with different values force the reader to commit on
  ordering, not just resolution.
- **adversarial-2 (invariant 2)**: trap is "the `scope` claim is the
  request scope param echoed back." Multiple scopes with mixed
  `include.in.token.scope` values force the reader to apply the filter,
  not just echo.
- **adversarial-3 (invariant 12)**: trap is "every Keycloak token has
  `sid`" or "client_credentials always nulls `sid`." Two grants on one
  client force the reader to apply the conditional, not a blanket rule.

## Step 3 — Construct the trap menu

`prediction-target.md` should enumerate at least four plausible-but-wrong
predictions plus the correct one, **before** the token is minted. Each
trap should map to a specific misread of the invariant. Goals:

- A skill that hedges on the underlying dimension cannot land on a
  single trap; it lands on "depends on X." If the skill's invariants
  warrant that hedge, the verdict is `fail-by-design`, not
  `fail-skill-gap`.
- A skill that misapplies the invariant lands on a specific wrong trap.
  The trap-menu structure makes the misapplication legible in the diff.

See `assets/prediction-target.template.md` for the structure.

## Step 4 — Pick the simplest realm

Always start from minimum config and add only what the seam requires.
Heuristics:

- **One realm**, name `adv-N` where N is the next adversarial fixture
  number.
- **One client** unless the seam requires comparing two configurations
  (e.g., adversarial-3 could have used two clients but chose one client +
  two grants — simpler).
- **Confidential client, `directAccessGrantsEnabled=true`** for password
  grant access. `serviceAccountsEnabled=true` only if you need
  `client_credentials`.
- **`fullScopeAllowed=false`** unless the seam is *about* full-scope
  behavior — keeps scope governed by explicit assignments.
- **Hardcoded Claim mapper** when you need a deterministic claim value
  with zero dependency on user / role / session state. Use User Property
  / User Attribute mappers only when the seam *is* the user-data
  pipeline.
- **No optional scopes assigned** unless the seam tests optional-scope
  request behavior. Default scopes only.

## Step 5 — Anti-overfit check

Before minting, ask: "If Keycloak generated different scope UUIDs on
re-import, would the answer flip?" If yes, the seam depends on JVM hash
order and the verdict will be `fail-by-design`. That's a legitimate
fixture (adversarial-1 is exactly this), but it must be designed
**knowing** that's the verdict — the trap menu and prediction-target.md
should make hedging an explicit option, not a workaround.

If you want a deterministic answer and the seam is currently
hash-dependent, redesign: collapse multiple mappers/scopes into one,
introduce explicit priority differences, or pick a different invariant.

## Step 6 — Determinism plan

Before minting, decide which fields you'll strip when comparing two
mints. Default strip set:

```
iat, exp, auth_time, session_state, sid, nbf,
jti-suffix-after-the-colon (UUID, not the prefix)
```

If the field your seam tests is in this set (e.g., your seam tests
`sid`), you cannot strip it during the determinism check — that field
must be deterministic across mints in its own right. If it isn't, the
seam is broken.

## Step 7 — Build the realm, then export

Build via admin REST API (curl + jq), step by step. Don't write a
`realm-config.json` and import — building step-by-step lets you verify
each call's response and catch admin-API rejections early.

After everything is configured, export the full realm via
`/admin/realms/{realm}/partial-export?exportClients=true&exportGroupsAndRoles=true`.
That export is `realm-config.json` — the public artifact the predictor
sees. Verify the toggles your seam depends on are preserved in the
export (some Keycloak attributes are stored as strings vs. booleans;
some unset attributes are omitted entirely vs. emitted as empty).
