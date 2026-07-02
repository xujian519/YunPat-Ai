---
name: infringement_equivalence
description: Analyze whether a feature in an accused product is equivalent to a claimed feature under the triple-identity test (三基本一无需原则): substantially same means, function, and effect, achievable without creative effort.
version: 1.0.0
author: YunPat-AI Team
---

# infringement_equivalence

## When to Use

- A feature in the accused product is not literally identical to the claimed feature but performs a similar role
- The infringement_feature_table identified a feature as "等同" (equivalent) needing deeper analysis
- Preparing arguments for equivalent infringement in litigation
- Evaluating prosecution history estoppel (禁止反悔) — whether the patentee surrendered equivalent scope during prosecution

## Typical Workflow

1. Identify borderline features from `infringement_feature_table` where the matching is not exact.
2. For each borderline feature, call `infringement_equivalence` with the feature pair.
3. Apply the triple-identity test:
   - **基本相同的手段** (substantially same means)
   - **基本相同的功能** (substantially same function)
   - **基本相同的效果** (substantially same effect)
   - **无需创造性劳动** (achievable without creative effort by a person skilled in the art)
4. Check for prosecution history estoppel: did the applicant narrow this feature during prosecution?
5. Conclude whether equivalence applies.

## Parameters

| Parameter | Type     | Required | Default | Description                                    |
| --------- | -------- | -------- | ------- | ---------------------------------------------- |
| `features`| string[] | yes      | —       | List of feature pairs to analyze (e.g., ["专利权1特征A vs 产品特征A'"]) |

## Return Value

The tool returns equivalence analysis for each feature pair:

```
【等同分析】三基本一无需原则:

1. 专利特征A vs 产品特征A'
   - 手段: 基本相同 — <reasoning>
   - 功能: 基本相同 — <reasoning>
   - 效果: 基本相同 — <reasoning>
   - 无需创造性劳动: 是 — <reasoning>
   → 结论: 构成等同
```

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `features` is empty       | Provide feature pairs to analyze             |

## Tips

- Equivalence is judged at the TIME OF INFRINGEMENT, not the patent's filing date. Technological developments after filing may create new equivalent means.
- The doctrine of equivalents cannot expand claims to cover prior art — if the accused product practices the prior art, equivalence is blocked.
- "Substantially same" does not mean "functionally same outcome" — the way the function is achieved matters too.
- Be conservative: equivalence is an exception to literal infringement, not a tool to rewrite claims.
- Document the "person skilled in the art" baseline — what knowledge and capabilities would such a person have at the relevant time?

## Known Limitations

- The LLM's equivalence analysis is a preliminary opinion. Equivalence is ultimately a judicial determination with jurisdiction-specific nuances.
- Prosecution history estoppel analysis requires access to the full file wrapper (审查档案), which may not be available.
- The tool does not consider the "all-elements rule" limitation on equivalence — equivalence applies to individual features, not the invention as a whole.
