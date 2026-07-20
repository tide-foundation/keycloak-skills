# The two-phase agent harness

The fixture is only meaningful if the predictor has not seen the answer.
This is the single most important property of the harness — protecting
it requires a specific topology, not just an honor system.

## Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│ Parent (you, applying this skill)                                   │
│                                                                     │
│   1. Spawns Builder ────────────┐                                   │
│                                  ▼                                   │
│                         ┌─────────────────┐                         │
│                         │ Builder agent   │                         │
│                         │                 │                         │
│                         │ Writes:         │                         │
│                         │  setup.md       │                         │
│                         │  prediction-    │                         │
│                         │    target.md    │                         │
│                         │  realm-config   │                         │
│                         │  request*       │                         │
│                         │  actual-token*  │                         │
│                         │  log*           │                         │
│                         │  surprises.md   │                         │
│                         │                 │                         │
│                         │ Does NOT write: │                         │
│                         │  prediction.json│                         │
│                         │  diff.md        │                         │
│                         └────────┬────────┘                         │
│                                  │ reports actuals back              │
│                                  ▼                                   │
│   2. Spawns Predictor ──────────┐                                   │
│      (parent-level, NOT a       │                                   │
│       sub-agent of builder)     │                                   │
│                                  ▼                                   │
│                         ┌─────────────────┐                         │
│                         │ Predictor agent │                         │
│                         │                 │                         │
│                         │ May read:       │                         │
│                         │  SKILL.md +     │                         │
│                         │   references/   │                         │
│                         │  realm-config   │                         │
│                         │  request*       │                         │
│                         │  prediction-    │                         │
│                         │    target.md    │                         │
│                         │  adv-1's        │                         │
│                         │   prediction.   │                         │
│                         │   json (shape   │                         │
│                         │   ref only)     │                         │
│                         │                 │                         │
│                         │ MUST NOT read:  │                         │
│                         │  actual-token*  │                         │
│                         │  log*           │                         │
│                         │  setup.md       │                         │
│                         │  surprises.md   │                         │
│                         │  diff.md        │                         │
│                         │  prediction.json│                         │
│                         │   (existing)    │                         │
│                         │  target skill's │                         │
│                         │   fixtures/*    │                         │
│                         │   token-*.json  │                         │
│                         │                 │                         │
│                         │ Writes:         │                         │
│                         │  prediction.json│                         │
│                         └────────┬────────┘                         │
│                                  │                                   │
│   3. Parent writes diff.md ─────┘                                   │
│      (parent has seen actuals via builder report;                   │
│       not contaminated for the diff phase, only                     │
│       contaminated for prediction)                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Why parent-level spawn matters

The Agent tool description states sub-agents start with no memory of
prior runs. That is true for *prompt* context — but a builder agent's
prompt to its own sub-predictor is written by the builder, who has seen
the actuals. The builder cannot avoid leaking hints in the prompt
(consciously or not). A predictor spawned by the parent receives a
prompt written by the parent **before** any actual values are minted —
or, more practically, written from a generic template that doesn't
reference the specific token values.

The parent itself is partially contaminated after the builder reports
back (the builder's summary mentions actuals). That's why the parent
writes `diff.md` (which needs actuals) but does **not** write
`prediction.json`.

In practice: spawn both Builder and Predictor with the `Agent` tool from
the parent's tool list, not from inside the builder.

## The predictor prompt template

```
You are a fresh-context prediction agent. Your sole job: predict
[the specific commitment from prediction-target.md] by applying the
`keycloak-token-construction` skill at
`/home/sam/keycloak-skills/skills/keycloak-token-construction/`.
You will be evaluated by comparison against an actual minted token that
you must not see.

# Inputs you MAY read
- The target skill folder: `skills/keycloak-token-construction/`
  — read SKILL.md and references/ as needed. Cite the skill explicitly.
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/realm-config.json`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/request*.json`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/prediction-target.md`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-1/prediction.json`
  for shape reference only (different fixture, no contamination).

# Inputs you MUST NOT read (contamination)
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/actual-token*.json`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/log*.txt`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/setup.md`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/surprises.md`
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/diff.md` (if exists)
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/prediction.json`
  (the file you will write)
- Any actual-token JSON in
  `skills/keycloak-token-construction/fixtures/` — those are
  positive-control fixtures from the skill's own validation; reading
  them risks anchoring on specific token values rather than reasoning
  from the skill text.

If you accidentally read one of the forbidden files, say so explicitly
in your output and continue — but do not retroactively change your
prediction based on it.

# Output
Write `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/prediction.json`.
Adopt the same shape as `/home/sam/keycloak-skills/tests/token-construction/adversarial-1/prediction.json`.
At minimum include the committed value, `shapes_ruled_out_by_skill`,
`skill_passages_invoked`, `reasoning`, and `fixture_target_compliance_note`.

# Final report
Under 200 words. State the committed value, key invariants applied, and
any moments where the skill text was ambiguous or insufficient — that's
the actionable feedback.
```

Use this template verbatim and substitute `N` and the per-fixture
specifics. Do not paraphrase the "must not read" list — explicit
filenames defeat ambiguity.

## When the predictor can't commit

If the predictor's output is `"UNVERIFIABLE"` or hedges with skill
citation, that's a legitimate response — it means the skill correctly
identified a non-derivable answer. The verdict is `fail-by-design` (see
`verdict-rubric.md`), not `fail-skill-gap`. Adversarial-1 is the
canonical example.

If the predictor commits but commits wrong, that's `fail-skill-gap` —
the skill's text led the predictor astray. SKILL.md or references/
warrant an edit.

If the predictor commits correctly with citations, that's `pass`.
Strongest signal: agent reports "skill text was sufficient" and the
commitment lands exactly.

## Chained-flow (token-exchange) addendum

Two-leg fixtures (see [token-exchange.md](token-exchange.md)) keep this
topology unchanged but amend the inputs:

- **Ordering**: the builder mints leg 1 (subject token) *before*
  `prediction-target.md` exists. The commitment point sits between the
  legs; only the token under test (leg 2) is minted after commitment.
- **The subject token is a MAY-read input, not contamination.** It is
  embedded in `request-2.json` and published decoded as
  `subject-token.json`. Add both to the predictor's MAY-read list. The
  MUST-NOT-read list is unchanged — leg-1's decoded payload is never
  named `actual-token-1.json`, so the `actual-token*` deny pattern
  stays correct verbatim.
- **Predictor prompt additions** (append to the MAY-read section of the
  template below):

```
- `/home/sam/keycloak-skills/tests/token-construction/adversarial-N/subject-token.json`
  — the decoded subject token from leg 1. This is an INPUT to the
  exchange under test, like realm-config.json. Your prediction concerns
  ONLY the exchanged token minted by request-2.json; treat every
  subject-token claim as a given, not something to predict.
```

- **Extra deny-list entry**: for exchange fixtures, add
  `skills/keycloak-token-fixture-build/` (this skill's own folder) to
  the predictor's MUST-NOT-read list. `references/token-exchange.md`
  carries builder-side analysis of the exchange seam — including
  target-skill discrepancy notes — that would contaminate a predictor.
  Single-leg fixtures never needed this line because this skill's
  files contained no target-skill answers; the exchange reference
  does.
- **Scoring**: `diff.md` compares the prediction against
  `actual-token-2.json` only. A prediction that merely restates
  subject-token claims is out of scope for scoring (and a sign the
  seam is wrong — see token-exchange.md anti-patterns).

## Re-running predictors after a SKILL.md edit

Existing fixtures double as regression tests. After any edit to the
target skill's SKILL.md or references/:

1. For each existing `tests/token-construction/adversarial-N/`, delete `prediction.json`
   and `diff.md` (preserve them in git history if they were
   pass-verified — but don't keep them as files because the predictor
   would read them).
2. Re-spawn a fresh predictor for each fixture using the same template.
3. Re-write each `diff.md`.
4. Compare verdicts to the previous run. A previously-passing fixture
   that now fails is a regression in the skill edit; a previously-
   failing fixture that now passes is a fix.

If you have many fixtures, run the predictors in parallel (one Agent
tool call per fixture, all in one message).
