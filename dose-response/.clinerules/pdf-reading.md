
When reading any PDF in this workspace (SAP, ADRG, CSR, or any other document):
- Do NOT convert the PDF to text using `pdftotext` — it will mangle tables you need to read accurately
- Use `pypdfium2` instead
- Note: a `PdfPage` object has no attribute `get_text` — use `get_textpage`: `page.get_textpage().get_text_range()`
