# Design: `using-multica` Skill

**Date:** 2026-05-15
**Status:** Approved

## Overview

A skill document that teaches orchestrator personas (Team Lead, Tech Lead, PM, Business Analyst, Software Architect) how to create, assign, and manage issues in the Multica platform. The skill combines judgment guidance (when and how to delegate) with CLI mechanics (the exact commands to do it).

The functionality already exists in the `multica` CLI (`multica issue` subcommand). No new API integration is needed — the skill is a reference document that makes the CLI accessible and effective for AI personas.

## Scope

**In scope:**
- Judgment guidance: when to create an issue vs. handle inline
- Issue scoping: how to write a well-formed title, description, and acceptance criteria
- Agent selection: how to discover available agents and match work to speciality
- Delegation depth: orchestrators delegate, they do not self-assign
- CLI quick-reference: the commands an orchestrator actually needs, with pitfall notes

**Out of scope:**
- Coding/specialist agents (Developer, QA Engineer, Researcher, Code Explorer, etc.) — they execute tasks, not assign them
- Daemon internals, task claiming, runtime management
- Admin operations (creating/updating agents, managing workspaces)

## Architecture

### Single file: `using-multica/SKILL.md`

Consistent with existing skill conventions (`using-openbao/SKILL.md`). No separate roster file — agent discovery is dynamic via `multica agent list --output json`.

**Document structure (top to bottom):**
1. Frontmatter (name, description, trigger)
2. When to use / when NOT to use
3. Judgment guidance (4 rules)
4. CLI quick-reference table
5. Pitfalls

### Placement

The skill file lives at `skills/using-multica/SKILL.md` in the multica-agent-image repo (alongside the Dockerfile), consistent with how other local skills are shipped with the agent image. It is installed only on orchestrator personas via `agentSetup.skills` in `values.yaml` — not on coding agents.

## Section Designs

### Section 1 — Identity & triggers

- **Name:** `using-multica`
- **Trigger:** any time an orchestrator persona needs to break down work and delegate it — creating issues, assigning agents, monitoring progress, or updating status
- **Excluded:** coding/specialist agents execute tasks; they do not use this skill
- **Safety rule:** reads (list, get, search) are free; writes (create, assign, status change) require a clear delegation decision first — never create issues speculatively

### Section 2 — Judgment guidance

Four rules presented before the CLI commands:

1. **Create vs. handle inline** — create an issue when: the work requires a specialist agent, it can run concurrently, it has clear acceptance criteria, or it will take more than a few minutes. Skip the issue when: it's a clarifying question, a lookup, or something resolvable in a single response.

2. **Scoping a well-formed issue** — one agent, one concern. Title should complete "Done when…". Description must include: what to do, why it matters, constraints/context the agent needs, and explicit acceptance criteria. Vague issues produce vague work.

3. **Picking the right agent** — run `multica agent list --output json` once at session start. Match by speciality. Don't assign backend work to a QA Engineer. Prefer the specialized agent over the generalist when both could apply.

4. **Delegation depth** — orchestrators create issues for other agents; they do not create issues to assign back to themselves. If you'd be executing it, just do it.

### Section 3 — CLI quick-reference

Commands scoped to what an orchestrator actually needs:

| Task | Command |
|---|---|
| Discover available agents | `multica agent list --output json` |
| Create and assign an issue | `multica issue create --title "..." --assignee "Agent Name"` |
| Add a multi-line description | `--description-stdin` with heredoc, or `--description-file path` |
| Assign/reassign after creation | `multica issue assign <id> --to "Agent Name"` |
| Change status | `multica issue status <id> <status>` |
| Add a progress comment | `multica issue comment add <id> --content "..."` |
| Check what's running | `multica issue list --status in_progress --output json` |
| Find an existing issue | `multica issue search "query"` |
| View execution history | `multica issue runs <id>` |
| Re-trigger a stuck issue | `multica issue rerun <id>` |

**Pitfalls:**
- `--assignee` fuzzy-matches by name; `--assignee-id` uses UUID — prefer `--assignee` with the exact name from `agent list`
- Duplicate-detection guard rejects re-creation of an identical active issue; pass `--allow-duplicate` only when intentionally re-creating
- Valid statuses: `backlog`, `todo`, `in_progress`, `in_review`, `done`, `blocked`, `cancelled`
- `--description` inline decodes `\n` as newlines; use `--description-stdin` for multi-line bodies

## Deployment

The skill is referenced in `agentSetup.skills` in `values.yaml`. It should be assigned only to orchestrator personas:
- Team Lead
- Tech Lead
- Product Manager
- Business Analyst
- Software Architect

It should NOT be assigned to:
- Developer, QA Engineer, Researcher, Code Explorer, Code Reviewer, Technical Writer, etc.
