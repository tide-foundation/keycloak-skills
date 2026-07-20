---
name: keycloak-token-fixture-build
description: Methodology and templates for building adversarial test fixtures for the `keycloak-token-construction` skill, plus the two-phase fresh-context predictor harness. Covers single-leg grant fixtures and chained two-leg standard token-exchange fixtures (subject-token leg then exchange leg, `urn:ietf:params:oauth:grant-type:token-exchange`). Use when adding a new `tests/token-construction/adversarial-N/` fixture, validating a SKILL.md or references/ edit hasn't regressed an existing fixture, designing a seam to probe a specific invariant, deciding the verdict of a prediction-vs-actual diff, or coordinating the builder-then-fresh-predictor agent split. Engage proactively whenever a SKILL.md change is being considered or after one is made, since untested edits can silently regress invariants.
---

# Building adversarial fixtures for `keycloak-token-construction`

This skill operates exclusively on the `keycloak-token-construction`
skill (the **target skill**, at `skills/keycloak-token-construction/`)
and on `tests/token-construction/adversarial-N/` directories at the
repo root. It does not generalise to other skills.

In-scope: designing a seam to probe a specific invariant; constructing a
realm + client + scopes + mappers config that exercises the seam; capturing
a real minted token + bracketed Keycloak log; running a fresh-context
predictor against the public artifacts only; scoring the prediction vs.
actual; deciding the verdict.

Out-of-scope: editing the target skill's SKILL.md or references/ files —
that is a separate decision the human makes after reading a verdict. Also
out-of-scope: anything about authentication flows, signing, or other parts
of Keycloak that the target skill itself excludes.

## When to invoke this skill

Three triggers, in priority order:

1. **A new fixture is being added** to probe an invariant in the target
   skill that has no fixture yet. Goal: extend regression coverage.
2. **The target skill's SKILL.md or references/ was just edited** (or is
   about to be). Goal: re-run existing fixtures' fresh predictors against
   the changed skill text and confirm no regression.
3. **An existing fixture is producing a confusing verdict** and the
   diff.md needs to be re-scored or the seam re-evaluated. Goal: decide
   pass / fail-by-design / fail-skill-gap / fail-fixture-bug.

If the user is asking a Keycloak token-construction question (claim
provenance, mapper behavior, etc.) and is **not** asking to test or
extend the skill, this skill is the wrong tool — defer to the target
skill directly.

## Macro workflow

```
1. Pick an invariant, design a seam        → references/seam-design.md
2. Build realm + client + scopes via admin   (use scripts/new-realm.sh
   REST API; export realm-config.json        as a starting point if it
                                              exists; otherwise inline)

3. Write prediction-target.md BEFORE         → assets/prediction-target.template.md
   minting any token. Trap menu must be
   written before any actual values are
   known to anyone.

4. Mint the token; bracket the curl with     (use the target skill's
   timestamps; pull docker logs --since/      capture-tokens.sh /
   --until. Do a determinism check by         capture-with-refresh.sh
   minting twice and diffing.                 as the pattern.)

5. Spawn a FRESH predictor agent at the      → references/harness.md
   parent level with a strict allow/deny
   list of files. Predictor writes
   prediction.json.

6. Parent (which has seen actuals) writes    → assets/diff.template.md
   diff.md scoring prediction vs. actual.

7. Parent writes surprises.md with anything  → assets/surprises.template.md
   that didn't match pre-mint expectations.

8. Verdict: pass / fail-by-design /          → references/verdict-rubric.md
   fail-skill-gap / fail-fixture-bug.
   Decide whether the target skill needs
   an edit, or the fixture revealed a
   contract limit the skill correctly hedges.
```

**Token-exchange fixtures are two-leg** (mint a subject token, then
exchange it) and amend the ordering of steps 3–4: the commitment point
moves *between* the legs. Read
[references/token-exchange.md](references/token-exchange.md) before
starting one — it also carries the verified 26.5.5 exchange recipe and
the capture tooling (`scripts/capture-exchange.sh`).

## Critical invariants this harness must enforce

The fixture's value depends on these. A fixture that violates any of them
should be rebuilt before scoring.

1. **Pre-mint commitment is mandatory.** `prediction-target.md` and the
   trap menu in `setup.md` must be written and committed to disk before
   any token is minted. The order matters: once the actual token is
   visible to anyone, the prediction target's authority is gone — a later
   "prediction" is just the actual value paraphrased.

2. **The predictor agent must be spawned at the parent level**, not as a
   sub-agent of the builder. Sub-agents inherit the builder's context
   indirectly (the builder writes the prompt; the prompt can leak hints).
   Parent-spawned agents start with no shared state.

3. **The predictor's prompt must enumerate forbidden files explicitly**:
   `actual-token*.json`, `log*.txt`, `setup.md`, `surprises.md`,
   `diff.md`, the existing `prediction.json` if any, and any actual-token
   JSON in the target skill's own `fixtures/` (those are positive-control
   anchors that risk priming the predictor on specific token values
   rather than reasoning from skill text). See `references/harness.md`.

4. **Builders never write `prediction.json` themselves.** A builder has
   already seen the actual token; their prediction is contaminated.
   Builders write everything else: `setup.md`, `prediction-target.md`,
   `realm-config.json`, `request*.json`, `actual-token*.json`,
   `log*.txt`, `surprises.md`, `diff.md`. Predictor writes
   `prediction.json` only.

