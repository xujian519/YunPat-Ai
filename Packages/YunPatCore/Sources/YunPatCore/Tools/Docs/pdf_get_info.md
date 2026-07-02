---
name: pdf_get_info
description: Inspect PDF metadata — page count, page dimensions, encryption status. Always call this tool first before rendering pages with pdf_render_page to understand the document scope.
version: 1.0.0
author: YunPat-AI Team
---

# pdf_get_info

## When to Use

- Before reading a patent PDF: determine total page count to plan rendering strategy
- Checking whether a PDF is encrypted before attempting text extraction
- Validating that a patent document's page dimensions match expected formats (A4, Letter)
- Deciding how many pages to render based on document length

## Typical Workflow

1. Receive a PDF file path from the user or from a previous tool output.
2. Call `pdf_get_info` to obtain metadata.
3. Based on page count, decide how many pages to render: short documents (<10 pages) can be fully rendered; long documents should render key pages (first page, claims section, drawings).
4. Proceed with `pdf_render_page` for the selected pages.
5. Run OCR or text extraction on the rendered pages.

## Parameters

| Parameter        | Type   | Required | Default | Description                                    |
| ---------------- | ------ | -------- | ------- | ---------------------------------------------- |
| `pdf_path`       | string | yes      | —       | Absolute or project-relative path to the PDF   |
| `_context_folder`| string | no       | project folder | Base directory for relative path resolution |

## Return Value

Success (`ok: true`):

```json
{
  "ok": true,
  "data": {
    "pageCount": 15,
    "width": 595.0,
    "height": 842.0,
    "isEncrypted": false,
    "isLocked": false
  }
}
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "NOT_FOUND", "message": "PDF file not found at path.", "hint": "Use list_files to verify the path." } }
```

## Error Codes

| Code         | Meaning                   | Recovery                                      |
| ------------ | ------------------------- | --------------------------------------------- |
| `NOT_FOUND`  | File does not exist       | Verify path with `list_files`                 |
| `READ_ERROR` | File is not a valid PDF   | Check file format; try opening with a PDF reader |
| `INTERNAL`   | PDFKit could not open file| The file may be corrupted or password-protected |

## Tips

- Always call `pdf_get_info` before `pdf_render_page` — rendering page 15 of a 14-page document wastes a tool call.
- For encrypted PDFs: inform the user and ask for the password rather than failing silently.
- Chinese patent PDFs are typically A4 (595×842 points). If dimensions differ significantly, warn the user — the PDF may contain scanned images rather than text.

## Known Limitations

- Password-protected PDFs cannot be opened. The tool will report an error; the user must provide an unprotected copy.
- Page dimensions are reported in PDF points (1/72 inch), not pixels. Multiply by DPI/72 to get pixel dimensions for rendering.
