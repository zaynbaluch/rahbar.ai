"""Stage 1 — watermark removal (color-preserving).

The scanned PCTB book has a light-grey diagonal "Web Version / Not for Sale"
watermark. Plain OCR reads clean body text fine, but where the watermark crosses
text near figures it corrupts characters (see docs/decisions/ADR-005). We remove
it BEFORE Docling.

Color-preserving trick (HSV): the watermark is **low-saturation, mid-brightness**
grey. Black text is low-brightness; white paper is very high-brightness; colored
diagrams are high-saturation. So we lift only low-saturation, mid-bright pixels to
white — erasing the watermark while keeping text AND colored figures intact (the
latter matters for VLM captioning later).

Outputs a cleaned PDF that Docling then parses.

Run: uv run python -m src.preprocess            # all pages
     uv run python -m src.preprocess 10 20 30   # specific pages (debug PNGs)
"""

from __future__ import annotations

import pathlib
import sys

import cv2
import fitz  # PyMuPDF
import numpy as np

REPO = pathlib.Path(__file__).resolve().parents[2]
PDF_IN = REPO / "data" / "raw" / "General_Science_Textbook_6th_Grade.pdf"
PDF_OUT = REPO / "data" / "processed" / "textbook_cleaned.pdf"
DEBUG_DIR = REPO / "data" / "processed" / "preprocess_debug"

RENDER_DPI = 200

# Watermark mask thresholds (tuned for this book's grey watermark).
SAT_MAX = 45      # keep only low-saturation (grey/neutral) pixels ...
VAL_MIN = 130     # ... that are brighter than black text ...
VAL_MAX = 246     # ... but not already pure-white paper.


def render_page_rgb(page: fitz.Page) -> np.ndarray:
    pix = page.get_pixmap(dpi=RENDER_DPI)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.h, pix.w, pix.n)
    if pix.n == 4:
        img = cv2.cvtColor(img, cv2.COLOR_RGBA2RGB)
    return img  # RGB


def remove_watermark(rgb: np.ndarray) -> np.ndarray:
    """Lift low-sat mid-bright (watermark) pixels to white; keep text + color."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    s, v = hsv[:, :, 1], hsv[:, :, 2]
    mask = (s < SAT_MAX) & (v > VAL_MIN) & (v < VAL_MAX)
    out = rgb.copy()
    out[mask] = (255, 255, 255)
    return out


JPEG_QUALITY = 88  # scanned pages compress well; keeps OCR quality, small file


def rgb_to_pdf_page(
    out_pdf: fitz.Document, rgb: np.ndarray, point_size: tuple[float, float]
) -> None:
    ok, buf = cv2.imencode(
        ".jpg",
        cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR),
        [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY],
    )
    if not ok:
        raise RuntimeError("JPEG encode failed")
    # Page size must be in POINTS (1/72"), matching the source page — NOT pixels,
    # or the page becomes huge and downstream rasterization explodes.
    pw, ph = point_size
    page = out_pdf.new_page(width=pw, height=ph)
    page.insert_image(fitz.Rect(0, 0, pw, ph), stream=buf.tobytes())


def main(argv: list[str]) -> None:
    doc = fitz.open(PDF_IN)
    debug_pages = [int(a) for a in argv] if argv else None

    if debug_pages:
        DEBUG_DIR.mkdir(parents=True, exist_ok=True)
        for p in debug_pages:
            rgb = render_page_rgb(doc[p - 1])
            cleaned = remove_watermark(rgb)
            cv2.imwrite(str(DEBUG_DIR / f"page{p:03d}_before.png"),
                        cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
            cv2.imwrite(str(DEBUG_DIR / f"page{p:03d}_after.png"),
                        cv2.cvtColor(cleaned, cv2.COLOR_RGB2BGR))
            print(f"page {p}: debug PNGs -> {DEBUG_DIR}")
        doc.close()
        return

    PDF_OUT.parent.mkdir(parents=True, exist_ok=True)
    n = doc.page_count
    out_pdf = fitz.open()
    for i in range(n):
        src_rect = doc[i].rect  # point dimensions of the original page
        cleaned = remove_watermark(render_page_rgb(doc[i]))
        rgb_to_pdf_page(out_pdf, cleaned, (src_rect.width, src_rect.height))
        if (i + 1) % 20 == 0:
            print(f"  cleaned {i + 1}/{n} pages")
    out_pdf.save(PDF_OUT, deflate=True, garbage=4)
    out_pdf.close()
    doc.close()
    print(f"Cleaned PDF -> {PDF_OUT} ({n} pages)")


if __name__ == "__main__":
    main(sys.argv[1:])
