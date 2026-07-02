---
name: capabilities_discover
description: Search enabled capabilities by keyword — use before capabilities_load to find the exact capability name.
version: 1.0.0
author: YunPat-AI Team
---

# capabilities_discover

## When to Use

- Exploring which capabilities are currently enabled in the session.
- Finding the exact capability `name` required by `capabilities_load`.
- Checking whether a specific feature (e.g. "shell", "file", "knowledge") is available.

## Typical Workflow

1. Call with a broad keyword (or omit `query` to list all capabilities).
2. Scan the returned matches — each entry shows display name, internal name, and description.
3. Copy the exact `name` value (e.g. `desktop.shell`) for use with `capabilities_load`.

## Parameters

| Parameter | Type   | Required | Default | Description |
| --------- | ------ | -------- | ------- | ----------- |
| `query`   | string | no       | `""`    | Case-insensitive substring matched against name, displayName, and description. Empty → returns all capabilities. |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "matches": [{ "name": "desktop.shell", "displayName": "Shell Execution", "description": "Execute whitelisted shell commands", "requiresNetwork": false, "source": "builtin" }] } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "INTERNAL", "message": "Registry unavailable.", "hint": "Retry after a short delay." } }
```

## Error Codes

| Code       | Meaning                          | Recovery |
| ---------- | -------------------------------- | -------- |
| `INTERNAL` | Capability registry inaccessible | Retry; if persistent, restart the session. |

## Tips

- **Search broadly first.** An empty `query` returns every enabled capability — then narrow with more specific keywords.
- **Use the exact `name` field** from results, not `displayName`, when calling `capabilities_load`. The system matches by `name` exactly.
- Entries marked `requiresNetwork: true` may incur latency — check before loading in offline contexts. The `🌐` indicator in textual output also signals this.

## Known Limitations

- Results reflect the capability set at call time; capabilities loaded mid-session appear after the next user turn.
- The raw text response uses Chinese labels (`【匹配的能力】`); prefer the structured JSON envelope described above.
