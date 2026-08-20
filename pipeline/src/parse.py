"""Stage 2 — Docling structured parse of the cleaned textbook.

Runs Docling (Tesseract OCR) on the watermark-cleaned PDF and exports:
  - textbook.md            : layout-aware Markdown (headings, figures, tables)
  - textbook.docling.json  : full DoclingDocument (blocks + provenance/bboxes)
  - figures/fig_###.png    : cropped figure images (for VLM captioning)

Structured JSON is what the chunking stage consumes (block types + reading
order + figure refs). See docs/decisions/ADR-005.

Processes the book in small **batches** (memory-safe on a 14 GB machine) with
**resume** — re-running skips batches whose output already exists. Each batch
writes its own markdown + JSON; the chunking stage reads all batches in order.

Run: uv run python -m src.parse            # all pages, batched, resumable
     uv run python -m src.parse 5 8        # one explicit range (validation)
"""

from __future__ import annotations

import json
import pathlib
import sys
import time

from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import (
    PdfPipelineOptions,
    TesseractCliOcrOptions,
)
from docling.document_converter import DocumentConverter, PdfFormatOption

REPO = pathlib.Path(__file__).resolve().parents[2]
# Parse the flat-field-cleaned PDF (watermark removed, colour + correct page
# size preserved — see src/preprocess.py). Run `python -m src.preprocess` first.
PDF = REPO / "data" / "processed" / "textbook_cleaned.pdf"
OUT = REPO / "data" / "processed" / "parse"
BATCH_DIR = OUT / "batches"
FIG_DIR = OUT / "figures"

BATCH_SIZE = 10  # pages per Docling pass — keeps peak RAM bounded


def build_converter() -> DocumentConverter:
    opts = PdfPipelineOptions()
    opts.do_ocr = True
    opts.ocr_options = TesseractCliOcrOptions(lang=["eng"], force_full_page_ocr=True)
    opts.do_table_structure = True
    opts.generate_picture_images = True
    opts.images_scale = 2.0
    opts.do_picture_classification = False
    return DocumentConverter(
        format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=opts)}
    )


def save_figures(doc, start_page: int) -> int:
    """Save figure crops as PNGs, named by absolute page for chunk linkage."""
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    saved = 0
    for i, pic in enumerate(doc.pictures):
        try:
            img = pic.get_image(doc)
        except Exception:
            img = None
        if img is None:
            continue
        # page_no within the batch is 1-based → map to absolute book page.
        rel = pic.prov[0].page_no if pic.prov else 1
        page = start_page + rel - 1
        img.save(FIG_DIR / f"fig_p{page:03d}_{i:02d}.png")
        saved += 1
    return saved


def scrub_image_blobs(d: dict) -> dict:
    """Drop base64 image data from the dict — figures are saved as PNGs."""
    for pic in d.get("pictures", []):
        if isinstance(pic, dict) and pic.get("image"):
            pic["image"] = None
    for pg in (d.get("pages") or {}).values() if isinstance(d.get("pages"), dict) else []:
        if isinstance(pg, dict) and pg.get("image"):
            pg["image"] = None
    return d


def parse_range(conv, start: int, end: int) -> None:
    tag = f"p{start:03d}-{end:03d}"
    md_path = BATCH_DIR / f"batch_{tag}.md"
    json_path = BATCH_DIR / f"batch_{tag}.docling.json"
    if json_path.exists():
        print(f"  batch {tag}: already done, skipping")
        return

    t0 = time.time()
    result = conv.convert(PDF, page_range=(start, end), raises_on_error=True)
    doc = result.document
    elapsed = time.time() - t0

    md_path.write_text(doc.export_to_markdown(), encoding="utf-8")
    json_path.write_text(
        json.dumps(scrub_image_blobs(doc.export_to_dict()), ensure_ascii=False),
        encoding="utf-8",
    )
    n_fig = save_figures(doc, start)
    print(
        f"  batch {tag}: {elapsed:.0f}s · texts={len(doc.texts)} "
        f"tables={len(doc.tables)} figures={n_fig}"
    )


def main(argv: list[str]) -> None:
    BATCH_DIR.mkdir(parents=True, exist_ok=True)
    conv = build_converter()

    if len(argv) == 2:  # explicit single range (validation)
        parse_range(conv, int(argv[0]), int(argv[1]))
        return

    total = fitz_page_count()
    print(f"Batched parse of {total} pages (batch size {BATCH_SIZE})")
    t0 = time.time()
    for start in range(1, total + 1, BATCH_SIZE):
        end = min(start + BATCH_SIZE - 1, total)
        parse_range(conv, start, end)
    print(f"Done in {(time.time() - t0) / 60:.1f} min -> {BATCH_DIR}")


def fitz_page_count() -> int:
    import fitz

    d = fitz.open(PDF)
    n = d.page_count
    d.close()
    return n


if __name__ == "__main__":
    main(sys.argv[1:])
