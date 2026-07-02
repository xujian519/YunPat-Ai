---
name: oa_compare
description: Perform feature-by-feature comparison between patent claims and a cited reference document. Used to evaluate novelty and inventive step rejections in office actions.
version: 1.0.0
author: YunPat-AI Team
---

# oa_compare

## When to Use

- An OA rejection cites prior art (D1, D2, etc.) against specific claims
- Building a claim chart for an OA response to show distinguishing features
- Analyzing whether a cited reference actually discloses each claim feature
- Preparing arguments that a reference does not teach or suggest a particular feature

## Typical Workflow

1. After `oa_parse` identifies the affected claims and references.
2. For each rejected claim, call `oa_compare` with the claim text and the reference number.
3. The LLM produces a feature-by-feature table showing: claim feature → reference disclosure → whether the feature is present.
4. Identify distinguishing features that are NOT disclosed in the reference.
5. Use these distinguishing features as the basis for arguments in `oa_response`.

## Parameters

| Parameter   | Type   | Required | Default | Description                                    |
| ----------- | ------ | -------- | ------- | ---------------------------------------------- |
| `claims`    | string | yes      | —       | Full text of the claims to compare             |
| `reference` | string | yes      | —       | Reference document number (e.g., "CN1234567A") |

## Return Value

```json
{
  "ok": true,
  "data": {
    "claim": "权利要求1的内容...",
    "reference": "CN1234567A",
    "comparison_table": [
      {"feature": "技术特征A", "in_reference": true, "reference_location": "段落[0023]"},
      {"feature": "技术特征B", "in_reference": false, "note": "区别技术特征"}
    ]
  }
}
```

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `claims` is empty         | Provide the claim text to compare            |

## Tips

- Compare each claim element individually — the standard is whether the reference discloses EACH AND EVERY feature, not whether it's in the same general field.
- For inventive step (创造性) rejections: even if all features are individually known, argue that the combination is non-obvious (not taught or suggested).
- Mark features as "partially disclosed" when the reference shows something similar but not identical — these are good candidates for amendment-based arguments.
- Include specific paragraph/line numbers from the reference to strengthen your comparison.
- For method claims: pay attention to step ordering — a reference that performs steps in a different order may not disclose the claimed method.

## Known Limitations

- The tool triggers LLM-based analysis. The LLM's knowledge of specific patent documents depends on its training data.
- The tool does not fetch the full text of the reference — you must provide the relevant portions separately.
- Equivalence (等同特征) analysis requires separate use of `infringement_equivalence`.
