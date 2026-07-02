---
name: patent_translate_en2cn
description: Translate English patent text to Chinese following CNIPA terminology standards. Preserves claim structure and legal phrasing conventions.
version: 1.0.0
author: YunPat-AI Team
---

# patent_translate_en2cn

## When to Use

- Analyzing a USPTO/EPO patent or OA in Chinese patent practice
- Translating foreign prior art references for CNIPA submission
- Preparing Chinese versions of English patent claims for domestic client review
- The user asks "翻译成中文", "translate to Chinese", or "英译中"

## Typical Workflow

1. Obtain the English patent text (claims, specification, or office action).
2. Call `patent_translate_en2cn` with the text.
3. The LLM translates while preserving patent-specific conventions:
   - "said" → "所述"
   - "characterized in that" → "其特征在于"
   - "wherein" → "其中"
   - Claim numbering and dependency structure
4. Verify key terminology using `patent_translate_terms` for ambiguous terms.
5. Review for CNIPA stylistic compliance (Chinese patents use specific phrasing patterns).

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `text`    | string | yes      | —       | English patent text to translate               |
| `content` | string | no       | —       | Alias for `text`                               |

## Return Value

The tool returns the LLM-translated Chinese text in the subsequent message.

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `text` is empty           | Provide English text to translate            |

## Tips

- For US-origin patents: "comprising" → "包括" (not "包含" which implies exclusivity in Chinese patent practice).
- "Preferably" → "优选地"; "may" → "可以"; "for example" → "例如" — these hedging terms are important to preserve.
- Means-plus-function claims (35 USC 112(f)) have no direct CNIPA equivalent — translate the function and note the structural correspondence.
- USPTO OAs use different terminology than CNIPA OAs — translate concepts, not literally. "Obviousness rejection" = "不具备创造性".
- For very long English patents, translate in sections: abstract → claims → description.

## Known Limitations

- LLM translation quality varies by technical domain. Mechanical/electrical: good. Chemical/biotech/pharma: requires expert review.
- US patent drafting style (broad, multiple embodiments) differs from Chinese style (focused, fewer embodiments). The translation preserves the original style.
- Machine translation should be reviewed by a human patent translator before use in official proceedings.
