# Prediction target

Given `realm-config.json` and `request.json`, what is the value of the `scope` claim in the resulting access-token payload?

The skill must commit to a single concrete answer of one of the following shapes:

- An **exact** space-separated string — every token in the right place: `"<tok1> <tok2> ... <tokN>"`. Commits both the set of names and the order. Treated as a full prediction.
- A **set commitment with order hedge**: the set of names AND `openid`'s position (first / last / wherever the skill says). Order of the other tokens declared "JVM-dependent / HashSet iteration / not contract-derivable." This is a structurally legitimate response per SKILL.md invariant 10. State the set explicitly.
- The string `"absent"` — predicted by a skill that believes the `scope` claim doesn't appear in this token at all.

Hedges of the form "depends on which scopes are attached," "any of the assigned scopes," or "the documented default scopes" — without naming the exact set — do not count as predictions.

Specifically the skill must answer:

1. **Set membership**: which of the following names are in the `scope` claim? `{openid, profile, email, basic, acr, roles, web-origins, adv2-scope-attr-unset, adv2-scope-attr-true, adv2-scope-attr-false, adv2-client}`. List which are in and which are out. (No hedging.)
2. **`openid` position**: where does `openid` sit relative to the others? (First / last / undefined.)
3. **Inter-scope order**: either commit to a specific permutation of the non-`openid` tokens, OR explicitly cite invariant 10 / `scope-resolution.md`'s lack of an order contract for the `Set<ClientScopeModel>` iteration — but if hedging, do so with a citation.

The diff will score each of these dimensions. A response that nails (1) and (2) but legitimately hedges (3) with a skill citation is a structurally complete pass even if the on-the-wire permutation doesn't match a specific prediction.
