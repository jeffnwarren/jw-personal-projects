# HANDOFF — Mountain of Mirrors HTML Gamebook Conversion

_Updated each session. Resume here when starting a new Claude session._

> **MODEL NOTE:** Claude Code does NOT auto-switch models. Before transcription sessions,
> manually switch to Opus 4.6 by typing `/model claude-opus-4-6` in the chat.
> Use Sonnet 4.6 for structural/code sessions (QA, shell edits, etc.).

---

## Project Goal
Convert the TSR Endless Quest book **Mountain of Mirrors** (Book 2, by Rose Estes, 1983)
into a single-file interactive HTML gamebook, matching the style and functionality of the
already-completed **Dungeon_of_Dread_2026-02-21_0942_CST.html**.

---

## Current Status — Session 1 Complete (Setup + Shell DONE)

### What Has Been Done
- [x] Extracted all 152 PDF pages as JPEG images (1190×1684 px, ~270 KB each) into `pages/`
- [x] Read key pages to understand book structure
- [x] Created `extract_pages.py` script (reusable for future books)
- [x] Created `HANDOFF.md` (this file) and `README.md`
- [x] Created `build_shell.py` script — adapts DoD HTML to Mountain of Mirrors
- [x] Built `Mountain_of_Mirrors_SHELL.html` (0.29 MB, 152 stub sections, verified)
- [ ] Content transcription — **NOT YET STARTED**

### Next Action (Start of Session 2)
**Begin transcribing book pages 2–22** (PDF pages 001–021) into the shell.
- Use **Claude Opus 4.6** for better vision accuracy on scanned text
- Open `Mountain_of_Mirrors_SHELL.html` and start filling in sections 2–22
- The opening narrative (pages 2–21) has no choices — use `turn-instruction` divs
- Page 22 has the FIRST CHOICE: turn to page 38 or 119

---

## Critical Book Structure Notes

| Item | Value |
|---|---|
| PDF pages | 152 |
| Book page range | 2 – 153 (page 1 not in PDF) |
| PDF page → book page | PDF page N = book page (N + 1) |
| HTML section IDs | Must match book page numbers (sections 2 – 153) |
| Max section number | 153 |
| First choice point | Book page 22: "turn to page 38" or "turn to page 119" |
| Last page (good ending example) | Book page 153 — "The End. Go back to the beginning." |
| Cover image available | `mountainofmirrors_cover.png` (921×576 px) |
| Illustration pages | ~20–25 full-page art pages (no text to transcribe) |
| Text-only pages | ~128–130 pages |

**Page mapping rule:**
```
book_page  = pdf_page_number + 1
pdf_page   = book_page - 1
page_file  = pages/page_{pdf_page:03d}.jpg
```
Examples:
- Book page 38  → PDF page 37  → `pages/page_037.jpg`
- Book page 119 → PDF page 118 → `pages/page_118.jpg`
- Book page 153 → PDF page 152 → `pages/page_152.jpg`

**Book page 1 is missing from the PDF.** Likely the inside front cover or title page.
No choice link in the book says "turn to page 1" so this is safe to omit.
The game starts at section 2.

---

## Recommended Model for Content Sessions

| Task | Recommended Model |
|---|---|
| HTML shell creation | Claude Sonnet 4.6 (current model is fine) |
| Page transcription (vision) | **Claude Opus 4.6** — better accuracy reading 1983 scanned text |
| QA and fixes | Claude Sonnet 4.6 |

Use Opus for any session that involves reading page images and transcribing text.
Use Sonnet for structural/code work (shell, JS, fixes).

---

## Full Staged Plan

### Phase 0 — Setup (Session 1 — COMPLETE)
- [x] Extract PDF pages as images
- [x] Analyze book structure
- [x] Create HANDOFF.md and README.md

### Phase 1 — HTML Shell (Session 1 — COMPLETE)
- [x] Copy Dungeon of Dread HTML as base template (via `build_shell.py`)
- [x] Replace title, cover image, color scheme (icy blue theme)
- [x] Set section max to 153 in Go-to input
- [x] Stub all 152 sections (book pages 2–153) with placeholder text
- [x] Verified: 12/12 checks pass; 152 sections range 2–153
- [x] Saved as: `Mountain_of_Mirrors_SHELL.html` (0.29 MB)

### Phase 2 — Transcription Batch 1: Book pages 2–22 (Session 2 or 3)
PDF pages 001–021 (the opening narrative + first choice)
- [ ] Read page images with Claude vision
- [ ] Transcribe text into HTML sections
- [ ] Format "turn to page N" as `<a href="#" onclick="goToSection(N); return false;">`
- [ ] Mark illustration pages with `[ILLUSTRATION]` placeholder
- [ ] Update section 2 as the "begin adventure" entry point

### Phase 3 — Transcription Batch 2: Book pages 23–52 (Session 3 or 4)
PDF pages 022–051

### Phase 4 — Transcription Batch 3: Book pages 53–82 (Session 4 or 5)
PDF pages 052–081

