---
name: <tool_name>
description: <one-line summary of what this tool does and when to use it>
version: 1.0.0
author: YunPat-AI Team
---

# <tool_name>

## When to Use

- <trigger scenario 1>
- <trigger scenario 2>
- <trigger scenario 3>

## Typical Workflow

1. <step 1 — prepare inputs>
2. <step 2 — invoke the tool>
3. <step 3 — handle the response>

## Parameters

| Parameter  | Type   | Required | Default | Description                      |
| ---------- | ------ | -------- | ------- | -------------------------------- |
| `<param1>` | string | yes      | —       | <what this parameter controls>   |
| `<param2>` | int    | no       | `10`    | <what this parameter controls>   |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "<key>": "<value>" } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "ERROR_CODE", "message": "Human-readable message.", "hint": "Suggested fix." } }
```

## Error Codes

| Code               | Meaning                        | Recovery                                      |
| ------------------ | ------------------------------ | --------------------------------------------- |
| `INVALID_PARAMS`   | Missing or malformed parameter | Check required fields and retry               |
| `<SECOND_CODE>`    | <what triggers it>             | <suggested action>                            |

## Tips

- <tip 1>
- <tip 2>

## Known Limitations

- <limitation 1 — scope, rate-limit, data freshness, etc.>
