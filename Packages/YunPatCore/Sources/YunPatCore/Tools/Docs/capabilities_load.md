---
name: capabilities_load
description: Load a capability into the current session — the capability's tools become callable immediately.
version: 1.0.0
author: YunPat-AI Team
---

# capabilities_load

## When to Use

- Activating a capability discovered via `capabilities_discover`.
- Enabling a feature mid-session that was not loaded at session start.
- Dynamically extending the tool set based on user needs.

## Typical Workflow

1. Run `capabilities_discover` to find the target capability's exact `name`.
2. Call `capabilities_load` with that `name`.
3. The capability's tools are immediately dispatchable — use them in the next tool call.
4. **Schema snapshot freezes** until the next user turn; newly loaded tools won't appear in the model's tool schema until then.

## Parameters

| Parameter | Type   | Required | Default | Description |
| --------- | ------ | -------- | ------- | ----------- |
| `name`    | string | yes      | —       | Exact capability name from `capabilities_discover` results. Case-sensitive. |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "name": "desktop.shell", "displayName": "Shell Execution", "description": "Execute whitelisted shell commands", "source": "builtin", "permission": "perSession", "requiresNetwork": false, "typicalUseCases": ["script execution", "git operations"] } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "INVALID_ARGS", "message": "name field required", "hint": "Provide the exact capability name from capabilities_discover results." } }
```

## Error Codes

| Code           | Meaning                        | Recovery |
| -------------- | ------------------------------ | -------- |
| `INVALID_ARGS` | `name` parameter missing/empty | Supply the exact `name` from `capabilities_discover` results. |
| `NOT_FOUND`    | No capability matches name     | Run `capabilities_discover` to confirm the name, then retry. |
| `INTERNAL`     | Registry or buffer failure     | Retry; if persistent, restart the session. |

## Tips

- **Always pair with `capabilities_discover`.** Never guess a capability name — discover it first.
- **Loaded tools are callable immediately** even though the model's tool schema won't include them until the next user turn. Dispatch them by name in the same tool-call batch.
- Loading is idempotent — loading an already-active capability is safe and returns the same details.
- Check `requiresNetwork` in the returned details before relying on a network-dependent capability in an offline workflow.

## Known Limitations

- **Schema snapshot freeze:** newly loaded tools do not appear in the model's tool schema until the **next user turn**. The model must dispatch them by name without schema prompting within the current turn.
- Loading a capability does not auto-load its transitive dependencies; each dependency must be loaded separately.
- Capability load state is session-scoped and does not persist across session restarts.
