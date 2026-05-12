# Diff — adversarial-4 prediction vs actual (regression rerun)

## Headline

| | Value |
| --- | --- |
| Skill prediction (`prediction.json`) | Member access+ID: trap **4**, `["acme"]`. Nonmember access+ID: trap **1**, absent. Scope set `{openid, profile, organization, email}`. ID-token `scope` absent. |
| Actual on the wire | Member access+ID: `["acme"]` exactly. Nonmember access+ID: claim absent. Scope set matches; ID-token has no `scope` field. |
| Fixture verdict | **PASS — verdict-flip from pre-org-docs FAIL-SKILL-GAP.** The new `references/organizations.md` §1, §2, §3.1 + SKILL.md invariant 13(a) directly settled the wire-shape question that the pre-edit predictor got wrong. |

## Harness note

Fresh-context Agent spawned at parent level against the post-edit skill text. Forbidden file list explicitly excluded sibling adversarial fixtures (1, 2, 3, 5, 6 — adv-5 and adv-6 contain related organisation-claim data that would invalidate fresh-context). Also excluded own `actual-token-*.json`, `actual-id-token-*.json`, `log-*.txt`, `setup.md`, `surprises.md`, and the pre-edit artifacts at `prediction.before-org-docs.json` + `diff.before-org-docs.md`.

## Regression check

Pre-edit verdict: **FAIL-SKILL-GAP** (predicted `{"acme": {}}` — trap 5; actual `["acme"]` — trap 4). Post-edit verdict: **PASS**. The flip is driven directly by `references/organizations.md` §1, which states the OOTB mapper config emits `["alias"]` as a flat array of alias strings, plus §2 which states zero-membership produces NON_NULL drop (not `[]` or `{}`), plus §3.1 which confirms the single-membership lucky-path.

## Per-dimension scoring

| Dimension | Predicted | Actual | Match? |
| --- | --- | --- | --- |
| Member access-token `organization` | `["acme"]` (trap 4) | `["acme"]` | ✓ |
| Member ID-token `organization` | `["acme"]` (trap 4) | `["acme"]` | ✓ |
| Nonmember access-token `organization` | absent (trap 1) | absent | ✓ |
| Nonmember ID-token `organization` | absent (trap 1) | absent | ✓ |
| Member access-token `scope` set | `{openid, profile, organization, email}` | matches | ✓ |
| Nonmember access-token `scope` set | `{openid, profile, organization, email}` | matches | ✓ |
| ID-token `scope` absent | absent | absent | ✓ |

All seven scored dimensions match. The predictor explicitly cited the new docs sections in its `reasoning` and `skill_passages_invoked` arrays.

## Methodological note (caveat)

The docs encode the empirical fixture outcomes — `organizations.md` §1 uses `["acme"]` as the canonical shape example, anchored by adv-4. The predictor reading the docs and committing `["acme"]` is partly reading the answer for its own fixture. This is a normal property of empirically-derived documentation: the fixtures generated the evidence, the docs encode the evidence, and a predictor reading the docs commits the evidence. To preserve adv-4 as a future blind-regression seam, a new fixture with different alias names would be needed. For *this* edit, the rerun confirms the docs are precise enough to be followed — the predictor cited the relevant sections and reproduced the right commitment.

## Recommendation

None for the target skill — the docs edit is verified to flip this fixture's verdict to PASS. The methodological caveat above is a future-fixture concern, not a current skill concern.
