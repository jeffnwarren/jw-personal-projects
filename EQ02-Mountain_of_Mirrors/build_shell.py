#!/usr/bin/env python3
"""
build_shell.py
Creates Mountain_of_Mirrors_SHELL.html by adapting Dungeon of Dread's HTML.

Changes made:
  - Title / headings updated
  - Cover image replaced (mountainofmirrors_cover.png embedded as base64)
  - Color scheme → cool icy silver/blue theme
  - localStorage key updated
  - Page jump max updated to 153
  - Home-section start button → goToSection(2)
  - All DoD game sections replaced with stubs for book pages 2-153
"""

import base64
import re
from pathlib import Path

BASE_DIR  = Path(r"c:\Users\jeff\Documents\EQ02-Mountain_of_Mirrors")
DOD_HTML  = BASE_DIR / "Dungeon_of_Dread_2026-02-21_0942_CST.html"
COVER_PNG = BASE_DIR / "mountainofmirrors_cover.png"
OUT_HTML  = BASE_DIR / "Mountain_of_Mirrors_SHELL.html"

# ── 1. Load source ────────────────────────────────────────────────────────────
print("Reading source HTML…")
dod = DOD_HTML.read_text(encoding="utf-8")

# ── 2. Locate structural split points ─────────────────────────────────────────
# Everything before the first game section tag
section_marker = '\n    <section id="section-1"'
script_marker  = '\n    <script>'

sec_idx    = dod.index(section_marker)
script_idx = dod.index(script_marker)

header_raw = dod[:sec_idx]          # CSS + cover + home + options
script_raw = dod[script_idx:]       # JS + </div></body></html>

print(f"  Header portion: {len(header_raw):,} chars")
print(f"  Script portion: {len(script_raw):,} chars")

# ── 3. Embed new cover image ───────────────────────────────────────────────────
print("Encoding cover image…")
cover_b64 = base64.b64encode(COVER_PNG.read_bytes()).decode("ascii")
cover_data_uri = f"data:image/png;base64,{cover_b64}"

# Replace the embedded base64 image src (the huge data URI in the <img> tag)
header = re.sub(r'src="data:image/[^"]{20,}"', f'src="{cover_data_uri}"',
                header_raw, count=1)

# ── 4. Text replacements in header ───────────────────────────────────────────
print("Applying text replacements…")

# Title and headings
header = header.replace("<title>Dungeon of Dread</title>",
                        "<title>Mountain of Mirrors</title>")
header = header.replace("DUNGEON of DREAD", "MOUNTAIN of MIRRORS")
header = header.replace("Dungeon of Dread", "Mountain of Mirrors")

# Cover alt text
header = header.replace("Dungeon of Dread Cover Illustration",
                        "Mountain of Mirrors Cover Illustration")

# Cover click hint text
header = header.replace("Click cover or swipe to begin →",
                        "Click the cover to begin →")

# Page jump max
header = header.replace('max="128"', 'max="153"')

# Home-section start button: section 1 → section 2
header = header.replace('onclick="goToSection(1)"', 'onclick="goToSection(2)"')
header = header.replace(
    "Turn to page <strong>1</strong>",
    "Turn to page <strong>2</strong>")

# ── 5. Color scheme: warm parchment → cool icy silver/blue ───────────────────
# Light theme
header = header.replace("--bg-color: #d4cbb3",
                         "--bg-color: #c5d5e0")
header = header.replace(
    "--page-bg: linear-gradient(to right, #e8e0cc 0%, #f0ead8 5%, #f2ecd9 50%, #f0ead8 95%, #e8e0cc 100%)",
    "--page-bg: linear-gradient(to right, #dce9f3 0%, #eaf4fb 5%, #edf6fd 50%, #eaf4fb 95%, #dce9f3 100%)")
header = header.replace("--text-color: #1a1612",
                         "--text-color: #0d1f2d")
header = header.replace("--link-color: #8B4513",
                         "--link-color: #1a5276")
header = header.replace("--button-bg: #f0ead8",
                         "--button-bg: #d6eaf8")
header = header.replace("--button-border: #8B4513",
                         "--button-border: #1a5276")

# Dark theme
header = header.replace("--bg-color: #1a1a2e",
                         "--bg-color: #0a1628")
header = header.replace(
    "--page-bg: linear-gradient(to right, #16213e 0%, #1a1a2e 5%, #1f1f3a 50%, #1a1a2e 95%, #16213e 100%)",
    "--page-bg: linear-gradient(to right, #071324 0%, #0a1628 5%, #0c1d34 50%, #0a1628 95%, #071324 100%)")
header = header.replace("--text-color: #e0d6c8",
                         "--text-color: #c8dde8")
header = header.replace("--link-color: #d4a574",
                         "--link-color: #7fb3d3")
header = header.replace("--button-bg: #2a2a4a",
                         "--button-bg: #0f2640")
header = header.replace("--button-border: #d4a574",
                         "--button-border: #7fb3d3")

# Cover begin button gradient (warm brown → deep blue)
header = header.replace(
    "background: linear-gradient(135deg, #8B4513 0%, #654321 100%)",
    "background: linear-gradient(135deg, #1a5276 0%, #0e3460 100%)")
header = header.replace(
    "background: linear-gradient(135deg, #654321 0%, #4a2c0f 100%)",
    "background: linear-gradient(135deg, #0e3460 0%, #082440 100%)")
header = header.replace("border: 2px solid #5c3317",
                         "border: 2px solid #1a4a6b")
header = header.replace("color: #f5f5dc",
                         "color: #e8f4fd")

# Misc link/hover colors in cover section
header = header.replace("color: #8B4513;\n    cursor: pointer;",
                         "color: #1a5276;\n    cursor: pointer;")
header = header.replace(
    ".cover-customize-link:hover {\n            color: #8B4513;",
    ".cover-customize-link:hover {\n            color: #1a5276;")

# ── 6. Script replacements ────────────────────────────────────────────────────
script = script_raw

# localStorage key
script = script.replace("dungeonOfDread_progress", "mountainOfMirrors_progress")

# max attribute (in case it appears in JS too)
script = script.replace('max="128"', 'max="153"')

# ── 7. Generate stub sections (book pages 2-153) ──────────────────────────────
print("Generating 152 stub sections (book pages 2-153)…")

def make_stub(n):
    return (
        f'    <section id="section-{n}" class="game-section" data-section="{n}">\n'
        f'        <div class="page-nav page-nav-left" onclick="goToPrevPage()">◀</div>\n'
        f'        <div class="page-nav page-nav-right" onclick="goToNextPage()">▶</div>\n'
        f'        <div class="page-number">{n}</div>\n'
        f'        <div class="section-content">\n'
        f'            <p>[Page {n} — content to be transcribed]</p>\n'
        f'        </div>\n'
        f'        <div class="bookmark-link" style="display: none;"></div>\n'
        f'    </section>'
    )

stubs = "\n\n".join(make_stub(n) for n in range(2, 154))

# ── 8. Assemble and write ─────────────────────────────────────────────────────
print("Assembling output…")
output = header + "\n\n" + stubs + "\n\n" + script

OUT_HTML.write_text(output, encoding="utf-8")

size_mb = OUT_HTML.stat().st_size / 1024 / 1024
print(f"\nShell written: {OUT_HTML.name}")
print(f"  Size: {size_mb:.2f} MB")
print(f"  Total chars: {len(output):,}")
print(f"  Sections: 2-153 (152 stubs)")
print("\nDone! Open Mountain_of_Mirrors_SHELL.html in a browser to verify.")
