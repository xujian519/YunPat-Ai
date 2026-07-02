---
name: oa_response
description: Generate a draft response to a Chinese patent office action based on analysis results and chosen strategy. Produces argumentation text and amended claims if needed.
version: 1.0.0
author: YunPat-AI Team
---

# oa_response

## When to Use

- All rejections have been parsed (`oa_parse`) and compared (`oa_compare`)
- A response strategy has been chosen: argue distinction (争辩), amend claims (修改), or both
- The user asks to "写答复意见", "draft OA response", or "生成审查意见答复"
- The deadline is approaching and a draft is needed for attorney review

## Typical Workflow

1. Complete `oa_parse` and `oa_compare` for all rejected claims.
2. Determine the strategy for each rejection:
   - **争辩 (argue)**: The examiner misread the reference; the feature is genuinely not disclosed.
   - **修改 (amend)**: Acknowledge the rejection and narrow the claims to add distinguishing features.
   - **删除 (cancel)**: Concede the rejection and cancel the claim.
3. Call `oa_response` with the rejection reason and chosen strategy.
4. Review the draft for legal soundness and factual accuracy.
5. Use `complete` to deliver the final response.

## Parameters

| Parameter         | Type   | Required | Default | Description                                    |
| ----------------- | ------ | -------- | ------- | ---------------------------------------------- |
| `rejection_reason`| string | yes      | —       | The rejection ground to respond to             |
| `strategy`        | string | yes      | "争辩"  | Response strategy: 争辩/修改/删除              |

## Return Value

The tool triggers LLM-based drafting. The response text appears in the subsequent message.

## Error Codes

| Code           | Meaning                          | Recovery                                    |
| -------------- | -------------------------------- | ------------------------------------------- |
| `INVALID_ARGS` | `rejection_reason` is empty     | Provide the rejection reason to respond to  |

## Tips

- Structure each response argument as: (1) examiner's position, (2) applicant's counter-position, (3) legal basis, (4) evidence from the specification/claims.
- When amending claims: show the amended text with strike-through (删除) and underline (新增) formatting so the examiner can see exactly what changed.
- Cite specific paragraphs from the original specification to support "written description" arguments.
- For inventive step rejections: argue that the combination of D1+D2 is based on impermissible hindsight (事后诸葛亮) — the examiner only combined them because they already know the invention.
- Never amend claims in a way that adds new matter (违反专利法第33条) — the amendment must be supported by the original disclosure.
- Include a concluding statement: "申请人认为，经上述修改和/或陈述后，本申请已克服审查意见指出的缺陷，符合授权条件。"

## Known Limitations

- The LLM drafts response text but does not guarantee compliance with all CNIPA formal requirements. Attorney review is always required.
- The tool does not track amendment history across multiple OAs — maintain a separate amendment log.
- Response deadlines (typically 4 months + 15 days for CNIPA) are not tracked by this tool.
