---
name: file_operation_history
description: View the session's file operation log — every write_file and edit_file invocation with timestamps, undo status, and content metadata.
version: 1.0.0
author: YunPat-AI Team
---

# file_operation_history

## When to Use

- Inspecting what file operations occurred so far in the current session
- Finding the `operation_id` needed to undo a specific operation via file_undo
- Auditing which files were modified, when, and by what kind of operation
- Determining whether an operation is still undoable (↩️ = yes, ➡️ = no)

## Typical Workflow

1. Call file_operation_history with no parameters to view the full log
2. Optionally filter to a single file via `path` to narrow the output
3. Note the `↩️` markers for undoable operations (those with captured before-content)
4. Copy the displayed UUID to use as `operation_id` in file_undo

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `path`    | string | no       | —       | Filter operations to those affecting this path |

## Return Value

Success (`ok: true`):

```
↩️ `src/main.ts` [edit](1234 chars)  14:32
↩️ `src/main.ts` [write](567 chars)  14:30
➡️ `src/new.ts` [write](89 chars)    14:28
```

Empty log:

```
尚无文件操作记录。
```

## Error Codes

| Code           | Meaning                     | Recovery                                        |
| -------------- | --------------------------- | ----------------------------------------------- |
| `INVALID_ARGS` | `path` is malformed (empty) | Provide a valid path string or omit the parameter |

## Tips

- Call before file_undo to confirm the operation's existence and undoable status
- `↩️` means the operation captured before-content and can be reverted; `➡️` means it cannot
- The `(N chars)` annotation shows the after-content size for write/edit operations
- Operations are listed in reverse chronological order (most recent first)
- The log is per-session — opening a new session starts with a clean slate

## Known Limitations

- Only write_file and edit_file operations are tracked; shell mutations are not shown
- Before-content is omitted from new-file writes (no prior content existed), rendering them non-undoable
- Operation IDs are session-scoped UUIDs — they are not persistent across sessions
- Timestamps use local short-time format only (HH:MM), not full date or timezone
