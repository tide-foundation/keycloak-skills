---
name: keycloak-__FILL__skill-name
description: |
  Use for __FILL__one-line-trigger. Covers __FILL__list-of-concrete-symbols-tables-classes-verbs-named-queries.
  Verified against Keycloak __FILL__version.
license: MIT
compatibility: Requires Keycloak __FILL__version. Some claims are version-specific (KC __FILL__minimum-version+).
metadata:
  author: Tide Foundation
  version: 0.1.0
  keycloak-version: __FILL__version
---

# __FILL__skill-title — Reference Skill

> **This file is a template.** Copy `skills/_template/` to `skills/<your-skill-name>/`, then replace every `__FILL__` token with real content. Run `grep -n __FILL__ skills/<your-skill-name>/SKILL.md` to find every spot you still need to edit. When `grep` returns nothing, the skill is filled in. Delete this banner before merging.

__FILL__one-paragraph-statement-of-when-to-use-and-scope. Example pattern: "Expert reference for X. The skill is structured so this file alone covers most needs (~80% of questions); read the reference files for deep dives."

Verified against Keycloak __FILL__version.

---

## Source Code Layout

__FILL__table-of-keycloak-source-paths-relevant-to-this-skill.

| Path | What's there |
|---|---|
| `__FILL__path` | __FILL__one-line |

---

## Mental Model

__FILL__numbered-list-of-8-to-15-invariants. These are the things a reader must hold in their head before any specific table or method makes sense. Lead with the most load-bearing concept.

1. __FILL__invariant
2. __FILL__invariant

---

## __FILL__schema-or-api at a Glance

__FILL__diagram-table-or-reference-card. For schema skills, an ASCII tree of related tables. For SPI skills, a diagram of the provider interface and adapter relationships.

---

## Patterns

__FILL__recurring-shapes-in-this-area. Each pattern gets a name, a one-line definition, and 2–4 concrete examples from real Keycloak code.

### Pattern 1: __FILL__pattern-name
- __FILL__definition
- Examples: __FILL__real-symbols

### Pattern 2: __FILL__pattern-name

---

## Common Gotchas

__FILL__numbered-list-of-things-that-trip-people-up. Each gotcha leads with the failure mode, names the symbol or column or version where it bites, and ends with the fix or correct mental model.

### 1. __FILL__gotcha-title
__FILL__description-then-fix.

### 2. __FILL__gotcha-title

---

## Cheat Sheet

__FILL__two-column-table: "If you need X" → "Look at Y". Exhaustive enough that a reader can answer most lookup questions without reading the rest of the skill.

| If you need... | Look at... |
|---|---|
| __FILL__need | __FILL__where |

---

## Common __FILL__jpql-or-api-or-code Patterns

__FILL__short-copy-pastable-snippets. Each has one line of context above it, uses real Keycloak class and method names, and shows the WRONG way alongside the right way when there's a common trap.

### __FILL__snippet-title
```java
// __FILL__snippet
```

---

## Auto-Routing — read references PROACTIVELY without being asked

__FILL__triggers-for-each-references-file. Be explicit; the agent should not need to ask permission.

### Read `references/__FILL__file.md` when ANY of:

- User asks about __FILL__pattern
- User mentions __FILL__symbol
- User is doing __FILL__task

### When SKILL.md alone is sufficient

__FILL__list-of-question-categories-this-main-file-covers. Helps the agent avoid over-routing into references for questions answered above.

- __FILL__category
- __FILL__category
