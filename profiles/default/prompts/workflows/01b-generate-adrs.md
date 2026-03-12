---
name: Generate ADRs from Interview
description: Phase 1b — extract architectural decisions from the interview and product documents into ADRs
version: 1.0
---

# Generate Architecture Decision Records

You are a technical architect reviewing the outputs of the kickstart interview and product planning phase. Your job is to extract genuine architectural decisions and record them as Architecture Decision Records (ADRs) using the `adr_create` MCP tool.

## Session Context

- **Session ID:** {{SESSION_ID}}

## Instructions

### Step 1: Read Source Documents

Read all available source material:

```
Read({ file_path: ".bot/workspace/product/interview-summary.md" })
Read({ file_path: ".bot/workspace/product/mission.md" })
Read({ file_path: ".bot/workspace/product/tech-stack.md" })
Read({ file_path: ".bot/workspace/product/entity-model.md" })
```

### Step 2: Identify ADR-Worthy Decisions

Scan the source documents for decisions that meet ALL of these criteria:

**Include:**
- Scope boundaries (what is explicitly in/out of scope and why)
- Platform or technology choices where alternatives existed
- Migration strategy decisions (e.g. like-for-like vs. rework)
- Integration decisions (which systems are included/deferred)
- Domain model choices that have architectural consequences
- Any decision where the interview reveals a rejected alternative

**Exclude:**
- Clarifications that just confirmed an obvious default
- Questions the user skipped
- Implementation details that belong in task plans
- Generic principles without a real trade-off

Aim for **3–10 ADRs** from a typical kickstart. Fewer is better than padding with non-decisions.

### Step 3: Create ADRs

For each identified decision, call `adr_create`. Set `source` to `kickstart-interview` and `status` to `accepted` (these decisions are already ratified by the interview process).

**Field guidance:**

- **title**: Short, noun-phrase title of the decision (not a question). E.g. "Scope to Titan Platform Only", not "Should we use Titan?"
- **context**: Why this decision needed to be made — the forces at play. Pull from the interview interpretation sections.
- **decision**: The specific choice made. Be concrete.
- **rationale**: Why this option over alternatives. Include the interview answer and its interpretation.
- **consequences**: Trade-offs, constraints this creates for future tasks, risks.
- **alternatives_considered**: What was evaluated and rejected, with reasons. Draw from interview options that were not selected.
- **related_adrs**: Link ADRs that are logically connected (fill in after creating all of them).

**Example call:**

```javascript
mcp__dotbot__adr_create({
  title: "Scope Implementation to Titan Platform Only",
  context: "The project could target both Titan (the core billing platform) and FinApps (the financial applications layer). Including both would increase scope and risk significantly.",
  decision: "All implementation will target Titan only. FinApps integration is explicitly deferred.",
  rationale: "The interview confirmed that the immediate goal is standardisation within Titan. FinApps integration can follow once the Titan pattern is stable. This reduces blast radius and aligns with the like-for-like migration principle.",
  consequences: "FinApps will continue to use the existing approach until a follow-on project. Tasks must not introduce FinApps dependencies. Acceptance criteria should validate Titan behaviour only.",
  alternatives_considered: "Option B (both Titan and FinApps simultaneously) was rejected due to increased complexity and risk of breaking FinApps billing during the migration.",
  status: "accepted",
  source: "kickstart-interview"
})
```

### Step 4: Link Related ADRs

After creating all ADRs, identify pairs that are logically related (e.g. "scope to Titan" relates to "defer FinApps integration"). Use `adr_update` to set `related_adrs` on each.

```javascript
mcp__dotbot__adr_update({
  adr_id: "adr-001",
  related_adrs: ["adr-002", "adr-003"]
})
```

### Step 5: Report

Output a summary:
- Number of ADRs created
- List of ADR IDs and titles
- Any decisions you chose NOT to record as ADRs and why

---

## MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp__dotbot__adr_create` | Create a new ADR |
| `mcp__dotbot__adr_update` | Update an existing ADR (e.g. to add related_adrs) |
| `mcp__dotbot__adr_list` | List created ADRs to review |

---

## Anti-Patterns

### ❌ Recording non-decisions
**Don't:** Create an ADR for "Use standard naming conventions"
**Do:** Only record decisions with real trade-offs and rejected alternatives

### ❌ Duplicating product document content
**Don't:** Repeat everything in mission.md as ADRs
**Do:** ADRs explain the *why behind* the decisions in mission.md

### ❌ Vague decisions
**Don't:** "Decided to use a good architecture"
**Do:** "Use repository pattern for all data access (rejected active record due to testability concerns)"

### ❌ Over-generating
**Don't:** Create 20+ ADRs from a simple project
**Do:** Be selective — only genuine architectural decisions with future impact
