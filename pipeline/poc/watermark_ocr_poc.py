"""Watermark-removal + OCR proof-of-concept.

Validates that we can turn the scanned, watermarked PCTB Class-6 textbook into
clean text BEFORE committing to the full pipeline (see docs/decisions/ADR-005).

For a handful of representative pages it:
  1. renders the page to an image,
  2. removes the light-grey diagonal "Web Version / Not for Sale" watermark,
  3. OCRs both the raw and cleaned versions with Tesseract,
  4. saves before/after PNGs + the OCR text for manual inspection.

Run: uv run python poc/watermark_ocr_poc.py
"""

from __future__ import annotations

import pathlib

import cv2
import fitz  # PyMuPDF
import numpy as np
import pytesseract

REPO = pathlib.Path(__file__).resolve().parents[2]
PDF = REPO / "data" / "raw" / "General_Science_Textbook_6th_Grade.pdf"
OUT = REPO / "data" / "processed" / "poc"

# A spread of layouts: front matter, body text, a figure page, an
# activity-table + key-points page. (PDF indices are 1-based here.)
PAGES = [10, 18, 20, 21, 30]

RENDER_DPI = 200
# Pixels lighter than this grey level are pushed to white — erases the light
# watermark while leaving the near-black body text intact.
WATERMARK_CUTOFF = 150


def render_page(doc: fitz.Document, page_index_1based: int) -> np.ndarray:
    """Render a page to a BGR numpy image at RENDER_DPI."""
    page = doc[page_index_1based - 1]
    pix = page.get_pixmap(dpi=RENDER_DPI)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.h, pix.w, pix.n)
    if pix.n == 4:  # RGBA -> RGB
        img = cv2.cvtColor(img, cv2.COLOR_RGBA2RGB)
    return cv2.cvtColor(img, cv2.COLOR_RGB2BGR)


def clean_watermark(bgr: np.ndarray) -> np.ndarray:
    """Return a binarized image with the light watermark removed."""
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    # 1. Knock out anything lighter than the cutoff (watermark + paper) -> white.
    gray[gray > WATERMARK_CUTOFF] = 255
    # 2. Otsu binarize what remains (dark text) for crisp OCR input.
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return binary


def ocr(img: np.ndarray) -> str:
    # psm 3 = fully automatic page segmentation (handles columns/boxes).
    return pytesseract.image_to_string(img, lang="eng", config="--psm 3").strip()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    doc = fitz.open(PDF)
    print(f"PDF: {PDF.name}  ({doc.page_count} pages)\n")

    for p in PAGES:
        bgr = render_page(doc, p)
        cleaned = clean_watermark(bgr)

        raw_text = ocr(bgr)
        clean_text = ocr(cleaned)

        cv2.imwrite(str(OUT / f"page{p:03d}_raw.png"), bgr)
        cv2.imwrite(str(OUT / f"page{p:03d}_cleaned.png"), cleaned)
        (OUT / f"page{p:03d}_raw.txt").write_text(raw_text, encoding="utf-8")
        (OUT / f"page{p:03d}_cleaned.txt").write_text(clean_text, encoding="utf-8")

        wm_raw = raw_text.lower().count("web version") + raw_text.lower().count("not for sale")
        wm_clean = clean_text.lower().count("web version") + clean_text.lower().count("not for sale")

        print(f"── page {p} ─────────────────────────────────────────────")
        print(f"  raw    : {len(raw_text):5d} chars, watermark hits={wm_raw}")
        print(f"  cleaned: {len(clean_text):5d} chars, watermark hits={wm_clean}")
        print("  cleaned preview:")
        preview = "\n".join("    " + ln for ln in clean_text.splitlines()[:8] if ln.strip())
        print(preview or "    (empty)")
        print()

    doc.close()
    print(f"Artifacts written to: {OUT}")


if __name__ == "__main__":
    main()
