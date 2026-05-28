# Prediction target — adversarial-8 (`mapClaim` reserved-name three-category split)

One token request (`request.json`, ROPC `password` grant, `scope=openid`)
is issued against `adv8-client` in realm `adv-8`. It yields an **access
token** and an **ID token**. All configuration is in `realm-config.json`.

`adv8-client` has `fullScopeAllowed=false` and carries three client-level
protocol mappers, all of type `oidc-hardcoded-claim-mapper`:

- `override-azp` — `claim.name=azp`, `claim.value=OVERRIDDEN-AZP`
- `override-iss` — `claim.name=iss`, `claim.value=https://evil.example.com`
- `override-sid` — `claim.name=sid`, `claim.value=OVERRIDDEN-SID`

All three mappers have `access.token.claim=true` and `id.token.claim=true`
(and `jsonType.label=String`). Examine the exact config in
`realm-config.json` rather than restating it from this paragraph; do not
take this paragraph as authoritative.

The skill must commit, with concrete values, to **all** of the following.
No item may be hedged unless a named SKILL.md invariant or `references/`
passage mandates the hedge.

## Committed questions

For each of the three claim names (`azp`, `iss`, `sid`) and each of the
two surfaces (access token, id_token):

- `routing_category` — exactly one of `modifiable` | `non-modifiable` |
  `collision` | `custom`. (The fourth value `custom` is what the predictor
  must commit if the name is neither in `tokenPropertySetters` nor a
  dedicated `@JsonProperty` field. It is in the menu so a misread can land
  there, not because the seam expects it to be correct.)

- `wire_shape` — exactly one of `single_key_mapper_value` |
  `single_key_base_value` | `duplicate_keys` | `absent`.

- `value_observed_under_last_wins_parse` — the exact string a permissive
  JSON parser (`json.loads`, jq) would expose at the claim key after
  parsing the token body. For `duplicate_keys`, this is one of the two
  values (the predictor must state which one and why).

For the `duplicate_keys` case specifically:

- `first_key_serialization_origin` — `dedicated_jsonproperty_field` |
  `other_claims_anygetter`. (Which mechanism emits the first occurrence
  of the duplicate key, given Jackson's default serialization order for
  `JsonWebToken` / `AccessToken` / `IDToken`.)
- `last_key_serialization_origin` — same enum.

Cross-cutting commitments:

- `warn_log_lines_per_mint` — exact integer count of
  `Claim '<X>' is non-modifiable in IDToken. Ignoring the assignment for
  mapper '<M>'.` WARN lines emitted by `OIDCAttributeMapperHelper` for a
  single token mint of this request.
- `warn_logger_category` — the Java logger category that emits those
  WARN lines. Must be the exact dotted package class name.
- `warn_log_surface_meaning` — does the literal phrase "in IDToken" in
  the WARN message refer to (i) the ID-token surface, or (ii) the
  `IDToken` Java class which is the superclass of `AccessToken`? Pick
  one.

## Required output shape

```json
{
  "access_token": {
    "azp": {
      "routing_category": "<modifiable|non-modifiable|collision|custom>",
      "wire_shape": "<single_key_mapper_value|single_key_base_value|duplicate_keys|absent>",
      "value_observed_under_last_wins_parse": "<exact string>"
    },
    "iss": { "...same shape..." },
    "sid": {
      "routing_category": "...",
      "wire_shape": "...",
      "value_observed_under_last_wins_parse": "...",
      "first_key_serialization_origin": "<dedicated_jsonproperty_field|other_claims_anygetter>",
      "last_key_serialization_origin": "..."
    }
  },
  "id_token": {
    "azp": { "...same shape..." },
    "iss": { "..." },
    "sid": { "...with first/last_key_serialization_origin if duplicate..." }
  },
  "warn_log_lines_per_mint": <integer>,
  "warn_logger_category": "<exact dotted classname>",
  "warn_log_surface_meaning": "<id_token_surface|IDToken_java_class>",
  "reasoning": "<cite SKILL.md / references passages per commitment>",
  "shapes_ruled_out_by_skill": ["..."],
  "skill_passages_invoked": ["..."],
  "fixture_target_compliance_note": "..."
}
```

The `value_observed_under_last_wins_parse` field for `sid` may use the
literal token `"<real_userSession_getId_value>"` to denote the real
session UUID (which the predictor cannot know in advance). The same
literal is acceptable in trap-rule-out reasoning. For all other claim
values the predictor must commit to an exact string.

