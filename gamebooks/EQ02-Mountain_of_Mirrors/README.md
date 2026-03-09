# Gamebook HTML Conversion — Mountain of Mirrors

## Project Overview

This project converts **Mountain of Mirrors** (TSR Endless Quest Book 2, by Rose Estes, 1983)
into a single-file interactive HTML gamebook. It follows the same method used to convert
**Dungeon of Dread** (Endless Quest Book 1), producing a browser-playable adventure with:

- Clickable "Turn to page N" choices
- Cover page with Begin Adventure button
- Dark mode / font size / save-resume options
- QA validation via Playwright script

The completed Dungeon of Dread conversion (`Dungeon_of_Dread_2026-02-21_0942_CST.html`) is the
**reference implementation** for all style and code decisions.

---

## Book Metadata

| Field | Value |
|---|---|
| Title | Mountain of Mirrors |
| Series | TSR Endless Quest, Book 2 |
| Author | Rose Estes |
| Year | 1983 |
| Publisher | TSR, Inc. |
| Protagonist | Landon, a young elf warrior |
| Setting | Shanafria (Mountain of Mirrors), fantasy world |
| Book page range | 2–153 (152 pages in PDF; book page 1 not in scan) |
| Total PDF pages | 152 |
| First choice | Book page 22 → turn to page 38 or 119 |
| Illustration pages | ~20–25 full-page art pages (no choice text) |

---

## Conversion Method (Successful Steps)

This section documents exactly what was done so future conversions can follow the same process.

### Step 1 — Source Preparation

The source PDF (`Mountain of Mirrors.pdf`) was a 657 MB high-resolution scan (450 DPI)
that had **no embedded text layer** — it is purely image-based.

**Key check:** Use PyMuPDF to confirm whether a text layer exists:
```python
import fitz
doc = fitz.open("book.pdf")
for i in range(min(5, len(doc))):
    print(f"Page {i+1}: {len(doc[i].get_text().strip())} chars")
```
If all pages return 0 chars → image-only PDF → proceed to Step 2.

### Step 2 — Page Image Extraction

Used `extract_pages.py` (included in project) to render all PDF pages as JPEG images.
Settings that worked well:

| Setting | Value | Rationale |
|---|---|---|
| Tool | PyMuPDF (`fitz`) | Already installed; fast and reliable |
| Zoom | 2.0× (≈144 DPI render) | Balances file size and readability |
| JPEG quality | 85 | Good quality, ~270 KB per page |
| Output size | 1190×1684 px | Readable by Claude vision; ~41 MB total |
| Output folder | `pages/` | One file per page: `page_001.jpg`…`page_152.jpg` |

Run: `python extract_pages.py`

**Result:** 152 JPEG files, each clearly readable by Claude's vision.

### Step 3 — Book Structure Analysis

Read key pages using Claude's vision (Read tool on image files):

- Confirmed image quality and readability
- Determined page number mapping: **PDF page N = Book page N+1**
  (PDF starts at book page 2 because book page 1 was not scanned)
- Identified choice format: numbered list + "turn to page N" instructions
- Located first choice point (book page 22)
- Confirmed book page range (2–153)
- Identified illustration-only pages (no text to transcribe)

### Step 4 — HTML Shell Creation

Copy the completed Dungeon of Dread HTML as a base. Modify:

1. `<title>` tag → "Mountain of Mirrors"
2. `#home-section` heading and cover image src (use `mountainofmirrors_cover.png`)
3. Color scheme (optional — Dungeon of Dread uses a warm parchment tone; can adapt
   to a cool icy/silver theme for Mountain of Mirrors if desired)
4. `max` attribute on `#page-jump` input → `153`
5. Replace all section content stubs with placeholder `<section>` blocks for pages 2–153
6. Test that the shell loads, cover shows, and Begin Adventure works

Save as `Mountain_of_Mirrors_SHELL.html` first; rename to final when complete.

### Step 5 — Content Transcription (Multi-Session)

Each session: read ~15 page images using Claude vision, transcribe text, format as HTML sections.

**Section ID = Book page number** (e.g., book page 38 → `id="section-38"`).

Choice links format:
```html
<p class="choice">1. If you want to...,
<a href="#" onclick="goToSection(38); return false;" class="page-link">
turn to page <strong>38</strong></a>.</p>
```

Narrative-continuation pages (no choice — story flows to next page):
```html
<div class="turn-instruction">
  <span class="choice-text">Turn to page
    <a href="#" onclick="goToSection(N+1); return false;" class="page-link">
    <strong>N+1</strong></a></span>
</div>
```

