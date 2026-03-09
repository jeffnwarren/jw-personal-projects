#!/usr/bin/env python3
"""
extract_pages.py
Extracts each page of Mountain of Mirrors.pdf as a JPEG image
for use with Claude vision-based transcription.

Output: pages/page_001.jpg ... pages/page_152.jpg
Resolution: zoom=2.0 (~144 DPI) gives ~1190x1684 px — readable and compact
"""

import fitz  # PyMuPDF
import os

PDF_PATH = r"c:\Users\jeff\Documents\EQ02-Mountain_of_Mirrors\Mountain of Mirrors.pdf"
OUT_DIR  = r"c:\Users\jeff\Documents\EQ02-Mountain_of_Mirrors\pages"
ZOOM     = 2.0          # 144 DPI — change to 3.0 for higher quality
QUALITY  = 85           # JPEG quality (1-100)
START    = 1            # First page to extract (1-based)
END      = None         # Last page to extract; None = all pages

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    doc = fitz.open(PDF_PATH)
    total = len(doc)
    end = END if END else total

    print(f"PDF: {total} pages")
    print(f"Extracting pages {START}-{end} -> {OUT_DIR}")
    print(f"Zoom: {ZOOM}x  Quality: {QUALITY}")
    print()

    mat = fitz.Matrix(ZOOM, ZOOM)

    for page_num in range(START - 1, end):
        page = doc[page_num]
        pix  = page.get_pixmap(matrix=mat, alpha=False)

        filename = f"page_{page_num + 1:03d}.jpg"
        out_path = os.path.join(OUT_DIR, filename)
        pix.save(out_path, jpg_quality=QUALITY)

        size_kb = os.path.getsize(out_path) / 1024
        print(f"  [{page_num + 1:3d}/{end}] {filename}  {pix.width}x{pix.height}  {size_kb:.0f} KB")

    doc.close()
    print(f"\nDone. {end - START + 1} pages extracted to {OUT_DIR}")

if __name__ == "__main__":
    main()
