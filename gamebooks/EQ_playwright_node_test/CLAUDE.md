# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Automated Playwright QA crawler for single-file HTML gamebooks. Navigates using BFS (Breadth-First Search), validates all links/navigation paths, and runs post-BFS feature and mobile tests. Intentionally generic — works on any gamebook with the same HTML structure, not just Dungeon of Dread.

## Setup

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
npm init -y
npm i -D playwright
npx playwright install
```

## Running the Script

```bash
# Full run
node qa-gamebook-v11.11.0.js "Dungeon_of_Dread_2026-02-21_0942_CST.html"

# With progress dots and log file
node qa-gamebook-v11.11.0.js --progress --outputLog "Dungeon_of_Dread_2026-02-21_0942_CST.html"

# Fast (BFS + structural checks only)
node qa-gamebook-v11.11.0.js --skipExtras --skipMobile --progress "Dungeon_of_Dread_2026-02-21_0942_CST.html"

# Visual debugging
node qa-gamebook-v11.11.0.js --headed --slowMo=100 --progress "Dungeon_of_Dread_2026-02-21_0942_CST.html"
```

**Exit codes:** `0` = clean, `2` = failures found, `1` = script error.

## CLI Flags

| Flag | Default | Purpose |
|---|---|---|
| `--headed` | off | Show browser window |
| `--progress` | off | Print dots during BFS |
| `--progressEvery=N` | 10 | Dot frequency |
| `--slowMo=ms` | 0 | Playwright action delay |
| `--timeoutMs=ms` | 1500 | Navigation wait timeout |
| `--maxStates=N` | 5000 | BFS safety cap |
| `--debug` | off | Verbose state logging |
| `--skipExtras` | off | Skip post-BFS tests 1–10 |
| `--skipMobile` | off | Skip mobile tests 12–17 |
| `--minContent=N` | 40 | Stub detection threshold (0 = disable) |
| `--outputLog[=name]` | off | Write log to .txt file |

## Architecture

### Script Execution Flow

1. **Parse CLI args** → `parseArgs()`
2. **Build DOM model** (static analysis) — reads all sections, links, and structure without browser navigation
3. **Static checks (S1–S5)** — duplicate IDs, broken links, ending+links conflicts, dead-ends, stubs
4. **BFS traversal (B1–B8)** — explores all reachable states, checks page indicator and bookmark UI at each step
5. **Post-BFS checks (P1–P2)** — unreachable section detection
6. **Extra tests (1–10)** — save/resume, restart, goToSection, jumpToPage, dark mode, font slider
7. **Mobile suite (12–17)** — viewport meta, overflow, touch targets, swipe, landscape, iOS input zoom
8. **Print results and exit**

### Key Internal Data Structures

| Name | Type | Contents |
|---|---|---|
| `model` | object | Built from DOM: `sectionNums`, `allIds`, `linksBySection`, `endingWithLinks`, `deadEndSections`, `shortContentSections` |
| `sectionsOrdered` | string[] | Section IDs sorted by section number |
| `nextMap` / `prevMap` | Map | DOM-order linear navigation |
| `outDegree` | Map | Section ID → array of link target IDs |
| `visitedSectionIds` | Set | Section IDs ever active during BFS |
| `failures` | array | Hard failures (cause non-zero exit) |
| `notes` | array | Informational findings (do not affect exit code) |

### BFS State Shape

```js
{ at: "section-N", lastChoice: "section-M" | null, path: ["section-A", ...] }
```
State key: `"section-N|section-M"` (or `"section-N|null"`). Duplicate keys are skipped.

## Gamebook HTML Structure (What the Script Expects)

- **Sections:** `section.game-section[id^="section-"][data-section]`
- **Choice links:** `.page-link` with `onclick="goToSection(N)"` or `data-target`
- **Page indicator:** `#page-indicator` with format `"Page N (X/Y)"`
- **Bookmark:** `.bookmark-btn` inside each section
- **Required JS globals:** `goToSection`, `goToNextPage`, `goToPrevPage`, `goToCover`
- **Optional JS globals (tested if present):** `saveProgress`, `hasProgress`, `restartAdventure`, `jumpToPage`, `toggleOption`, `setFontSizeFromSlider`, `handleSwipe`

## Known Issue: qa-mode Contamination

`bootFresh()` adds `body.qa-mode` throughout the entire run, including mobile tests. This reveals hidden page-flip arrows (`.page-nav-left`/`.page-nav-right`) that real readers never see, affecting touch target audits and overflow checks. The fix is surgical scoping: strip `qa-mode` before layout tests, restore only for `jumpToPage` test. Not yet implemented — see `gamebook-qa-handoff-5.md` for full details.

## Current Book: Dungeon of Dread

- 126 sections, non-contiguous (section 7 is intentionally absent)
- Starting section: `section-1`
- localStorage key: `dungeonOfDread_progress`
- Page indicator format: `"Page N (X/Y)"` — e.g. `"Page 13 (12/126)"` (section 13 is 12th because section 7 is absent)

## Current Script Version

`qa-gamebook-v11.11.0.js` — see `gamebook-qa-handoff-5.md` for full version history, all implemented checks, suggested next additions, and known issues.
