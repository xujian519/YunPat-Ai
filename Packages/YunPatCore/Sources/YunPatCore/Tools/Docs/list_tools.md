---
name: list_tools
description: Returns a catalog of all available tools with their names, descriptions, and parameter schemas. A meta-tool for tool discovery.
version: 1.0.0
author: YunPat-AI Team
---

# list_tools

## When to Use

- You are unsure which tools are available in the current session.
- You need to discover tool capabilities before invoking them.
- You want to verify a tool name or parameter signature.

## Typical Workflow

1. Invoke `list_tools` with no parameters.
2. Inspect the returned catalog to find the right tool.
3. Invoke the selected tool with the correct parameters.

## Parameters

No parameters.

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "tools": [ { "name": "read_file", "description": "Reads a file.", "parameters": { "path": "string" } } ] } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "INTERNAL", "message": "Failed to enumerate tools.", "hint": "Retry once; if persistent, report the issue." } }
```

## Error Codes

| Code        | Meaning                     | Recovery                    |
| ----------- | --------------------------- | --------------------------- |
| `INTERNAL`  | Tool registry unavailable   | Retry once, then escalate.  |

## Tips

- Call this once at the start of a session to build a mental model of available tools.
- Use tool names from the response directly — they are canonical.
- Pair with `search_files` on tool source code if you need deeper implementation detail.

## Known Limitations

- Returns only tool metadata, not usage guides (see per-tool docs in this directory).
- Tool availability may differ across sessions or environments.
