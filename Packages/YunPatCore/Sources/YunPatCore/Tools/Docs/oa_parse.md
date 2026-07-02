---
name: oa_parse
description: Parse a Chinese Office Action (审查意见通知书) and extract rejection grounds, cited reference numbers, examiner arguments, and affected claims. Uses regex patterns for common OA phrasing.
version: 1.0.0
author: YunPat-AI Team
---

# oa_parse

## When to Use

- An OA text has been received and needs structured analysis
- The user pastes OA content and asks "分析审查意见" or "parse this office action"
- Multiple rejection grounds need to be separated and categorized
- Preparing an OA response strategy requires understanding each rejection individually

## Typical Workflow

1. Receive the full OA text from the user (copy-pasted or extracted from PDF).
2. Call `oa_parse` to extract structured rejection information.
3. For each rejection ground, identify: the claim(s) affected, the legal basis (Article 22.2/22.3/26.4, etc.), and the cited references.
4. Proceed to `oa_compare` for each claim-reference pair that needs feature-by-feature analysis.
5. After all comparisons, use `oa_response` to draft the response.

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `oa_text` | string | yes      | —       | Full text of the office action                 |
| `content` | string | no       | —       | Alias for `oa_text`                            |

## Return Value

```json
{
  "ok": true,
  "data": {
    "rejections": ["权利要求1不具备新颖性", "权利要求2-3不具备创造性"],
    "references": ["D1: CN1234567A", "D2: US9876543B2"],
    "affected_claims": [1, 2, 3]
  }
}
```

The tool uses regex patterns to detect common OA phrasing in Chinese:
- `权利要求\d+[^。]*不[具]?备(?:新颖|创造)性` — detects novelty/inventive step rejections
- `(?:对比文件|D)\s*[1-4]\s*[：:]\s*(CN|US|EP|WO)\d+` — extracts reference document numbers

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `oa_text` is empty        | Provide the OA content as text               |

## Tips

- If the OA is a scanned PDF, use `pdf_render_page` + OCR before calling `oa_parse`.
- The regex covers common CNIPA phrasing patterns. For unusual formulations, manually review the output.
- Pay special attention to Article 26.4 rejections (clarity/support) — these require different response strategies than novelty/inventive step rejections.
- If no rejections are detected by regex, the OA may use non-standard language or may be a procedural notice rather than a substantive rejection.

## Known Limitations

- Regex-based parsing covers ~80% of standard CNIPA OA phrasing. Edge cases and non-standard wording may be missed.
- The tool does not distinguish between primary references and secondary references in inventive step rejections.
- Procedural notices (formality corrections, deadline reminders) are not parsed — the tool focuses on substantive rejections.