Illustration-only pages — use a simple placeholder:
```html
<div class="section-content">
  <p style="text-align:center; font-style:italic;">[Illustration]</p>
</div>
<div class="turn-instruction">
  <span class="choice-text">Turn to page
    <a href="#" onclick="goToSection(N+1); return false;" class="page-link">
    <strong>N+1</strong></a></span>
</div>
```

Ending pages — use the ending class and a restart prompt:
```html
<p class="ending">THE END</p>
<p style="text-align:center;">
  <button class="control-btn" onclick="goToSection(2)">Try Again</button>
</p>
```

**Recommended transcription session size:** ~15 pages per session
**Recommended model for transcription:** Claude Opus 4.6 (best vision accuracy for 1983 scanned text)

### Step 6 — QA Validation

Run the Playwright-based QA script after all sections are filled in:

```bash
node qa-gamebook-v11.9.0.js --progress --outputLog "Mountain_of_Mirrors.html"
```

Or with visible browser for debugging:
```bash
node qa-gamebook-v11.9.0.js --headed --slowMo=50 "Mountain_of_Mirrors.html"
```

The QA script checks:
- All choice links reach valid sections
- No dead-end sections (other than endings)
- No unreachable sections
- Save/Resume and Restart functionality
- Dark mode and font size controls

Fix any issues reported, then re-run until clean.

---

## Color Scheme Recommendation for Mountain of Mirrors

The book is set on an icy, silver-mirrored mountain. Suggested theme:

| Variable | Light mode | Dark mode |
|---|---|---|
| `--bg-color` | `#cdd6e0` (cool gray-blue) | `#0d1b2a` |
| `--page-bg` | icy white gradient | deep midnight gradient |
| `--link-color` | `#1a5276` (deep blue) | `#7fb3d3` (ice blue) |
| `--button-border` | `#1a5276` | `#7fb3d3` |

(Optional — the Dungeon of Dread warm parchment theme also works perfectly well.)

---

## QA Script Usage Reference

```
node qa-gamebook-v11.9.0.js [options] <path-to-html>

Options:
  --headed              Show browser window
  --progress            Show progress indicator
  --progressEvery=N     Update every N states (default: 25)
  --maxStates=N         Cap exploration states (default: 5000)
  --slowMo=ms           Slow down actions (for debugging)
  --outputLog[=name]    Write results to log file
  --skipExtras          Skip post-BFS tests (faster)
  --minContent=N        Min chars for non-stub detection (default: 40)
  --debug               Verbose logging
```

---

## File Inventory

| File | Description |
|---|---|
| `Mountain of Mirrors.pdf` | Source PDF (657 MB, 152 pages, image-only) |
| `mountainofmirrors_cover.png` | Cover art for HTML home page |
| `pages/page_001.jpg` – `page_152.jpg` | Page images for transcription |
| `extract_pages.py` | Page extraction script (reusable) |
| `qa-gamebook-v11.9.0.js` | QA validation script |
| `Dungeon_of_Dread_2026-02-21_0942_CST.html` | Reference implementation |
| `HANDOFF.md` | Session-to-session progress tracker |
| `README.md` | This file |
| `Mountain_of_Mirrors_SHELL.html` | HTML scaffold (created in Session 2) |
| `Mountain_of_Mirrors.html` | Final output (created after transcription) |

---

## Guide for Future Book Conversions

To convert any new Endless Quest (or similar gamebook) PDF:

1. **Place files** in a new project folder. Include:
   - Source PDF
   - Cover image (PNG)
   - `extract_pages.py`, `qa-gamebook-v11.9.0.js`
   - A completed reference HTML gamebook

2. **Check for text layer** in the PDF using PyMuPDF. If text exists, extraction is much easier.
   If image-only, proceed with the steps below.

3. **Extract pages** using `extract_pages.py`. Adjust `PDF_PATH` and `OUT_DIR`. Run once.

4. **Analyze structure** by reading 10–20 early pages with Claude vision:
   - What page numbers appear in the book?
   - Does PDF page 1 match book page 1 or is there an offset?
   - When does the first choice appear?
   - What format do choices use? ("turn to page N", "go to section N", etc.)

5. **Create the HTML shell** from the reference HTML. Update title, cover, color scheme,
   and section count.

6. **Transcribe content** in batches of ~15 pages per Claude session.
   Use Opus 4.6 for image reading if text quality is critical.

7. **Run QA** and iterate until clean.

8. **Update README** with the new book's metadata and any lessons learned.

---

## Session History

| Session | Date | Model | Accomplishments |
|---|---|---|---|
| 1 | 2026-02-21 | Sonnet 4.6 | Setup, image extraction, structure analysis, HANDOFF + README created |
| 2 | — | — | HTML shell creation (planned) |
| 3–8 | — | Opus 4.6 | Content transcription (planned) |
| 9 | — | Sonnet 4.6 | QA and final polish (planned) |