## What does NOT count as a prediction

- "depends on the surface" for any claim where the toggle gate clearly
  passes on both surfaces (both `access.token.claim=true` and
  `id.token.claim=true` are explicit in `realm-config.json` for all
  three mappers).
- "either single key or duplicate" for any individual claim — resolve
  it from invariant 15's three-category routing.
- "the mapper write may or may not succeed" — invariant 15 specifies
  the outcome per category; commit.
- For the WARN count: declining to state a precise integer. Invariant 15
  specifies the cardinality rule ("once per surface where the mapper's
  toggle gate passed"). Apply it.
- For the `warn_log_surface_meaning`: hedging between the two
  interpretations of "in IDToken." The skill's new section is explicit
  on which interpretation is correct.

## Plausible outputs (the trap menu)

Exactly one combination is correct; it will be confirmed by minting. The
others are misreads a vague reading would let through. (No entry here is
marked correct — that is recorded only in `setup.md`, which the predictor
must not read.)

1. **All three claims show the mapper's value as a single key on both
   surfaces; `warn_log_lines_per_mint = 0`.** The misread the seam is
   built to defeat #1: a reader who treats `oidc-hardcoded-claim-mapper`
   as always-wins (since the mapper *fires* on both surfaces — toggle
   gate passes) and doesn't apply the `mapClaim`/`tokenPropertySetters`
   reserved-name filter at all.

2. **All three claims show the base server-owned value as a single key
   on both surfaces; `warn_log_lines_per_mint = 6`.** Misread #2: a
   reader who, having heard that base claims are "server-owned," treats
   every base-claim name as if it were in the `notAllowedInToken` set
   and predicts three WARN lines × two surfaces = 6.

3. **`azp` mapper-value single key, `iss` base value single key + 2 WARNs,
   `sid` mapper-value single key, no `sid` WARN.** Misread #3: a reader
   who correctly identifies `azp` as modifiable (category a) and `iss`
   as non-modifiable (category b), but conflates `sid` with the
   modifiable set (or doesn't notice `sid` is absent from
   `tokenPropertySetters` and would route through `otherClaims`),
   predicting it behaves like `azp`.

4. **`azp` mapper-value single key, `iss` base value single key + 2 WARNs,
   `sid` base value single key, no `sid` WARN.** Misread #4: same
   category-(b)-success as trap 3 but a reader who incorrectly extends
   the WARN-drop branch to cover `sid` silently (no log because the
   skill says only certain names log) — they correctly suppress the
   mapper write but wrongly suppress the duplicate-key emission.

5. **`azp` mapper-value single key, `iss` base value single key + 1 WARN
   (only on access-token pass, because the WARN message says "in
   IDToken" so the access-token pass doesn't log).** Misread #5: a
   reader who interprets "in IDToken" in the WARN literal as referring
   to the ID-token surface, not to the `IDToken` Java superclass, and
   predicts only one WARN line per mint (the ID-token pass).

6. **`azp` mapper-value single key, `iss` base value single key + 2 WARNs,
   `sid` two distinct keys (real session id + `OVERRIDDEN-SID`) with no
   WARN; `warn_log_lines_per_mint = 2`.** The combination invariant 15
   derives.

7. **Some other mixed combination** — fill in exact per-surface,
   per-claim values.

## Minimum specificity to pass

Every field in the output shape must hold a concrete value with no
hedge. `reasoning` must cite the specific mechanism that routes each
claim name through `mapClaim`, naming the invariant or reference passage
that governs (a) the `tokenPropertySetters` modifiable set, (b) the
`notAllowedInToken` sentinel and its WARN, and (c) the dedicated-field-
plus-otherClaims duplicate-key emission. A correct prediction must in
particular resolve:

- Whether `azp` is dispatched via `IDToken.issuedFor` or via
  `otherClaims["azp"]`.
- Whether `iss` produces a WARN, and on how many surfaces, given the
  mapper's toggle config in `realm-config.json`.
- Whether `sid` is in `tokenPropertySetters` at all, and what Jackson
  emits when a dedicated `@JsonProperty`-annotated field and an
  `otherClaims` key share the same name.
- Whether the WARN message's "in IDToken" phrasing constrains the
  surface on which the WARN fires.
