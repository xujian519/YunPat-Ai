---
name: write_file
description: Create or overwrite files with UTF-8 content. Integrates with FileOperationLog for undo.
version: 1.0.0
author: YunPat-AI Team
---

# write_file

## When to Use

- Creating a new file or overwriting an entire existing file
- Writing generated output, configuration, or scaffolded code
- Restoring a file to a known-good state (combined with undo)

## Typical Workflow

1. Call with `dry_run: true` to preview the outcome (path, byte size)
2. If correct, call again without `dry_run` to commit
3. Use `file_undo` to revert if the result is wrong

## Parameters

| Parameter  | Type   | Required | Default | Description                                    |
| ---------- | ------ | -------- | ------- | ---------------------------------------------- |
| `path`     | string | yes      | —       | Absolute or project-relative file path         |
| `content`  | string | yes      | —       | Full file content in UTF-8                     |
| `dry_run`  | bool   | no       | `false` | Preview only; returns path + size, no write    |

## Return Value

Success:

```json
{ "ok": true, "data": { "path": "/abs/path/to/file", "size": 1234 } }
```

Dry-run adds `"dryRun": true` to the data object. No write occurs and no log entry is created.

Failure:

```json
{ "ok": false, "error": { "code": "WRITE_ERROR", "message": "Permission denied", "hint": "Check file permissions and parent directory existence" } }
```

## Error Codes

| Code           | Meaning                        | Recovery                                            |
| -------------- | ------------------------------ | --------------------------------------------------- |
| `INVALID_ARGS` | `path` is missing or empty     | Provide a valid path                                |
| `WRITE_ERROR`  | I/O failure (permissions, disk full, missing parent dir) | Check permissions and directory; retry |

## Tips

- Always `dry_run: true` first to validate before committing changes
- Use `file_undo` to revert the last write_file or edit_file on a given path
- Prefer `edit_file` for targeted, line-level edits — write_file replaces the whole file
- Writes are atomic; partial-write corruption is avoided
- Before-content is auto-captured for undo; dry_run invocations are NOT logged

## Known Limitations

- UTF-8 only; binary encodings are unsupported
- Does not auto-create missing parent directories
