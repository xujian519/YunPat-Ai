---
name: patent_translate_terms
description: Look up standard patent terminology translations (Chinese ↔ English). Query a built-in dictionary of 70+ common patent terms with their established equivalents.
version: 1.0.0
author: YunPat-AI Team
---

# patent_translate_terms

## When to Use

- Unsure about the standard translation of a patent term before running `patent_translate_cn2en` or `patent_translate_en2cn`
- Verifying that a term used in a draft translation matches accepted patent lexicon
- Building a glossary of terms for a specific patent family being filed in multiple jurisdictions
- The user asks "这个术语怎么翻译", "patent term translation", or "术语查询"

## Typical Workflow

1. Identify an ambiguous or domain-specific patent term.
2. Call `patent_translate_terms` with the term (Chinese or English).
3. Review the exact match. If no exact match, review the partial matches.
4. If the term is not in the dictionary, proceed with `patent_translate_cn2en` / `patent_translate_en2cn` which uses the LLM's broader knowledge.
5. Add frequently-used but missing terms to the dictionary.

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `term`    | string | yes      | —       | Patent term to look up (Chinese or English)    |
| `keyword` | string | no       | —       | Alias for `term`                               |

## Return Value

Exact match:

```
【术语】权利要求 → claim
```

Partial matches:

```
【术语查询】3 条匹配:
  权利要求 ⇄ claim
  多项从属权利要求 ⇄ multiple dependent claim
  权利要求书 ⇄ claims
```

No match:

```
【术语查询】未找到 'quantum dot'，内置词库含 70 条术语。
```

## Built-in Dictionary Coverage (70+ terms)

The dictionary covers: claim types, patentability criteria, prosecution terms, procedural terms, document sections, and common legal phrases. See the source code in `ToolDispatch.handlePatentTranslateTerms` for the full list.

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `term` is empty           | Provide a term to look up                    |

## Tips

- Use this tool BEFORE running large translations — it's fast and deterministic, unlike LLM translation.
- Search in either direction: query in Chinese to get English, or in English to get Chinese.
- Partial matching means you can search "权利" to find all claim-related terms.
- For terms not in the dictionary: the LLM will still translate them in `patent_translate_cn2en` / `patent_translate_en2cn`, but consistency is not guaranteed across calls.
- Consider maintaining a per-case term glossary if the patent involves specialized domain vocabulary (e.g., semiconductor processing, gene editing).

## Known Limitations

- The built-in dictionary covers general patent terminology. Domain-specific technical terms (e.g., "finFET", "CRISPR-Cas9") are not included.
- The dictionary is static — new terms added during a session are not persisted.
- The dictionary focuses on CNIPA ↔ USPTO terminology. EPO-specific terms may have different conventions.
