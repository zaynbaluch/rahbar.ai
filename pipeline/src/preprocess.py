"""Stage 1 — watermark removal via flat-field correction (color-preserving).

The scanned PCTB book has a light-grey diagonal "Web Version / Not for Sale"
watermark that is **pixel-identical on every page**. Therefore the per-pixel
**median across all pages** is the watermark+background template (page text is
sparse and varies, so it averages out). Dividing each page by that template
(flat-field correction) erases the watermark while leaving the page-specific
text and colour intact — verified to eliminate the OCR corruption it caused
(see docs/decisions/ADR-005).

Outputs a cleaned colour PDF that Docling then parses.

Run: uv run python -m src.preprocess            # all pages -> cleaned PDF
     uv run python -m src.preprocess 10 144     # debug PNGs for specific pages
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
TEMPLATE_PATH = REPO / "data" / "processed" / "watermark_template.png"
DEBUG_DIR = REPO / "data" / "processed" / "preprocess_debug"

RENDER_DPI = 200
TEMPLATE_STRIDE = 2   # build template from every Nth page (watermark is constant)
TEMPLATE_FLOOR = 110  # clamp template so text areas aren't blown out
JPEG_QUALITY = 88


def render_page_rgb(page: fitz.Page) -> np.ndarray:
    pix = page.get_pixmap(dpi=RENDER_DPI)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.h, pix.w, pix.n)
    if pix.n == 4:
        img = cv2.cvtColor(img, cv2.COLOR_RGBA2RGB)
    return img  # RGB


def build_template(doc: fitz.Document) -> np.ndarray:
    """Median grayscale image across pages = the watermark+background template."""
    if TEMPLATE_PATH.exists():
        return cv2.imread(str(TEMPLATE_PATH), cv2.IMREAD_GRAYSCALE).astype(np.float32)
    grays = []
    for i in range(0, doc.page_count, TEMPLATE_STRIDE):
        g = cv2.cvtColor(render_page_rgb(doc[i]), cv2.COLOR_RGB2GRAY)
        grays.append(g)
    h = min(x.shape[0] for x in grays)
    w = min(x.shape[1] for x in grays)
    tmpl = np.median(np.stack([x[:h, :w] for x in grays]), axis=0).astype(np.float32)
    TEMPLATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(TEMPLATE_PATH), tmpl.astype(np.uint8))
    print(f"  built watermark template {tmpl.shape} -> {TEMPLATE_PATH}")
    return tmpl


def remove_watermark(rgb: np.ndarray, template: np.ndarray) -> np.ndarray:
    """Flat-field: multiply each channel by a per-pixel gain (255 / template).

    Neutral watermark pixels are lifted to white; dark text stays dark; colour
    hues are preserved (uniform per-pixel gain across channels).
    """
    h = min(rgb.shape[0], template.shape[0])
    w = min(rgb.shape[1], template.shape[1])
    rgb = rgb[:h, :w].astype(np.float32)
    gain = 255.0 / np.clip(template[:h, :w], TEMPLATE_FLOOR, 255.0)
    out = np.clip(rgb * gain[:, :, None], 0, 255).astype(np.uint8)
    return out


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
    pw, ph = point_size  # POINTS (1/72"), matching source page — not pixels
    page = out_pdf.new_page(width=pw, height=ph)
    page.insert_image(fitz.Rect(0, 0, pw, ph), stream=buf.tobytes())


def main(argv: list[str]) -> None:
    doc = fitz.open(PDF_IN)
    template = build_template(doc)

    if argv:  # debug mode: write before/after PNGs for given pages
        DEBUG_DIR.mkdir(parents=True, exist_ok=True)
        for p in (int(a) for a in argv):
            rgb = render_page_rgb(doc[p - 1])
            cleaned = remove_watermark(rgb, template)
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
        src_rect = doc[i].rect
        cleaned = remove_watermark(render_page_rgb(doc[i]), template)
        rgb_to_pdf_page(out_pdf, cleaned, (src_rect.width, src_rect.height))
        if (i + 1) % 20 == 0:
            print(f"  cleaned {i + 1}/{n} pages")
    out_pdf.save(PDF_OUT, deflate=True, garbage=4)
    out_pdf.close()
    doc.close()
    print(f"Cleaned PDF -> {PDF_OUT} ({n} pages)")


if __name__ == "__main__":
    main(sys.argv[1:])
