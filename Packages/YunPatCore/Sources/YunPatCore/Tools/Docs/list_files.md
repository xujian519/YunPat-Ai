---
name: list_files
description: Lists files matching a glob pattern within a directory tree. Use to discover project structure, find files by extension, or verify file existence before reading.
version: 1.0.0
author: YunPat-AI Team
---

# list_files

## When to Use

- You need to discover what files exist in a directory before reading them.
- You want to find all files matching a pattern (e.g. `*.swift`, `**/Tests/**`).
- You need to verify a file path exists without triggering a read error.

## Typical Workflow

1. Determine the glob pattern and optional base path.
2. Invoke `list_files` with `pattern` and `path`.
3. Iterate the returned file list; read only the files you need.

## Parameters

| Parameter | Type   | Required | Default | Description                                   |
| --------- | ------ | -------- | ------- | --------------------------------------------- |
| `pattern` | string | no       | `"*"`   | Glob pattern (supports `*`, `**`, `?`, `[]`). |
| `path`    | string | no       | cwd     | Base directory to search from.                |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "files": ["src/main.swift", "src/utils.swift"] } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "NOT_FOUND", "message": "Directory does not exist.", "hint": "Check the path parameter." } }
```

## Error Codes

| Code               | Meaning                  | Recovery                        |
| ------------------ | ------------------------ | ------------------------------- |
| `INVALID_ARGS`     | Invalid glob pattern     | Fix the pattern syntax.         |
| `NOT_FOUND`        | Path does not exist      | Verify the base directory.      |
| `PERMISSION_DENIED`| Cannot read directory    | Check file system permissions.  |

## Tips

- Use `**` for recursive matching (e.g. `**/*.swift`).
- Always list before reading — never guess file paths.
- Narrow the path to reduce result noise.

## Known Limitations

- Does not follow symlinks by default.
- Results are unsorted; sort client-side if order matters.
