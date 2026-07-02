---
name: infringement_feature_table
description: Generate a feature-by-feature comparison table between patent claims and an accused product/process. Used in patent infringement analysis under the all-elements rule (全面覆盖原则).
version: 1.0.0
author: YunPat-AI Team
---

# infringement_feature_table

## When to Use

- The user provides a patent claim set and a description of an accused product
- Preparing an infringement opinion (侵权分析报告) for litigation or licensing
- Evaluating whether a competitor's product falls within the patent's protection scope
- The user asks "做侵权对比", "generate infringement table", or "侵权分析"

## Typical Workflow

1. Obtain the patent claims (independent claims first) and a detailed description of the accused product.
2. Call `infringement_feature_table` with both inputs.
3. The LLM decomposes the claims into individual technical features.
4. For each feature, determine whether it is present in the accused product (相同) or equivalent (等同).
5. If literal infringement is not found for all features, proceed to `infringement_equivalence` for borderline features.
6. Summarize the infringement conclusion.

## Parameters

| Parameter           | Type   | Required | Default | Description                                    |
| ------------------- | ------ | -------- | ------- | ---------------------------------------------- |
| `claims`            | string | yes      | —       | Patent claim text to compare against           |
| `product_description`| string| yes      | —       | Description of the accused product or process  |

## Return Value

The tool returns a comparison table with the format:

```
【特征对比表】
专利: <claim summary>
产品: <product summary>

| 序号 | 专利特征 | 被控产品对应特征 | 判定 |
|------|---------|-----------------|------|
| 1    | ...     | ...             | 相同/等同/缺失 |
```

## Error Codes

| Code           | Meaning                          | Recovery                                    |
| -------------- | -------------------------------- | ------------------------------------------- |
| `INVALID_ARGS` | `claims` or `product_description` is empty | Provide both inputs              |

## Tips

- Start with the broadest independent claim (Claim 1). If it covers the product, infringement is established without analyzing dependent claims.
- The all-elements rule (全面覆盖原则) means EVERY feature must be present — one missing feature = no literal infringement.
- For the product description: be as specific as possible. "A smartphone with NFC" is better than "a mobile device".
- Consider both literal infringement (相同侵权) and equivalent infringement (等同侵权). Mark features that require equivalence analysis.
- Document the source of the product description — is it based on a tear-down, datasheet, or user manual?
- In Chinese practice: the "三基本一无需" test for equivalence (基本相同的手段、功能、效果 + 无需创造性劳动) should be noted.

## Known Limitations

- The tool triggers LLM-based analysis. The accuracy depends on the detail level of the product description.
- The tool does not access live product databases — all product information must be provided by the user.
- Design patent infringement (外观设计) requires visual comparison and is not handled by this tool.
