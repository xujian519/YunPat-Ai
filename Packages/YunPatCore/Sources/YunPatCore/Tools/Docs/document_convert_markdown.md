---
name: document_convert_markdown
description: Convert document content to Markdown format. Useful for normalizing patent texts, OA content, and technical disclosures into a consistent, LLM-friendly format.
version: 1.0.0
author: YunPat-AI Team
---

# document_convert_markdown

## When to Use

- A document extracted from Word/PDF contains formatting that should be preserved as structured Markdown
- Preparing patent text for LLM processing where Markdown headers and lists improve comprehension
- Converting a technical disclosure from plain text to structured format with sections
- Normalizing patent document sections (claims, description, abstract) into Markdown for consistent tool input

## Typical Workflow

1. Obtain the document text (from `document_parse_word`, `read_file`, or user paste).
2. Call `document_convert_markdown` to convert to Markdown.
3. Review the structured output — headers are `##`, lists are `-`, emphasis is `**bold**`.
4. Pass the structured Markdown to downstream analysis tools.
5. If the conversion misses key structure, manually annotate the Markdown.

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `text`    | string | yes      | —       | Raw text content to convert to Markdown        |
| `content` | string | no       | —       | Alias for `text`                               |

## Return Value

The tool returns the LLM-converted Markdown output in the subsequent message.

## Error Codes

| Code           | Meaning                   | Recovery                                     |
| -------------- | ------------------------- | -------------------------------------------- |
| `INVALID_ARGS` | `text` is empty           | Provide text content to convert              |

## Tips

- The conversion excels at: patent section headings (技术领域, 背景技术, etc.), numbered claim lists, and OA structured paragraphs.
- For maximum quality, provide the text in logical sections rather than one monolithic block.
- Use this tool as a preprocessing step before feeding text to other analysis tools — structured Markdown improves LLM comprehension of patent hierarchy.
- If converting Chinese patent text, the tool preserves: 「」quotation marks, Chinese numbering (一、二、三), and mixed CN/EN technical terms.
- The tool is LLM-driven and may normalize formatting. For exact-format preservation, use `read_file` directly.

## Known Limitations

- The conversion is LLM-based and adds latency (~1–3 seconds depending on text length).
- Mathematical formulas and chemical structures are not converted — they remain as plain text descriptions.
- Tables in the source text may not convert cleanly to Markdown table format. Review table-heavy content manually.
- Truncation at 2000 input characters. For longer documents, split into sections and convert each separately.