### Phase 5 — Transcription Batch 4: Book pages 83–112 (Session 5 or 6)
PDF pages 082–111

### Phase 6 — Transcription Batch 5: Book pages 113–133 (Session 6 or 7)
PDF pages 112–132

### Phase 7 — Transcription Batch 6: Book pages 134–153 (Session 7 or 8)
PDF pages 133–152

### Phase 8 — QA and Polish (Session 8 or 9)
- [ ] Run `node qa-gamebook-v11.9.0.js --progress "Mountain_of_Mirrors.html"`
- [ ] Fix all dead links, broken navigation, and missing sections
- [ ] Review text quality (typos, OCR errors)
- [ ] Set final filename with timestamp

---

## Session Log

### Session 1 — 2026-02-21
**Model:** Claude Sonnet 4.6
**Accomplished:**
- Analyzed project scope
- Confirmed PDF is image-only (no text layer) — OCR required
- Extracted all 152 pages as JPEG (zoom=2.0, ~270 KB/page, ~41 MB total)
- Confirmed image quality is excellent for Claude vision transcription
- Read pages 1–21 (book pages 2–22) and last 3 pages (151–153)
- Identified first choice point (book page 22)
- Created extract_pages.py, HANDOFF.md, README.md

**Key pages read this session:**
- Book pages 2–22 (PDF 001–021): opening linear narrative, no choices until page 22
- Book page 22: first choice → page 38 or page 119
- Book page 151 (PDF 150): near-final narrative page (good ending)
- Book page 152 (PDF 151): illustration
- Book page 153 (PDF 152): final page, ending text + "The End"

**Also completed:**
- Built `build_shell.py` — adapts DoD HTML for Mountain of Mirrors
- Built and verified `Mountain_of_Mirrors_SHELL.html` (0.29 MB, 152 stubs)

---

## HTML Section Template

Each section follows this pattern:

```html
<section id="section-N" class="game-section" data-section="N">
    <div class="page-nav page-nav-left" onclick="goToPrevPage()">◀</div>
    <div class="page-nav page-nav-right" onclick="goToNextPage()">▶</div>
    <div class="page-number">N</div>
    <div class="section-content">
        <p>Text of the page here...</p>
        <p class="choice">1. <a href="#" onclick="goToSection(X); return false;" class="page-link">Turn to page <strong>X</strong></a></p>
        <p class="choice">2. <a href="#" onclick="goToSection(Y); return false;" class="page-link">Turn to page <strong>Y</strong></a></p>
    </div>
    <div class="bookmark-link" style="display: none;"></div>
</section>
```

For pages with no choice (narrative continues to next page):
```html
    <div class="turn-instruction">
        <span class="choice-text">Turn to page <a href="#" onclick="goToSection(N+1); return false;" class="page-link"><strong>N+1</strong></a></span>
    </div>
```

For ending pages:
```html
    <p class="ending">THE END</p>
```

For illustration-only pages, use a simple placeholder:
```html
    <div class="section-content">
        <p style="text-align:center; font-style:italic;">[Illustration]</p>
    </div>
    <div class="turn-instruction">
        <span class="choice-text">Turn to page <a href="#" onclick="goToSection(N+1); return false;" class="page-link"><strong>N+1</strong></a></span>
    </div>
```

---

## Files in Project

| File | Description |
|---|---|
| `Mountain of Mirrors.pdf` | Source PDF (657 MB, 152 pages, image-only) |
| `mountainofmirrors_cover.png` | Cover art (921×576 px) |
| `pages/page_001.jpg` – `page_152.jpg` | Extracted page images for transcription |
| `extract_pages.py` | Script to re-extract pages if needed |
| `qa-gamebook-v11.9.0.js` | QA validation script (Playwright-based) |
| `Dungeon_of_Dread_2026-02-21_0942_CST.html` | Reference implementation |
| `HANDOFF.md` | This file |
| `README.md` | Project documentation |
| `Mountain_of_Mirrors_SHELL.html` | HTML scaffold (to be created in Session 2) |
| `Mountain_of_Mirrors.html` | Final output (to be created after transcription) |

---

## How to Resume This Project

1. Open a new Claude Code session in this directory
2. Tell Claude: "Resume the Mountain of Mirrors HTML gamebook conversion. Read HANDOFF.md for current status."
3. Claude reads this file, sees current phase, and continues from where we left off
4. After the session, update the Session Log above and check off completed items

---

## Transcription Progress Tracker

Track which book pages have been transcribed into the HTML.

| Book Pages | PDF Pages | Status | Notes |
|---|---|---|---|
| 2–22 | 001–021 | ⬜ Not started | Opening narrative + first choice |
| 23–52 | 022–051 | ⬜ Not started | |
| 53–82 | 052–081 | ⬜ Not started | |
| 83–112 | 082–111 | ⬜ Not started | |
| 113–133 | 112–132 | ⬜ Not started | |
| 134–153 | 133–152 | ⬜ Not started | Includes final endings |
