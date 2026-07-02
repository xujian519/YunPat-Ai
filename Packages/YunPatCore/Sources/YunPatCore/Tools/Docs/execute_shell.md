---
name: execute_shell
description: Execute a shell command. Requires user approval before running. Integrates with HooksService for pre/post-execution interception.
version: 1.0.0
author: YunPat-AI Team
---

# execute_shell

## When to Use

- Running a single binary or a short pipeline to gather facts (e.g., `git status`, `wc -l`, `diff`, `swift test --list`)
- Invoking project build tools, formatters, or linters where no higher-level tool exists
- Inspecting system state: environment variables, disk usage, process listings

## Typical Workflow

1. Construct the command — prefer a single binary call or a short (≤2 pipe stages) fact-computing pipeline.
2. Invoke the tool with `command`. The system routes it through HooksService pre-tool hooks; if no hook blocks it, the user sees an approval prompt.
3. Parse the response envelope. On success, `data.stdout` and `data.stderr` contain the output. On failure, inspect `error.code` and `error.hint`.

## Parameters

| Parameter  | Type   | Required | Default | Description                                      |
| ---------- | ------ | -------- | ------- | ------------------------------------------------ |
| `command`  | string | yes      | —       | The shell command to execute. Shown up to 100 characters in approval previews. |

> ⚠️ 以下参数尚未实现（计划中）：
> - `cwd` (string) — 工作目录，默认 projectFolder 或当前目录
> - `timeout` (number, 默认 `30`) — 超时秒数

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "stdout": "<output>", "stderr": "", "exitCode": 0 } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "PERMISSION_DENIED", "message": "User denied execution.", "hint": "Explain why the command is necessary and try again." } }
```

## Error Codes

| Code               | Meaning                                          | Recovery                                                 |
| ------------------ | ------------------------------------------------ | -------------------------------------------------------- |
| `INVALID_ARGS`     | `command` is empty or missing                    | Provide a non-empty command string and retry             |
| `PERMISSION_DENIED`| User denied the approval prompt or a hook blocked execution | Clarify intent and re-request; respect a second denial   |
| `INTERNAL`         | Shell process failed to launch or returned unexpectedly | Verify the command is valid and the binary is on `PATH`  |

## Tips

- Never run destructive commands (`rm -rf`, `git push --force`, `shutdown`) without explicit user confirmation — the approval prompt is your last chance to justify the command.
- Prefer a single binary call over complex pipelines. Multi-line scripts belong in a file, not inline.
- Use dry-run or preview flags (`--dry-run`, `-n`, `--check`) when the tool supports them to let the user preview effects before the real run.
- Quote arguments carefully. Use single-quotes around literals; avoid shell injection from user-provided strings.

## Known Limitations

- The command preview truncates at 100 characters. Long commands still execute fully but the user only sees the first 100 chars in the approval dialog.
- Shell state is not preserved across invocations — each call runs in an independent subprocess. Use a script file for multi-step workflows.
