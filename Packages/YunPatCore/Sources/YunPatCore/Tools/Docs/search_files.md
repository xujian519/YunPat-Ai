---
name: search_files
description: Searches file contents using ripgrep-style regex matching. Use to find symbol references, string occurrences, or patterns across a codebase.
version: 1.0.0
author: YunPat-AI Team
---

# search_files

## When to Use

- You need to find where a symbol, string, or pattern appears in the codebase.
- You want to locate all call sites of a function or uses of a type.
- You need to search for error messages, log strings, or configuration keys.

## Typical Workflow

1. Craft a regex pattern that matches your target.
2. Invoke `search_files` with the required `pattern` and an optional `path`.
3. Parse the returned matches with file paths, line numbers, and context.

## Parameters

| Parameter | Type   | Required | Default | Description                                  |
| --------- | ------ | -------- | ------- | -------------------------------------------- |
| `pattern` | string | yes      | —       | Regex pattern (ripgrep/RE2 syntax).           |
| `path`    | string | no       | cwd     | File or directory to search within.           |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "matches": [ { "file": "src/main.swift", "line": 42, "content": "let x = foo()" } ] } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "INVALID_ARGS", "message": "Pattern is not valid regex.", "hint": "Check regex syntax and escape special characters." } }
```

## Error Codes

| Code               | Meaning                  | Recovery                           |
| ------------------ | ------------------------ | ---------------------------------- |
| `INVALID_ARGS`     | Invalid regex pattern    | Fix the pattern; escape literals.  |
| `NOT_FOUND`        | Search path not found    | Verify the path exists.            |
| `TIMEOUT`          | Search took too long     | Narrow the path or simplify regex.  |

## Tips

- Use `\b` word boundaries to avoid partial matches (e.g. `\blog\b` not `log`).
- Escape regex metacharacters (`+`, `*`, `(`, `)`) when searching literal text.
- Narrow the `path` parameter for faster results.

## Known Limitations

- Binary files are skipped automatically.
- Results may be truncated for very large matches; use `list_files` + `read_file` for full context.
