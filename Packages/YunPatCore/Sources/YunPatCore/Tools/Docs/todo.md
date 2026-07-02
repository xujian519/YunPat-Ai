---
name: todo
description: Write or replace a task checklist during an agent workflow. Each invocation replaces the entire list. Use Markdown format with `- [ ]` for pending and `- [x]` for completed items.
version: 1.0.0
author: YunPat-AI Team
---

# todo

## When to Use

- Breaking a complex patent drafting task into sequential checkpoints (claims → description → drawings → abstract)
- Tracking OA response sub-tasks (parse → compare → draft response → review)
- Recording progress through a multi-source patent search
- Keeping the user informed of what the agent has done and what remains

## Typical Workflow

1. After receiving a multi-step request, plan the steps and write them as a checklist.
2. As each step completes, re-invoke `todo` with updated `- [x]` markers for finished items.
3. The user can inspect the checklist in the UI (ChecklistView) at any time.

## Parameters

| Parameter  | Type   | Required | Default | Description                                |
| ---------- | ------ | -------- | ------- | ------------------------------------------ |
| `markdown` | string | yes      | —       | Full checklist in Markdown. Each call replaces the previous checklist entirely. |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "message": "✅ 任务清单已更新:\n\n<the checklist>" } }
```

## Error Codes

| Code           | Meaning                  | Recovery                        |
| -------------- | ------------------------ | ------------------------------- |
| `INVALID_ARGS` | `markdown` is empty      | Provide a non-empty checklist   |

## Tips

- Use 3–7 items. Too many items overwhelm; too few provide no structure.
- Start every item with a verb: "提取权利要求特征", "对比 D1 与权1", "生成 OA 答复稿".
- Only mark an item `[x]` when it is truly finished and verified — not when it's "almost done".
- If a step reveals new sub-tasks, update the checklist rather than creating a parallel one.

## Known Limitations

- The checklist is session-scoped. It does not persist across application restarts.
- There is no append mode — every call replaces the full list. Keep a local copy of the old list if you need to merge.
