---
name: patent_translate_cn2en
description: Translate Chinese patent text to English following patent terminology standards. Preserves claim structure, legal phrasing, and technical accuracy.
version: 1.0.0
author: YunPat-AI Team
---

# patent_translate_cn2en

## When to Use

- Preparing a Chinese patent application for PCT international filing (needs English translation)
- Translating CNIPA OA responses for foreign counsel review
- Producing English versions of Chinese patent claims for licensing negotiations
- The user asks "翻译成英文", "translate to English", or "中译英"

## Typical Workflow

1. Obtain the Chinese patent text (claims, description, or OA response).
2. Call `patent_translate_cn2en` with the text.
3. The LLM translates while preserving patent-specific conventions:
   - "所述" → "said" (not "the")
   - "其特征在于" → "characterized in that"
   - Claim numbering and dependency structure
4. Verify key terminology using `patent_translate_terms` for ambiguous terms.
5. Review the translation for technical accuracy — LLM may misinterpret domain-specific jargon.

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `text`    | string | yes      | —       | Chinese patent text to translate               |
| `content` | string | no       | —       | Alias for `text`                               |

## Return Value

The tool returns the LLM-translated English text in the subsequent message. The translation preserves:
- Claim numbering (1., 2., 3.)
- Dependency references ("The method of claim 1, wherein...")
- Statutory language conventions

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `text` is empty           | Provide Chinese text to translate            |

## Tips

- Translate claims FIRST, then the description. Claim terminology sets the lexicon for the rest of the document.
- For mechanical/electrical patents: the LLM generally produces good translations. For chemical/biotech patents: verify IUPAC nomenclature and sequence listings manually.
- Preserve Chinese patent numbering in translations: "权利要求1" → "Claim 1", "实施例1" → "Embodiment 1".
- For OA responses: the argumentation logic must survive translation. Review translated arguments to ensure the reasoning chain is intact.
- Use `patent_translate_terms` to verify domain-specific terms before finalizing the translation.

## Known Limitations

- The LLM translates based on its training data. Novel technical terms coined in the patent may not have established English equivalents.
- Character-count limits: input is previewed at 500 characters. For full-document translation, use multiple calls section by section.
- Purely legal phrasing (e.g., "本领域普通技术人员") has accepted translations but the LLM may not consistently use them.
- Machine translation should be reviewed by a human patent translator before filing.