5. **Determinism check before scoring.** Mint the token at least twice;
   `jq -S` both decoded payloads; diff after stripping `iat`, `exp`,
   `jti`-suffix-after-prefix, `auth_time`, `session_state`, `sid`, `nbf`.
   If the diff includes the field under test, the fixture is non-
   deterministic and must be redesigned before it can be a regression
   test. (The `jti` *prefix* must be stable across mints; only the UUID
   after the colon may vary.)

6. **One realm per fixture, prefixed `adv-N`.** Multiple fixtures can
   share one Keycloak instance; collisions only happen on realm names.
   Don't tear Keycloak down between fixtures — parallel builders may be
   in flight.

7. **The seam must be probe-able from `realm-config.json` + request
   alone.** If the answer depends on UUID hash bucket order, JVM version,
   or other runtime state not captured in the realm export, the fixture
   has the wrong seam — either redesign (e.g., collapse two scopes into
   one to remove `HashSet` iteration variance), or accept that the
   correct verdict will be `fail-by-design` (skill correctly hedges; see
   adversarial-1 as the canonical example).

8. **Verdicts come in four shapes, not two.** `pass`, `fail-by-design`
   (skill correctly hedged a non-derivable answer), `fail-skill-gap`
   (skill committed to a wrong answer or missed a derivable one), and
   `fail-fixture-bug` (the seam was non-deterministic or the trap menu
   was incomplete). Only `fail-skill-gap` warrants a SKILL.md edit. See
   `references/verdict-rubric.md` for examples.

9. **Chained (token-exchange) fixtures move the commitment point
   between the legs — never after the token under test.**
   `request-2.json` must embed the literal leg-1 JWT, so leg 1 is
   minted *before* `prediction-target.md` is written; leg 2 (the token
   under test) is minted only *after*. The subject token is a public
   input artifact (published decoded as `subject-token.json`, never
   named `actual-token-1.json`), prediction targets may concern the
   exchanged token only, and both determinism mints of leg 2 must
   reuse the same subject token. Full rules:
   `references/token-exchange.md`.

## Routing — go to the right reference

- **"How do I pick a seam for invariant N?"** → [references/seam-design.md](references/seam-design.md)
- **"How do I spawn the predictor without contaminating it?"** → [references/harness.md](references/harness.md)
- **"What does this verdict mean? Should I edit SKILL.md?"** → [references/verdict-rubric.md](references/verdict-rubric.md)
- **"Which invariants have fixtures already?"** → [references/invariant-coverage.md](references/invariant-coverage.md)
- **"How do I build a token-exchange (two-leg) fixture?"** → [references/token-exchange.md](references/token-exchange.md)

## File layout per fixture

Required public artifacts (predictor sees these):

```
tests/token-construction/adversarial-N/
├── realm-config.json          # full realm export from admin REST API
├── request*.json              # token request body, one per request the fixture issues
└── prediction-target.md       # commit-or-fail criteria, trap menu
```

Required scoring artifacts (predictor must NOT read these):

```
tests/token-construction/adversarial-N/
├── setup.md                   # full pre-mint reasoning, seam description
├── actual-token*.json         # decoded JWT payload, one per request
├── log*.txt                   # bracketed docker logs slice, one per request
├── prediction.json            # written by the FRESH predictor agent only
├── diff.md                    # written by parent, scoring prediction vs actual
└── surprises.md               # anything that diverged from pre-mint expectations
```

Token-exchange fixtures add one public artifact and use numbered-leg
names: `request-1.json` (subject mint), `subject-token.json` (decoded
leg-1 payload — **public**, it is an input to the exchange),
`request-2.json` (the exchange request, embeds the literal
`subject_token` JWT), and scoring artifacts `actual-token-2.json` /
`log-*.txt`. The `actual-token*` deny-list is unchanged — the decoded
subject token is deliberately *not* named `actual-token-1.json`. See
[references/token-exchange.md](references/token-exchange.md).

Use the templates in `assets/` for `setup.md`, `prediction-target.md`,
`diff.md`, `surprises.md`. The `prediction.json` shape is the
fresh-context predictor's responsibility — give it
`tests/token-construction/adversarial-1/prediction.json` as a shape
reference in the prompt, but do not pre-fill it.

## Operational notes

- Keycloak runs from `skills/keycloak-token-construction/docker-compose.yml`.
  Bring it up with `docker compose up -d` from that directory; poll
  `http://localhost:8080/health/ready` until 200 (~30s). Do **not**
  `docker compose down` between fixtures — parallel builders may share
  the instance.
- Admin token: `POST /realms/master/protocol/openid-connect/token` with
  `grant_type=password&client_id=admin-cli&username=admin&password=admin`.
- Realm export: `GET /admin/realms/{realm}/partial-export?exportClients=true&exportGroupsAndRoles=true`
  — preserves the toggle attributes the seam depends on.
- Log capture pattern: bracket each curl with RFC3339 timestamps and
  pull `docker logs --since X --until Y keycloak`. The target skill's
  `capture-tokens.sh` is the canonical example.
- Password-grant users in Keycloak 26.5.5 require `firstName`,
  `lastName`, and `email` populated even when `requiredActions=[]` —
  `verify-profile` authenticator demands them at runtime. See
  `tests/token-construction/adversarial-1/surprises.md` for the failure mode.
- Standard token exchange works on the stock 26.5.5 stack with no
  compose change — enable it per client via the attribute
  `standard.token.exchange.enabled: "true"`. Legacy V1 exchange is NOT
  available (needs the preview `token-exchange` feature flag). Capture
  tooling: `scripts/capture-exchange.sh` (subcommands `subject` /
  `exchange <label>`; see `references/token-exchange.md`).
