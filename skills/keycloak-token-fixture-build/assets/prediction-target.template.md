# Prediction target

[1-2 sentence statement of the question. Reference `realm-config.json`
and `request*.json` as the inputs.]

The skill must commit to one of the following shapes:

- [shape 1: e.g., "an exact string value, exactly equal to one of: ..."]
- [shape 2: e.g., "the string `absent` if the claim is missing entirely"]
- [shape 3 if applicable: e.g., "a set commitment with explicit hedge on
  ordering — but only if SKILL.md invariant N admits the hedge with
  citation"]

Hedges of the form [list specific hedge phrases the seam is designed to
exclude — e.g., "depends on order," "either A or B," "implementation-
defined" — without skill citation] do not count as predictions.

## Required output shape

[For multi-token fixtures, specify the JSON shape per token. For single
predictions, state the field name and value type. Be explicit about
field names, allowed values, format constraints (e.g., "exactly six
characters before the colon").]

```json
{
  "[field_name]": "<specific value type>",
  ...
}
```

Plus a `reasoning` field per commitment citing the SKILL.md / references/
passages the commitment is sourced from.

## What does NOT count as a prediction

[Enumerate hedge phrases or output shapes the seam is designed to
exclude. Be specific. Each item explains what's wrong with that hedge.]

- "depends on [dimension]" without resolving the dimension for this
  config.
- "either [A] or [B]" without picking one.
- Refusing to commit on [specific dimension] because [reason that the
  skill text already addresses].

If the skill mandates a hedge for one of the commitments, the
prediction must cite the specific invariant or reference passage that
requires the hedge, and explain why that passage applies here while not
applying to [contrast case].

## Plausible outputs (the trap menu)

[Enumerate the same trap menu as setup.md. Number them; the correct
answer should be exactly one entry. The trap menu in this file is the
predictor's view; the trap menu in setup.md is the builder's view —
they should be the same content.]

1. **[shape, e.g., "Both have X"]** — would be predicted by a reader
   who [specific misread]. Wrong on [which token / which dimension]:
   [why].

2. **[shape]** — would be predicted by a reader who [different
   misread]. Wrong because [why].

3. **[shape]** — would be predicted by [different misread].

4. **[shape]** — the precise misread the seam is built to defeat:
   [reference to specific invariant in target skill].

5. **Correct combination — [the actual answer].**

## Minimum specificity to pass

[State the bar. What must be filled in with concrete values? What
hedges are admissible? Examples of pass shapes and fail shapes.]
