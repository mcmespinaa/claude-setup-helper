# {{PROJECT_NAME}}

> ICM Layer 0 — the **Map**. The first file Claude reads. Keep it short, current, and link outward; do not let it absorb content that belongs in a room (CONTEXT.md) or a reference file.

## What this is

{{ONE_LINE_DESCRIPTION}}

## Routing

| Task | Go to | Read |
|------|-------|------|
| {{TASK_1}} | {{DIR_1}} | {{ENTRY_FILE_1}} |
| {{TASK_2}} | {{DIR_2}} | {{ENTRY_FILE_2}} |

## Build / run commands

```bash
{{BUILD_COMMAND}}
```

## Conventions

- {{CONVENTION_1}}
- {{CONVENTION_2}}

## What to avoid

- {{ANTIPATTERN_1}}

## Structure

- `reference-*` / stable docs → factory material, read as constraints, do not regenerate per run.
- `*-YYYY-MM-DD` / output files → working artifacts, produced per run, never treated as current truth once stale.

_Maintained by: {{OWNER}}. Last updated: {{DATE}}._
