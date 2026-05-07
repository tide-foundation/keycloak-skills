# keycloak-skills

Reference skills for AI coding agents working on Keycloak — schema, SPIs, extensions, deployment. Each skill is a self-contained markdown file that an agent loads into context on demand.

Built and maintained by the [Tide Foundation](https://tide.org).

## Skills

| Skill | Covers | Verified against |
|---|---|---|
| [keycloak-entities](./skills/keycloak-entities/SKILL.md) | JPA entities, schema, JPQL, Liquibase changelogs, ~90 tables, FK cascades, federated user tables, UMA Authorization Services | Keycloak 26.5.5 |

More skills planned: SPI development, Admin REST API, themes, deployment, testing, OIDC/SAML protocols, admin UI extension.

## Use with Claude Code

Clone and symlink each skill into your Claude Code skills directory:

```bash
git clone https://github.com/tide-foundation/keycloak-skills.git ~/keycloak-skills
mkdir -p ~/.claude/skills
ln -s ~/keycloak-skills/skills/keycloak-entities ~/.claude/skills/keycloak-entities
```

Claude Code picks up the skill on next launch and routes to it when your task matches the skill's `description`.

For project-scoped install (only available inside one repo):

```bash
mkdir -p .claude/skills
ln -s ~/keycloak-skills/skills/keycloak-entities .claude/skills/keycloak-entities
```

## Use with Claude.ai or the Claude API

Each `SKILL.md` is plain markdown. Paste the relevant `SKILL.md` (and any `references/*.md` its auto-routing points to) into your agent's system prompt.

## Use with Cursor / Codex / Aider / other AGENTS.md-aware tools

These tools have no native skill loader, but they read markdown context. Either:

- Copy the skill content into your tool's rules file (e.g. `.cursor/rules/keycloak-entities.md`), or
- Reference the file path in your prompt and let the tool read it on demand.

## Versioning

Each skill declares the exact Keycloak version it was verified against, in both its frontmatter `description` and its body. If you are running a different Keycloak version, treat the skill as advisory and re-verify against your own source — Keycloak's data model and SPIs change meaningfully across versions.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to add a new skill, and [AGENTS.md](./AGENTS.md) for the writing and verification rules. Skills must be verified against actual Keycloak source, not web docs.

A starter scaffold lives at [skills/\_template/SKILL.md](./skills/_template/SKILL.md).

## License

[MIT](./LICENSE).
