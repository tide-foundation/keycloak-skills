# Keycloak Skills — Agent Guide

You are working in a repo of reference skills for AI coding agents that touch Keycloak. Skills live under `skills/<skill-name>/SKILL.md`, plus an optional `references/` folder for deep dives.

This file applies whenever an AI tool **edits or authors** a skill in this repo. If you are only **using** a skill, read its `SKILL.md` directly — it is self-contained.

## What this repo is

- Bounded reference material designed to load into agent context on demand.
- Verified against specific Keycloak versions, declared per skill.
- Optimized for SPI development, schema work, and extension authoring.

## What this repo is not

- Not playbooks, prompts, templates, or evals.
- Not marketing or architectural storytelling.
- Not generic auth advice — Keycloak-specific or out.

## Accuracy bar

Every concrete claim in a skill must be accurate against the Keycloak version the skill declares. Class names, method signatures, table names, column widths, named queries, SPI interfaces, and Liquibase change IDs must match what actually exists in that version.

How you verify is up to you. What matters is the skill is right at the version it claims. If you can't confirm a fact for the declared version, omit it.

Live web docs drift across versions and lag the code — treat them as a starting point, not authority.

## Skill structure

Each skill follows the shape `keycloak-entities` established. Match it.

```
skills/<skill-name>/
  SKILL.md           # frontmatter + body, sufficient for ~80% of questions
  references/        # optional deep-dive files
    *.md
```

### Frontmatter

```
---
name: keycloak-some-topic
description: |
  One paragraph naming the symbols, tables, classes, and verbs the skill covers,
  ending with the verified Keycloak version. Under 1024 characters.
license: MIT
compatibility: Requires Keycloak X.Y.x. Some claims version-specific (KC NN+).
metadata:
  author: Tide Foundation
  version: 0.1.0
  keycloak-version: X.Y.Z
---
```

The `description` is what skill loaders match on when routing. List concrete symbols (`USER_ENTITY`, `JpaEntityProvider`, `KeycloakModelUtils`, etc.) so the loader picks the right skill.

**Frontmatter rules** (per Anthropic's skill format):

- `name` must be kebab-case, no spaces, no capitals, no `claude` or `anthropic` prefix.
- `description` is required. Must include WHAT the skill does AND WHEN to use it. Under 1024 characters.
- **No XML angle brackets (`<` or `>`) anywhere in frontmatter** — security restriction (frontmatter is loaded into Claude's system prompt). Use `[placeholder]` style instead.
- `license`, `compatibility`, `metadata` are optional but recommended for this pack.

### Body shape

1. One-line restatement of when to use the skill, plus the verified Keycloak version.
2. Source code layout — table of paths and what's in each.
3. Mental model — numbered list of 8–15 invariants.
4. Schema / API at a glance — diagram or reference card.
5. Patterns — recurring shapes the agent will see.
6. Gotchas — numbered, the things that trip people up.
7. Cheat sheet — "if you need X, look at Y".
8. Code patterns — short, copy-pastable.
9. Auto-routing — when to read each `references/` file proactively, without asking.

## Writing rules

- Short sentences. Bullets over paragraphs.
- Lead with the rule, then the reason.
- Cite Java class names, table names, and column names exactly as they appear in Keycloak.
- When mentioning a version-specific feature, name the version (`KC 25+`, `KC 26.0+`).
- No "etc.", no "best practices", no "modern", no marketing.

## Verification checklist before merging a skill

- [ ] `SKILL.md` filename is exact (case-sensitive). Folder is kebab-case, prefixed `keycloak-`.
- [ ] Frontmatter has `name` and a symbol-rich `description`.
- [ ] Description is under 1024 characters and includes both WHAT and WHEN.
- [ ] No `<` or `>` characters anywhere in frontmatter (use `[placeholder]` style).
- [ ] Skill name does not start with `claude` or `anthropic` (reserved).
- [ ] SKILL.md body is under ~5,000 words. Anything longer goes in `references/`.
- [ ] Body declares the exact verified Keycloak version (e.g. "Verified against Keycloak 26.5.5").
- [ ] Every named class, table, column, named query, and SPI is accurate at that version.
- [ ] Auto-routing triggers cover the cases the SKILL.md does NOT inline.
- [ ] At least one anti-pattern or common-failure note per major topic.
- [ ] No `README.md` inside the skill folder (the repo-level README is the only one).

## Anti-patterns

- Skills that paraphrase the official docs — no value over a web search.
- Skills that fabricate class or method names ("LLM-shaped" Java).
- Skills that claim version-agnosticism — Keycloak's model changes meaningfully across versions.
- Skills that bury the gotcha. Lead with what breaks.
- Skills that mix concerns. One skill = one bounded topic.

## Calibration target

Read [skills/keycloak-entities/SKILL.md](./skills/keycloak-entities/SKILL.md) end to end before authoring a new skill. That is the shape, density, and voice every other skill in this pack should match.
