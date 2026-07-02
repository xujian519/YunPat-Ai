---
name: complete
description: End the current task and deliver a verified summary. The summary must be ≥30 characters of meaningful prose describing what was actually done and how it was verified — placeholders like 'done', 'ok', '已完成' are rejected.
version: 1.0.0
author: YunPat-AI Team
---

# complete

## When to Use

- The agent has finished all requested work and verified the output
- The patent draft / OA response / infringement analysis is complete and self-consistent
- The user explicitly asked to stop or wrap up
- The agent hits an unrecoverable dead-end and must report the result anyway

## Typical Workflow

1. Verify all checklist items in `todo` are marked `[x]`.
2. Review the final output — re-read the draft, check logic, confirm no placeholder text remains.
3. Call `complete` with a detailed summary that explains **what was produced** and **how it was validated**.

## Parameters

| Parameter | Type   | Required | Default | Description                                                    |
| --------- | ------ | -------- | ------- | -------------------------------------------------------------- |
| `summary` | string | yes      | —       | ≥30 characters of meaningful prose. Must describe work done and verification steps. |

## Return Value

The tool triggers `taskComplete` in the Loop engine, which terminates the current iteration and returns control to the user.

## Error Codes

| Code           | Meaning                                 | Recovery                                                 |
| -------------- | --------------------------------------- | -------------------------------------------------------- |
| `INVALID_ARGS` | `summary` fails validation (too short, or is a placeholder like "done" / "ok" / "已完成") | Write a real summary describing what was accomplished |

## Tips

- A good summary answers three questions: What was done? How was it verified? What should the user review?
- For patent drafts: "已根据交底书起草权利要求1-10，采用其特征在于划界。经 FactMarker 校验，技术特征与交底书一致；经 TabooDetector 扫描，无禁用词。请重点审查权1的前序部分和技术问题陈述。"
- For OA responses: "已解析审查意见中的3条驳回理由（权1-3不具备创造性），完成 D1/D2 特征对比，基于三基本一无需原则撰写争辩理由。权利要求已修改为包含区别技术特征。"
- Never call `complete` until you have actually verified the output.

## Known Limitations

- The summary is not persisted to the case database — it lives only in the current chat session.
- `complete` terminates the Loop; any remaining tools in the batch will not execute.
