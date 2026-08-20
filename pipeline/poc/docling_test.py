"""Docling structured-parse test on a few pages.

Confirms Docling (configured to use our validated Tesseract OCR) produces
layout-aware Markdown — headings, tables, figure regions — on the scanned
textbook, and is memory-viable here, BEFORE the full 153-page run.

Run: uv run python poc/docling_test.py
First run downloads Docling's layout/table models (~hundreds of MB).
"""

from __future__ import annotations

import pathlib
import time

from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import (
    PdfPipelineOptions,
    TesseractCliOcrOptions,
)
from docling.document_converter import DocumentConverter, PdfFormatOption

REPO = pathlib.Path(__file__).resolve().parents[2]
PDF = REPO / "data" / "raw" / "General_Science_Textbook_6th_Grade.pdf"
OUT = REPO / "data" / "processed" / "docling_test"

PAGE_RANGE = (10, 12)  # small, representative slice (text + figure + boxes)


def build_converter() -> DocumentConverter:
    opts = PdfPipelineOptions()
    opts.do_ocr = True
    # Scanned pages have no text layer → force full-page OCR with Tesseract.
    opts.ocr_options = TesseractCliOcrOptions(
        lang=["eng"], force_full_page_ocr=True
    )
    opts.do_table_structure = True
    opts.generate_picture_images = True  # keep figure crops for VLM captioning
    opts.images_scale = 2.0
    opts.do_picture_classification = False  # skip extra model for now
    return DocumentConverter(
        format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=opts)}
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    conv = build_converter()

    t0 = time.time()
    result = conv.convert(
        PDF, page_range=PAGE_RANGE, raises_on_error=True
    )
    elapsed = time.time() - t0
    doc = result.document

    md = doc.export_to_markdown()
    (OUT / "pages_10-12.md").write_text(md, encoding="utf-8")

    # Structure summary
    n_tables = len(doc.tables)
    n_pics = len(doc.pictures)
    n_texts = len(doc.texts)
    headings = [
        t.text
        for t in doc.texts
        if getattr(t, "label", None) and "head" in str(t.label).lower()
    ]

    print(f"Parsed pages {PAGE_RANGE} in {elapsed:.1f}s")
    print(f"  text items : {n_texts}")
    print(f"  headings   : {len(headings)} -> {headings[:8]}")
    print(f"  tables     : {n_tables}")
    print(f"  pictures   : {n_pics}")
    print(f"  markdown   : {len(md)} chars -> {OUT / 'pages_10-12.md'}")
    print("\n--- markdown preview (first 1400 chars) ---\n")
    print(md[:1400])


if __name__ == "__main__":
    main()
