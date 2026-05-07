---
name: <skill-name>
description: Use for <one-line trigger>. Covers <list of concrete symbols — class names, table names, SPI interfaces, verbs, named queries — that users would type when they need this skill>. Verified against Keycloak <X.Y.Z>.
---

# <Skill Title> — Reference Skill

<One-paragraph statement of when to use the skill and what's in scope. Example pattern: "Expert reference for X. The skill is structured so this file alone covers most needs (~80% of questions); read the reference files for deep dives.">

Verified against Keycloak <X.Y.Z>.

---

## Source Code Layout

<Table of paths in the Keycloak source tree relevant to this skill, and what's in each. Keep paths relative to the Keycloak repo root.>

| Path | What's there |
|---|---|
| `<path>` | <one line> |

---

## Mental Model

<Numbered list of 8–15 invariants. These are the things a reader must hold in their head before any specific table or method makes sense. Lead with the most load-bearing concept.>

1. <invariant>
2. <invariant>
...

---

## <Schema / API> at a Glance

<Diagram, table, or reference card. For schema skills, an ASCII tree of related tables. For SPI skills, a diagram of the provider interface and adapter relationships.>

---

## Patterns

<Recurring shapes in the area this skill covers. Each pattern gets a name, a one-line definition, and 2–4 concrete examples from real Keycloak code.>

### Pattern 1: <name>
- <definition>
- Examples: <real symbols>

### Pattern 2: <name>
...

---

## Common Gotchas

<Numbered list of things that trip people up. Each gotcha:
- Leads with the failure mode.
- Names the symbol or column or version where it bites.
- Ends with the fix or the correct mental model.>

### 1. <Gotcha title>
<Description, then fix.>

### 2. <Gotcha title>
...

---

## Cheat Sheet

<Two-column table: "If you need X" → "Look at Y". Exhaustive enough that a reader can answer most lookup questions without reading the rest of the skill.>

| If you need... | Look at... |
|---|---|
| <need> | <where> |

---

## Common <JPQL / API / Code> Patterns

<Short, copy-pastable snippets for the most frequent operations. Each snippet:
- Has one line of context above it.
- Uses real Keycloak class and method names.
- Shows the WRONG way alongside the right way when there's a common trap.>

### <Snippet title>
```java
// snippet
```

---

## Auto-Routing — read references PROACTIVELY without being asked

<For each `references/*.md` file, list the question patterns that should trigger reading it. Be explicit; the agent should not need to ask permission.>

### Read `references/<file>.md` when ANY of:

- User asks about <pattern>
- User mentions <symbol>
- User is doing <task>

### When SKILL.md alone is sufficient

<List the question categories this main file covers. Helps the agent avoid over-routing into references for questions answered above.>

- <category>
- <category>
