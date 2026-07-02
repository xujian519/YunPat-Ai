---
name: pdf_render_page
description: Render a specific page of a PDF to a CGImage. Use in combination with OCR or document detection tools. Always call pdf_get_info first to know the page count.
version: 1.0.0
author: YunPat-AI Team
---

# pdf_render_page

## When to Use

- Extracting text from a scanned patent PDF via OCR after rendering
- Rendering patent drawings or chemical structure diagrams for visual inspection
- Capturing specific pages of a patent document for annotation or comparison
- Preparing patent figures for inclusion in an OA response or analysis report

## Typical Workflow

1. Call `pdf_get_info` to learn the page count and dimensions.
2. Identify target pages: first page (bibliographic data), claims section, key drawings.
3. Call `pdf_render_page` for each target page, specifying appropriate DPI.
4. Pass rendered images to text extraction or document detection tools.
5. Aggregate extracted text into a structured analysis.

## Parameters

| Parameter        | Type   | Required | Default | Description                                      |
| ---------------- | ------ | -------- | ------- | ------------------------------------------------ |
| `pdf_path`       | string | yes      | —       | Absolute or project-relative path to the PDF     |
| `page`           | int    | no       | `1`     | Page number (1-based) to render                  |
| `dpi`            | int    | no       | `300`   | Rendering resolution in dots per inch            |
| `output_path`    | string | no       | —       | Optional path to save the rendered image         |
| `_context_folder`| string | no       | project folder | Base directory for relative path resolution |

## Return Value

Success (`ok: true`):

```json
{
  "ok": true,
  "data": {
    "page": 1,
    "dpi": 300,
    "width": 2480,
    "height": 3508,
    "status": "rendered"
  }
}
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "READ_ERROR", "message": "Cannot render page 20 — PDF only has 15 pages." } }
```

## Error Codes

| Code         | Meaning                        | Recovery                                          |
| ------------ | ------------------------------ | ------------------------------------------------- |
| `NOT_FOUND`  | PDF file does not exist        | Verify path with `list_files`                     |
| `INVALID_ARGS` | `page` exceeds page count    | Call `pdf_get_info` to learn valid page range     |
| `READ_ERROR` | Page rendering failed          | Try lowering DPI or check if PDF is corrupted     |

## Tips

- Use 150 DPI for quick previews, 300 DPI for OCR (recommended), and 600 DPI for detailed drawings.
- For patent documents with text layer: skip OCR and use `read_file` or `document_parse_word` if available in text format.
- Chinese patent PDFs from CNIPA often have scanned pages without embedded text — OCR is required.
- Render only the pages you need. A 100-page patent does not need all pages rendered; focus on claims (typically last 1–5 pages), abstract, and key drawings.

## Known Limitations

- The rendered image is currently held in memory as a CGImage. No image file is written to disk unless `output_path` is specified.
- Very large DPI values (>600) may cause memory pressure for large-format PDFs.
- Color accuracy in patent drawings (grayscale line art) is not guaranteed.
