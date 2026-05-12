# Diff — adversarial-2 prediction vs actual (regression rerun)

## Headline

| | Value |
| --- | --- |
| Skill prediction (`prediction.json`) | Set IN: `{openid, profile, email, adv2-scope-attr-true, adv2-scope-attr-unset, adv2-client}`. Set OUT: `{basic, acr, roles, web-origins, adv2-scope-attr-false}`. `openid` first. Inter-scope order hedged with invariant 10 citation. |
| Actual on the wire | `"openid adv2-scope-attr-true adv2-client email adv2-scope-attr-unset profile"` (six tokens, openid first, remaining five in JVM HashSet bucket order). |
| Fixture verdict | **PASS — no regression** from the pre-org-docs baseline. Set membership exact, openid position exact, order legitimately hedged per the prediction-target's scoring rubric. |

## Harness note

Fresh-context Agent spawned at parent level against the post-edit skill text. Forbidden file list excluded siblings and own `actual-token.json`, `setup.md`, `log.txt`, `prediction.before-org-docs.json`, `diff.before-org-docs.md`. Pre-edit artifacts preserved at the `.before-org-docs.*` paths.

## Regression check

Pre-edit verdict: PASS. Post-edit verdict: **PASS**. Same set commitment, same openid-first commitment, same order-hedge with invariant 10 citation. The docs edit does not affect this fixture — invariant 2 + `scope-resolution.md` L99-121's `getScopeString` algorithm + the DCSC.L200 `instanceof ClientModel` filter (not name-based) all anchor unchanged.

## Verdict rationale

The six-name set is fully contract-derivable: `profile`/`email`/`adv2-scope-attr-true`/`adv2-scope-attr-unset` and the same-named `ClientScopeModel` named `adv2-client` all survive the `isIncludeInTokenScope` filter (defaults to true on unset; explicit true on the customs). The DCSC.L200 filter removes only the actual `ClientModel`-typed entry, not the `ClientScopeModel` named `adv2-client` — that's the central seam, and the predictor read it correctly. `openid` re-attached via `TokenUtil.attachOIDCScope`. The inter-scope-five order is JVM HashSet bucket order — same shape as invariant 10's mapper-sort tie — and the predictor honoured the hedge.

## Recommendation

None. This fixture continues to anchor invariant 2's three counter-intuitive bits: default-true on unset attribute, type-based DCSC.L200 filter, OIDC-marker re-attach.
