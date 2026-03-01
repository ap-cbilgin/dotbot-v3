---
name: Kickstart Interview (Multi-Repo)
description: Override — auto-resolve initiative from Atlassian instead of multi-round interview
version: 1.0
---

# Kickstart: Auto-Resolve from Atlassian

You are initializing a multi-repo initiative. Instead of a multi-round interview, you will auto-resolve the initiative context from Atlassian (Jira + Confluence) using the user's prompt.

## Context Provided

- **User's prompt**: A short description containing a Jira key (e.g., "BS-9817 Pakistan E-Invoicing")
- **Briefing files**: Any attached reference materials

## Your Task

### Step 1: Parse the Jira Key

Extract the Jira key from the user's prompt using the pattern `[A-Z]{2,10}-\d+`.

If no Jira key is found:
- Use the prompt text as the initiative name
- Skip Atlassian resolution
- Populate `initiative.md` from prompt text + uploaded files
- Mark unresolved fields with `<!-- UNRESOLVED: field_name -->`

### Step 2: Resolve from Jira

Use the Atlassian MCP server to fetch initiative context:

**2a. Get the main issue:**
```
mcp__atlassian__getJiraIssue({ issueIdOrKey: "{JIRA_KEY}" })
```

Extract:
- `summary` → initiative name
- `description` → business objective
- `status` → current status
- `parent` → parent/programme key
- `components` → affected systems
- `labels` → initiative labels
- `assignee` → primary assignee
- `created` / `updated` → dates
- Custom fields → team members (BA, Architect, PM, SDM)
- `issuelinks` → related tickets

**2b. Get child issues:**
```
mcp__atlassian__searchJiraIssuesUsingJql({
  jql: "parent = {JIRA_KEY}",
  limit: 50
})
```

**2c. Get linked issues:**
```
mcp__atlassian__searchJiraIssuesUsingJql({
  jql: "issuekey in linkedIssues({JIRA_KEY})",
  limit: 50
})
```

**2d. Resolve parent programme:**

If the main issue has a parent key:
```
mcp__atlassian__getJiraIssue({ issueIdOrKey: "{PARENT_KEY}" })
```

Then search for sibling initiatives:
```
mcp__atlassian__searchJiraIssuesUsingJql({
  jql: "parent = {PARENT_KEY}",
  limit: 20
})
```

From siblings, identify the best **reference implementation** candidate:
- Same programme, completed or in-progress status, similar components
- If the user's prompt mentions a reference, use that instead

**2e. Search Confluence:**
```
mcp__atlassian__searchConfluenceUsingCql({
  cql: "text ~ \"{JIRA_KEY}\" OR text ~ \"{INITIATIVE_NAME}\"",
  limit: 20
})
```

Read up to `max_pages_to_read` (from settings, default 10) key pages:
```
mcp__atlassian__getConfluencePage({ pageId: "{PAGE_ID}" })
```

Extract page title, space, and a ~500 character excerpt from each page.

### Step 3: Read Settings

Load profile settings for organisation-specific values:
```
read_files({ files: [{ path: ".bot/defaults/settings.default.json" }] })
```

Also check `.env.local` for ADO org URL and Atlassian cloud ID (these are loaded into process environment by profile-init.ps1).

### Step 4: Write `initiative.md`

Write the populated template to `.bot/workspace/product/briefing/initiative.md`:

```markdown
# Initiative: {INITIATIVE_NAME}

## Metadata

| Field | Value |
|-------|-------|
| Jira Key | {JIRA_KEY} |
| Summary | {SUMMARY} |
| Status | {STATUS} |
| Parent | {PARENT_KEY} -- {PARENT_SUMMARY} |
| Strategic Programme | {PROGRAMME_NAME} |
| Created | {CREATED_DATE} |
| Updated | {UPDATED_DATE} |
| URL | {JIRA_URL} |

## Team

| Role | Name | Jira Account |
|------|------|--------------|
| Assignee | {ASSIGNEE} | {ASSIGNEE_ID} |
| Business Analyst | {BA} | {BA_ID} |
| Architect | {ARCHITECT} | {ARCHITECT_ID} |
| Project Manager | {PM} | {PM_ID} |
| SDM | {SDM} | {SDM_ID} |

> Team members resolved from Jira assignee + custom fields. Unresolved roles left blank.

## Business Objective

{JIRA_DESCRIPTION}

## Components & Labels

- **Components**: {COMPONENTS_LIST}
- **Labels**: {LABELS_LIST}

## Child Issues

| Key | Summary | Status | Assignee | Type |
|-----|---------|--------|----------|------|
(populated from Step 2b)

## Linked Issues

| Key | Summary | Link Type | Status | Project |
|-----|---------|-----------|--------|---------|
(populated from Step 2c)

## Confluence Documentation

| Page Title | Page ID | Space | Excerpt |
|------------|---------|-------|---------|
(populated from Step 2e)

> Up to max_pages_to_read pages fetched. Excerpts are first ~500 chars of body.

## Programme Context

- **Parent Programme**: {PARENT_KEY} -- {PROGRAMME_NAME}
- **Sibling Initiatives**:

| Key | Summary | Status | Relevance |
|-----|---------|--------|-----------|
(populated from Step 2d)

## Reference Implementation

- **Recommended Reference**: {REFERENCE_KEY} -- {REFERENCE_NAME}
- **Rationale**: {REFERENCE_RATIONALE}

> Auto-selected from sibling initiatives based on: same programme, completed/in-progress status,
> similar components. User can override by mentioning a reference in their prompt.

## Organisation Settings

| Setting | Value |
|---------|-------|
| Azure DevOps Org | {ADO_ORG_URL} |
| ADO Projects | {ADO_PROJECTS} |
| Atlassian Cloud ID | {ATLASSIAN_CLOUD_ID} |
| Confluence Spaces | {CONFLUENCE_SPACES} |

> Populated from settings.default.json and .env.local.

## User-Provided Context

- **Original Prompt**: "{USER_PROMPT}"
- **Reference Hint**: {REFERENCE_HINT}
- **Uploaded Files**:
{UPLOADED_FILES_LIST}
```

For any field that could not be resolved, use `<!-- UNRESOLVED: field_name -->` as the value.

### Step 5: Write Completion Signal

Write `.bot/workspace/product/interview-summary.md`:

```markdown
# Interview Summary

Auto-resolved from Atlassian. See `briefing/initiative.md` for full context.

## Resolution Method
- **Source**: Atlassian MCP (Jira + Confluence)
- **Jira Key**: {JIRA_KEY}
- **Pages Read**: {N} Confluence pages
- **Child Issues**: {N} found
- **Linked Issues**: {N} found
- **Sibling Initiatives**: {N} found

## Unresolved Fields
{LIST_OF_UNRESOLVED_FIELDS_OR_NONE}

## MCP Errors (if any)
{LIST_OF_FAILED_MCP_CALLS_OR_NONE}
```

### Graceful Degradation

If Atlassian MCP is unavailable or returns errors:

1. Populate `initiative.md` from the user's prompt text + any uploaded files
2. Mark unresolved fields with `<!-- UNRESOLVED: field_name -->`
3. Log which MCP calls failed in `interview-summary.md`
4. Still write both files — the system can proceed with partial data

## Critical Rules

- Write **exactly two files**: `briefing/initiative.md` AND `interview-summary.md`
- Do NOT create any other files (no mission.md, no tech-stack.md, etc.)
- Do NOT use task management tools
- Do NOT conduct a multi-round interview — auto-resolve from Atlassian
- If the user's prompt is very detailed, extract what you can and note the rest for manual review
