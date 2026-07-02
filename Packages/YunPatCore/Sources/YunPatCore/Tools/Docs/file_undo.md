---
name: file_undo
description: Undo file operations (write_file, edit_file) within the current session. Supports undo by operation ID, by file path, or last N operations.
version: 1.0.0
author: YunPat-AI Team
---

# file_undo

## When to Use

- Reverting a mistaken write_file or edit_file immediately after invocation
- Undoing all changes to a specific file path via the `path` parameter
- Rolling back the last N file operations in FIFO order via `count`
- Recovery from accidental overwrites — relies on before-content captured by FileOperationLog

## Typical Workflow

1. Optionally call file_operation_history to inspect recent operations
2. Decide scope: by `operation_id` (surgical), by `path` (targeted), or by `count` (blanket)
3. Invoke file_undo with the chosen parameter
4. Verify the undone file(s) match your expectation; re-invoke if you need to step further back

## Parameters

| Parameter      | Type   | Required | Default | Description                                          |
| -------------- | ------ | -------- | ------- | ---------------------------------------------------- |
| `operation_id` | string | no       | —       | UUID of the operation to undo; most precise mode     |
| `path`         | string | no       | —       | Undo ALL undoable operations on this file path       |
| `count`        | int    | no       | `1`     | Undo the last N undoable operations (recent first)   |

At most one mode is active: `operation_id` > `path` > `count`.

## Return Value

Success (`ok: true`):

```
✅ 已撤销: `src/config.json` (write)
✅ 已撤销: `src/utils.ts` (edit)
```

Failure (`ok: false`):

```
Error: 此操作不可撤销（无原始内容）
```

## Error Codes

| Code               | Meaning                               | Recovery                                        |
| ------------------ | ------------------------------------- | ----------------------------------------------- |
| `INVALID_ARGS`     | No valid undo target provided         | Provide at least one of operation_id, path, or count |
| `NOT_UNDOABLE`     | Operation lacks before-content (e.g., new file, shell mutation) | Cannot revert; operation had nothing to restore |
| `IO_ERROR`         | Disk write failed during restoration  | Check file permissions and disk space; retry    |

## Tips

- `operation_id` is the most surgical — use it when you know the exact op from file_operation_history
- `path` is best for "undo everything I just did to that file"
- `count` is the quick escape hatch: undo recent mistakes without looking up IDs
- Operations become non-undoable after a successful undo (canUndo flips to false)
- Shell mutations (mv/cp/rm/mkdir) are not tracked by FileOperationLog; use read+write to fix those

## Known Limitations

- Only write_file and edit_file are logged with before-content; shell-based file changes are not revertible via this tool
- Undo is session-scoped — closing the session clears the operation log permanently
- `count` parameter treats the operation log as LIFO within its filtered set (most recent first)
