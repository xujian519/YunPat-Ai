---
name: patent_draft_description
description: Draft the five-part patent specification (说明书): technical field, background art, summary of invention, description of drawings, and detailed description. Used after claims are finalized.
version: 1.0.0
author: YunPat-AI Team
---

# patent_draft_description

## When to Use

- Claims have been drafted and now the full specification is needed
- The user requests "写说明书", "draft the specification", or "撰写专利说明书"
- Converting a technical disclosure into a formal patent application document
- The five-part structure is required by CNIPA for Chinese patent applications

## Typical Workflow

1. Ensure claims are finalized first — the description must support every claim feature.
2. Draft the five sections in order: 技术领域, 背景技术, 发明内容, 附图说明, 具体实施方式.
3. The "发明内容" section should mirror the claims (copy claims verbatim as required by CNIPA practice).
4. In "具体实施方式", provide at least one detailed embodiment with specific parameters, materials, and alternatives.
5. Verify that every claim term is explained in the description.
6. Run TabooDetector to catch absolute language ("必须", "完全", "所有情况").

## Parameters

| Parameter           | Type     | Required | Default | Description                                    |
| ------------------- | -------- | -------- | ------- | ---------------------------------------------- |
| `technical_solution`| string   | yes      | —       | Full text of the technical disclosure          |
| `features`          | string[] | no       | `[]`    | List of key technical features to elaborate    |

## Return Value

The tool returns the technical solution text and instructs the LLM to produce the five-part description. The actual specification text appears in the subsequent LLM message.

## Error Codes

| Code           | Meaning                          | Recovery                                    |
| -------------- | -------------------------------- | ------------------------------------------- |
| `INVALID_ARGS` | No technical solution provided   | Provide `technical_solution` or both fields |

## Tips

- Draft the description AFTER claims are approved — the description must support the exact claim language.
- Background art should cite specific patent numbers when available, not generic statements.
- In the detailed description, use "可以" (may), "优选地" (preferably), and "例如" (for example) to avoid limiting interpretation.
- Provide at least 2–3 alternative embodiments even for simple inventions.
- For software inventions: include flowcharts and describe each step in the method.
- The description must enable a "person skilled in the art" (本领域普通技术人员) to practice the invention — include specific values, ranges, and operational steps.

## Known Limitations

- The LLM does not generate actual patent drawings. Mark drawing positions with `<FIGURE N>` placeholders.
- Chemical structure formulas cannot be rendered. Describe them textually or reference ChemDraw files.
- Very long descriptions (>10,000 characters) may need to be split across multiple LLM calls.
