---
name: document_parse_word
description: Extract text content from Microsoft Word (.doc/.docx) files. Returns the extracted plain text for further processing or analysis.
version: 1.0.0
author: YunPat-AI Team
---

# document_parse_word

## When to Use

- A patent disclosure or OA is provided as a Word document
- Extracting text from a .docx technical report before drafting claims
- Processing a batch of Word-formatted prior art references
- Converting a client's technical description from Word to structured patent analysis input

## Typical Workflow

1. Receive the Word file path from the user.
2. Call `document_parse_word` to extract the full text content.
3. Review the extracted text for formatting artifacts (headers, footers, tables may not extract cleanly).
4. Pass the extracted text to downstream tools: `patent_draft_claims`, `oa_parse`, `fact_extractor`, etc.
5. If the extraction is incomplete, ask the user to provide a plain text or PDF version.

## Parameters

| Parameter | Type   | Required | Default | Description                                    |
| --------- | ------ | -------- | ------- | ---------------------------------------------- |
| `path`    | string | yes      | —       | Absolute or project-relative path to the .doc/.docx file |

## Return Value

Success (`ok: true`):

```json
{
  "ok": true,
  "data": {
    "path": "/path/to/document.docx",
    "format": "docx",
    "content": "<extracted text, truncated to 3000 chars>",
    "total_chars": 15234
  }
}
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "NOT_FOUND", "message": "文件不存在: document.docx" } }
```

## Error Codes

| Code         | Meaning                          | Recovery                                       |
| ------------ | -------------------------------- | ---------------------------------------------- |
| `NOT_FOUND`  | File does not exist at path      | Use `list_files` to verify the path            |
| `READ_ERROR` | File cannot be read as text      | The file may be in older .doc (binary) format  |

## Tips

- Modern .docx files (Office Open XML) extract better than legacy .doc (binary) files. If the output is garbled, ask for a .docx or .txt version.
- The content is truncated to 3000 characters in the tool response. For full-text access, use `read_file` directly on the extracted path.
- Embedded images, equations, and tables are NOT extracted — only text content is returned.
- For patent documents with track changes enabled, the extracted text may include both original and revised content. Ask the user to accept all changes before extraction.

## Known Limitations

- Legacy .doc (binary) format support is limited. The tool attempts UTF-8 reading which may produce garbled output for binary .doc files.
- Text extraction from .docx relies on reading the raw XML structure directly. Complex formatting (nested tables, text boxes) may not extract in logical reading order.
- Maximum 3000 characters in the tool response. For larger documents, use the `total_chars` field to estimate remaining content and request specific sections.
