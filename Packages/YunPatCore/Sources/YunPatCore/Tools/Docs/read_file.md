---
name: read_file
description: Reads file content with line range support, or lists directory contents.
version: 1.0.0
author: YunPat-AI Team
---

# read_file

## When to Use

- Read a known file path to inspect its content.
- Peek at a directory to discover files before reading.
- Read only a portion of a large file via line range selectors.

## Typical Workflow

1. If unsure about file location, call `list_files` or `search_files` first.
2. Invoke `read_file` with the path; for directories it returns a listing, for files the content.
3. For large files, append `:start-end` to the path to read only the needed slice.

## Parameters

| Parameter   | Type   | Required | Default | Description                                              |
| ----------- | ------ | -------- | ------- | -------------------------------------------------------- |
| `path`      | string | yes      | —       | File or directory path. Supports `:start-end` range.     |
| `file_path` | string | no       | —       | Alias for `path`. Use one or the other.                   |

Line range: `path/to/file.swift:50-200` reads lines 50–200 inclusive. `:50-` reads to end.

## Return Envelope

Success (`ok: true`):
```json
{ "ok": true, "data": { "content": "<text or listing>", "path": "<resolved>" } }
```

Failure (`ok: false`):
```json
{ "ok": false, "error": { "code": "ERROR_CODE", "message": "...", "hint": "..." } }
```

## Error Codes

| Code          | Meaning                          | Recovery                                          |
| ------------- | -------------------------------- | ------------------------------------------------- |
| `INVALID_ARGS`| Missing or malformed `path`      | Supply a non-empty `path` or `file_path`          |
| `NOT_FOUND`   | Path does not exist              | Verify spelling; use `list_files` first            |
| `READ_ERROR`  | OS-level failure (perms, I/O)    | Check file permissions and disk state              |

## Tips

- Check a directory listing before reading files inside it.
- Use line ranges aggressively — never read a 2000-line file whole when you need lines 150–200.
- Prefer `read_file` over shelling out with `cat`/`head`/`tail` — it avoids escaping issues.

## Known Limitations

- Line ranges are inclusive on both ends; off-by-one errors can read an extra line.
- Directory listings are one level deep — not recursive.
