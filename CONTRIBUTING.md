# Contributing

Thanks for adding to the pack. This file is the procedural how-to. The writing rules live in [AGENTS.md](./AGENTS.md).

## Add a new skill

1. **Pick a bounded topic.** One skill = one well-scoped Keycloak concern (e.g. "JPA entities", "SPI development", "themes"). If a skill description needs the word "and" twice, split it.

2. **Create the directory.**

   ```bash
   cp -r skills/_template skills/<skill-name>
   ```

   Skill names are kebab-case and prefixed `keycloak-` (e.g. `keycloak-spi-development`).

3. **Fill out `skills/<skill-name>/SKILL.md`** following the template's section order. The frontmatter `name` must match the directory name.

   The template uses `__FILL__` markers for every spot that needs editing. To work through them:

   ```bash
   # See every placeholder you still need to replace, with line numbers
   grep -n __FILL__ skills/<skill-name>/SKILL.md

   # When this returns 0, every placeholder is gone
   grep -c __FILL__ skills/<skill-name>/SKILL.md
   ```

   Delete the "This file is a template" banner near the top of the body before merging.

4. **Verify every concrete claim** against the Keycloak version you are targeting. Class names, table names, column widths, named queries, SPI interfaces, and changelog IDs must match. Declare the exact version in the body.

5. **Add deep-dive material to `references/`** only if it does not fit the ~80% rule. SKILL.md should answer the most common questions on its own; `references/*.md` are for the long tail. Add explicit auto-routing triggers in the SKILL.md so the agent reads the reference proactively.

6. **Update [README.md](./README.md)** — add a row to the skill table.

7. **Run the verification checklist** in [AGENTS.md](./AGENTS.md) before opening a PR.

## File layout

```
skills/<skill-name>/
  SKILL.md           # required, exact case, with frontmatter
  references/        # optional, deep-dive docs the agent loads on demand
    <topic>.md
  scripts/           # optional, executable helpers (Python/Bash) the agent runs
  assets/            # optional, templates/icons/etc. used in output
```

Skills are markdown-first. Add `scripts/` only if a check is genuinely deterministic (e.g. validating a changelog XML), not just for tasks the agent can do in language. Don't add a `README.md` inside the skill folder — the repo-level [README.md](./README.md) is for human visitors; in-skill docs belong in `SKILL.md` or `references/`.

## Frontmatter

Copy the scaffold from `skills/_template/SKILL.md` and fill it in. Required and optional fields:

```
---
name: keycloak-your-topic            # required, kebab-case, no capitals, no spaces
description: |                       # required, under 1024 chars, NO < or > anywhere
  Use for [when]. Covers [symbols, tables, classes, verbs].
  Verified against Keycloak X.Y.Z.
license: MIT                         # optional but recommended
compatibility: Requires Keycloak X.Y.x.   # optional, 1-500 chars
metadata:                            # optional, free-form key/value
  author: Tide Foundation
  version: 0.1.0
  keycloak-version: X.Y.Z
---
```

The `description` is matched by skill loaders and other agents to decide relevance. Pack it with the literal symbols a user would type — class names, table names, SPI interfaces, named queries. Vague descriptions don't get loaded.

**Hard rules** (Anthropic's skill format):

- No `<` or `>` characters anywhere in frontmatter (security: frontmatter goes into Claude's system prompt). Use `[placeholder]` style.
- Description max 1024 characters.
- Compatibility max 500 characters.
- Skill name must not start with `claude` or `anthropic` (reserved).
- No `README.md` file inside the skill folder. All in-skill docs go in `SKILL.md` or `references/`.

## Symbol accuracy

Every Java class, table, column, named query, and SPI you mention must exist in the Keycloak version the skill declares. How you confirm that is your call. If you can't confirm it, leave it out.

## Style

See AGENTS.md. The short version:

- Lead with the rule, then the reason.
- Bullets and tables over prose.
- No "etc.", no "best practices", no marketing.
- Each gotcha = one numbered entry, with the failure mode and the fix.
- Match the voice of `keycloak-entities/SKILL.md`.

## What not to add

- Skills that overlap heavily with an existing one — extend, don't fork.
- Skills that paraphrase the Keycloak docs without adding gotchas, source citations, or version-specific info.
- "Tutorials" — this pack is reference material, not pedagogy.
- CI / lint config / build scripts — premature.

## Reviewing a skill

Before merge, the reviewer should:

- Spot-check three random class or table names for accuracy at the declared version.
- Confirm the version in the body matches the version actually used to verify.
- Read the auto-routing section and make sure the triggers cover real questions a user would ask.
- Check that the cheat sheet table is exhaustive enough that a reader can answer "where does X live?" without reading the rest of the skill.
