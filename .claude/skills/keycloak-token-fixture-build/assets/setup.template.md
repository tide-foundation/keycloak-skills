# adversarial-N — [one-line seam summary]

## The seam

[2-4 paragraphs. State the specific invariant from the target skill's
SKILL.md being probed (cite by number). State the question whose answer
isolates the invariant. State the misread the seam is designed to
catch — the trap a vague reading would fall for. Explain why this
particular realm shape forces the commitment rather than admitting
hedges.]

## Realm / client / scope / mapper / user configuration

Realm: `adv-N` (fresh, prefixed `adv-` per the harness convention).

Client: `advN-client`
- [list relevant flags: confidential, fullScopeAllowed, directAccessGrantsEnabled, serviceAccountsEnabled, ...]
- [defaultClientScopes assigned, optionalClientScopes if any]
- [rationale for each non-default flag]

User: `advN-user-...` (omit if client_credentials only)
- [username, password, email, firstName, lastName — required for
  password grant per adversarial-1's surprises.md]
- [rationale for any non-default attributes]

Client scope(s): [list each, with]
- Protocol, includeInTokenScope value, mappers (with full toggle
  states), rationale.

Mapper choices: [Hardcoded Claim if zero user/role dependency; User
Property/Attribute if probing the user-data pipeline; etc. State why
THIS mapper type was chosen over alternatives.]

## The request

```
POST /realms/adv-N/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=...
client_id=advN-client
[client_secret=... if confidential]
[username=... password=... if password grant]
scope=...
```

[State exactly what's in the request and why. Note which custom scopes
are default-assigned (apply automatically) vs. requested by name.]

## Plausible outputs (the trap menu)

[Enumerate at least 4 specific predictions that a partially-correct
skill might land on. Each item names the specific misreading that
would produce it. Exactly one is the correct outcome; the rest are
traps.]

1. **[specific value]** — would be predicted by a skill that [specific
   misread description].
2. **[specific value]** — would be predicted by a skill that [different
   misread].
3. **[specific value]** — would be predicted by a skill that [different
   misread].
4. **[the correct outcome]** — the documented contract derives this.

[Optional 5th: non-deterministic across mints — invalidating the
fixture; flagged as a possibility, checked explicitly by the
determinism step.]

## Minimum specificity to pass

[State the precise commitment criterion. What must the predictor
output? What hedges are admissible (with skill citation), and what
hedges are not?]

## Determinism check plan

[State what fields will be stripped before the two-mint diff. Confirm
the field under test is NOT in the strip set. State what would
constitute a fixture failure here.]

## Resolution after capture

[Filled in AFTER minting. Actual observed value. Actual log evidence.
Cross-reference to determinism check result. Brief note on whether the
pre-mint trap menu correctly anticipated the answer or whether a 5th
trap had to be added.]
