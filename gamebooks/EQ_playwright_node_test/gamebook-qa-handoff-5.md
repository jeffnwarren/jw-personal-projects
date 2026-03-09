# Gamebook QA Script — Project Handoff

**Last updated:** 2026-02-22
**Current script version:** v11.11.0
**Gamebook file:** `Dungeon_of_Dread_2026-02-21_0942_CST.html`

---

## Project Overview

An automated Playwright-based QA crawler for a single-file HTML gamebook. The script navigates the book like a real player using Breadth-First Search (BFS), validates every link and navigation path, and runs a suite of post-BFS feature and mobile tests. It is intentionally generic — not hardcoded to Dungeon of Dread — so it will work on future gamebook builds with the same HTML structure.

### Core design principle — production parity

The script's primary obligation is to test the book **as readers actually experience it**, not as it appears when developer tooling is active. Every measurement of layout, visibility, touch targets, and overflow should reflect production state. Where the script must temporarily activate internal tooling (such as `qa-mode`) to reach a specific function, it should scope that activation as narrowly as possible and restore production state immediately after. Tests that measure what readers see should never run while developer tooling is active.

This principle is currently not fully implemented — see the known qa-mode contamination issue in the Implementation Notes section.

---

## Gamebook Structure (Dungeon of Dread)

| Property | Value |
|---|---|
| Format | Single-file HTML (4,358 lines) |
| Sections | 126 game sections (`section.game-section[id^="section-"][data-section]`) |
| Section numbering | Non-contiguous — section 7 is absent; numbers jump from 6 to 8 |
| Starting section | `section-1` (first in sorted DOM order) |

### Key JavaScript globals (all plain scope, accessible via `page.evaluate`)

| Name | Type | Purpose |
|---|---|---|
| `goToSection(n, addToHistory)` | function | Primary navigation |
| `goToNextPage()` / `goToPrevPage()` | function | Linear page-flip |
| `goToCover()` / `goToIntro()` / `goToOptions()` | function | View navigation |
| `restartAdventure()` | function | Clears history, returns to cover (uses `confirm()`) |
| `startFreshAdventure()` | function | Clears history, goes to intro (no confirm) |
| `saveProgress()` / `loadProgress()` / `hasProgress()` | function | localStorage persistence |
| `jumpToPage()` | function | Reads `#page-jump` input, calls `goToSection()` |
| `toggleOption('dark'|'narration'|'qa')` | function | Flips option flags + calls `applyOptions()` |
| `setFontSizeFromSlider(value)` | function | Sets `options.fontSize` (0–4) + calls `applyOptions()` |
| `handleSwipe()` | function | Called by touchend listener; reads `touchStartX`/`touchEndX` |
| `touchStartX` / `touchEndX` | let (number) | Set by touchstart/touchend listeners |
| `updatePageIndicator()` | function | Updates `#page-indicator` text |
| `currentView` | let (string) | `'cover'`, `'home'`, `'options'`, or `'section'` |
| `history` | let (array) | Navigation history stack |
| `sortedSections` | const (array) | Sorted section numbers (mirrors script's `sectionsOrdered`) |
| `totalSections` | const (number) | `sortedSections.length` |
| `options` | let (object) | `{ darkMode, fontSize, narration, qaMode }` |
| `fontSizes` | const (array) | `[{name,size}]` — 15px/17px/19px/21px/23px for positions 0–4 |

### localStorage key
`dungeonOfDread_progress` — JSON with `{ history, lastChoiceSection, currentView, options }`

### Page indicator format
`"Page N (X/Y)"` — N = section number, X = 1-based ordinal in sorted list, Y = total sections.  
Example: `"Page 13 (12/126)"` — section 13 is the 12th in sorted order because section 7 is absent.

### Interactive element selectors

| Selector | Description |
|---|---|
| `.page-link` | Choice links ("Turn to page N") |
| `.page-nav-left` / `.page-nav-right` | Linear page-flip arrows (fixed, 50vh) |
| `.bookmark-btn` | Bottom "Back to page X" button (inside active section) |
| `.bookmark-link` | Wrapper div around `.bookmark-btn` |
| `.control-btn` | Top bar buttons (Restart, Settings, Go) |
| `#page-jump` | Number input for jumpToPage() |
| `#page-indicator` | Span showing current page / ordinal |
| `#back-choice-btn` | Top "Back to page X" button |
| `#toggle-dark` | Dark mode toggle |
| `#font-size-slider` | Range input (0–4, calls `setFontSizeFromSlider`) |

### CSS notes relevant to QA
- `@media (max-width: 560px)` repositions `.page-nav-left` to `left: 5px` and `.page-nav-right` to `right: 5px`
- Above 560px: arrows at `calc(50% - 270px)` from each edge
- `--font-size` CSS variable controls body font size
- `[data-theme="dark"]` on `<html>` enables dark mode
- `overflow: hidden` on `.page` (not body) — horizontal overflow check targets `document.documentElement`

---

## Script Architecture

### Runtime switches

| Flag | Default | Purpose |
|---|---|---|
| `--headed` | off | Show browser window |
| `--progress` | off | Print dots during BFS |
| `--progressEvery=N` | 10 | Dot frequency |
| `--slowMo=ms` | 0 | Playwright action delay |
| `--timeoutMs=ms` | 1500 | Navigation wait timeout |
| `--maxStates=N` | 5000 | BFS safety cap |
| `--debug` | off | Verbose state logging |
| `--skipExtras` | off | Skip post-BFS tests 1–6 |
| `--skipMobile` | off | Skip mobile test suite 12–17 (v11.10.0 only) |
| `--keepQaMode` | off | *(not yet implemented)* Keep `qa-mode` active throughout the entire run, including mobile layout tests. Use when you want to QA the qa-mode experience itself (arrows, breadcrumb, jump input) rather than the production reader experience. Without this flag, the intended future behaviour is that `qa-mode` is stripped before any layout-sensitive test and restored only when explicitly needed. |
| `--minContent=N` | 40 | Stub detection threshold (0 = disable) |
| `--outputLog[=name]` | off | Write log to .txt file |

### Key internal data structures

| Name | Type | Contents |
|---|---|---|
| `model` | object | Built from DOM: `sectionNums`, `allIds`, `linksBySection`, `endingWithLinks`, `deadEndSections`, `shortContentSections` |
| `sectionsOrdered` | string[] | Section IDs sorted by section number |
| `nextMap` / `prevMap` | Map | DOM-order linear navigation |
| `outDegree` | Map | Section ID → array of link target IDs |
| `visitedSectionIds` | Set | Section IDs ever active during BFS |
| `checkedIndicator` | Set | Section IDs whose indicator has been verified |
| `testedBottomBookmark` | Set | Section IDs whose bottom bookmark click has been tested |
| `failures` | array | Hard failures (cause non-zero exit) |
| `notes` | array | Informational findings (do not affect exit code) |

### BFS state shape
```js
{ at: "section-N", lastChoice: "section-M" | null, path: ["section-A", ...] }
```
State key: `"section-N|section-M"` (or `"section-N|null"`). Duplicate keys are skipped.

### Exit codes
- `0` — no failures
- `2` — one or more failures
- `1` — script error (thrown exception)

---

## All Checks Implemented

### Static checks (before BFS, no browser navigation)

| ID | Type | Description | Result type |
|---|---|---|---|
| S1 | Duplicate section IDs | Two `section.game-section` elements with the same `id` | FAILURE |
| S2 | Broken link targets | `.page-link` points to a section ID not in the DOM | FAILURE |
| S3 | Ending + links hybrid | Section has `.ending` class AND `.page-link` choices | FAILURE |
| S4 | Dead-end sections | No `.page-link` choices AND no `.ending` class | NOTE |
| S5 | Short-content stubs | Section visible text < `--minContent` chars | NOTE |
| S6 | Link text vs target mismatch | Prose says "page X" but link fires `goToSection(Y)` | FAILURE |
| S7 | Missing `.page-number` div | Game section has no `.page-number` child element | NOTE |
| S8 | Section number gaps | Numbers absent in range `[1..max]` (intentional or accidental) | NOTE |

### Runtime checks (collected throughout the entire run)

| ID | Type | Description | Result type |
|---|---|---|---|
| R1 | Uncaught JS exception | `page.on('pageerror')` fires during any phase | FAILURE |
| R2 | Console error | `page.on('console')` with type `"error"` during any phase | FAILURE |

### BFS checks (run during traversal, once per section or state)

| ID | Type | Description | Result type |
|---|---|---|---|
| B1 | Page indicator — section number | `#page-indicator` contains `"Page N"` after navigation | FAILURE |
| B2 | Page indicator — ordinal | `(X/Y)` ordinal matches section's position in sorted list | FAILURE |
| B3 | Page indicator — total | `(X/Y)` total matches `sectionsOrdered.length` | FAILURE |
| B4 | Page indicator — ordinal missing | `(X/Y)` part absent entirely | NOTE |
| B5 | Bottom bookmark visibility | Visible iff `lastChoice` is set | FAILURE |
| B6 | Bottom bookmark text | Shows `"Back to page N"` where N = `lastChoiceSection` | FAILURE |
| B7 | Bottom bookmark click | Clicking it navigates to the correct section | FAILURE |
| B8 | Top back button state | Disabled before first choice, enabled after | FAILURE |

### Post-BFS checks (after BFS completes, before extra tests)

| ID | Type | Description | Result type |
|---|---|---|---|
| P1 | Unreachable sections | Section in DOM never reached during BFS | FAILURE |
| P2 | Coverage summary | All-sections-reached confirmation | NOTE |

### Extra tests (skippable with `--skipExtras`)

| # | Name | Description | Result type |
|---|---|---|---|
| 1 | Save / Resume | Navigate to choice section → reload → verify resume at same section | FAILURE |
| 2 | Restart / goToCover | `restartAdventure()` returns to cover view, indicator = "Cover" | FAILURE |
| 3 | goToSection validity | Valid mid-book jump lands correctly; `goToSection(99999)` doesn't crash | FAILURE |
| 4 | jumpToPage() — valid | Sets `#page-jump` input, calls function, verifies landing | FAILURE |
| 5 | jumpToPage() — invalid | Input `99999` triggers alert, no navigation | FAILURE / NOTE |
| 6 | jumpToPage() — empty | Empty input does nothing | FAILURE |
| 7 | Dark mode toggle ON | `toggleOption('dark')` sets `data-theme="dark"` | FAILURE |
| 8 | Dark mode toggle OFF | Second call removes `data-theme` | FAILURE |
| 9 | Dark mode font regression | `--font-size` unchanged by dark toggle | FAILURE |
| 10 | Font slider — all positions | `setFontSizeFromSlider(0–4)` sets correct `--font-size` px values | FAILURE |

### Mobile test suite (v11.10.0+ only, skippable with `--skipMobile`)

| # | Name | Description | Result type |
|---|---|---|---|
| 12 | Viewport meta | `width=device-width` present; no `user-scalable=no` or `maximum-scale=1` | FAILURE / NOTE |
| 13 | Horizontal overflow portrait | `scrollWidth <= innerWidth` at 390px for first/mid/last sections | FAILURE |
| 14 | Touch target sizes | All interactive elements ≥ 44×44px (Apple HIG minimum) | NOTE |
| 15a | Swipe right-to-left | Sets globals + calls `handleSwipe()`; advances one page | FAILURE |
| 15b | Swipe left-to-right | Goes back one page | FAILURE |
| 15c | Swipe sub-threshold | 30px swipe does not navigate | FAILURE |
| 15d | Real TouchEvent dispatch | Dispatches genuine `TouchEvent` on `hasTouch` context | NOTE |
| 16 | Landscape layout | No overflow + nav arrows in bounds at 844×390 | FAILURE |
| 17 | iOS input zoom | `#page-jump` computed `font-size` ≥ 16px | NOTE |

> **Mobile coverage gap:** All mobile tests navigate to game sections only. The Options panel (`#options-section`), cover, and intro views are never measured for overflow, touch targets, or element visibility. A real-device screenshot (on file) shows the font slider row layout breaking at 390px — the `A+` label is clipped off-screen and the label column collapses vertically. This is undetected by any current check. See Suggested Next Additions for the proposed fix.

---

## Version History

| Version | Key additions |
|---|---|
| v11.7.1 | Baseline: BFS traversal, link validation, bookmark UI checks, bottom bookmark click test |
| v11.8.0 | Unreachable section detection, ending+links check, stub detection, page indicator (number only), save/resume, restart test, goToSection validity |
| v11.9.0 | Dead-end detection, jumpToPage() tests (3 cases), dark mode smoke test, font slider smoke test |
| v11.10.0 | Full mobile test suite (tests 12–17), `--skipMobile` flag |
| v11.10.1 | Page indicator ordinal + total verification (the `(X/Y)` part) |
| v11.11.0 | JS console error detection, link text vs target mismatch (S6), section gap report (S8), missing .page-number div (S7) |

---

## Suggested Next Additions

These were identified but not yet implemented, in priority order.

> **Phase 1 complete (v11.11.0, 2026-02-22).** The following items from the original high/medium priority lists have been implemented: JavaScript console error detection, link text vs target mismatch, section number gap report, missing .page-number div check. See the "All Checks Implemented" section for details.

### High priority

**Feature presence audit** *(static, runs before BFS)*  
The current script assumes every feature exists and tests whether it works. It never checks whether a feature has been silently removed by an AI editing session or manual cleanup. This is the check that would catch the narration situation described below.

The audit has two sides — verifying that intended features are present, and verifying that removed features are genuinely absent. Both are equally important: a feature that was supposed to be removed but wasn't (like qa-mode) is just as much a bug as a feature that was supposed to stay but was deleted (like the narration toggle).

**Side A — Features that must be present:**

The audit is a DOM + JS scope inspection run once at startup, before BFS begins. For each major feature it checks that the expected HTML elements are in the DOM and that the expected JavaScript functions and state are accessible.

| Feature | Expected HTML elements | Expected JS functions | Expected state |
|---|---|---|---|
| Narration controls | `#narration-controls`, `#narration-play`, `#narration-pause`, `#narration-stop` | `narrate()`, `narrationPlay()`, `narrationPause()`, `narrationStop()` | `options.narration` property, `speechSynth` not null |
| Narration toggle in Options | `[onclick*="toggleOption('narration')"]` in `#options-section` | — | — |
| Dark mode | `#toggle-dark` in `#options-section` | `toggleOption` | `options.darkMode` property |
| Font size | `#font-size-slider`, `#font-size-preview` | `setFontSizeFromSlider` | `options.fontSize` property |
| Save / Resume | — | `saveProgress`, `loadProgress`, `hasProgress` | localStorage key accessible |
| Restart | `.control-btn[onclick*="restartAdventure"]` | `restartAdventure`, `goToCover` | — |
| Page indicator | `#page-indicator` | `updatePageIndicator` | — |
| Section content | `.section-content` inside every game section | — | — |
| Page number display | `.page-number` inside every game section | — | — |

**Side B — Removed features that must be absent:**

These elements and functions were intentionally removed from the production book. Their presence should be treated as a `DEAD_CODE` failure — it means a previous editing session reintroduced something that was deliberately cleaned up.

| Removed feature | Should NOT exist in DOM | Should NOT exist in JS scope |
|---|---|---|
| qa-mode toggle | `#toggle-qa`, `[onclick*="toggleOption('qa')"]` in `#options-section` | `options.qaMode` property |
| Page-flip arrows | `.page-nav-left`, `.page-nav-right` inside any `.game-section` | — |
| Breadcrumb trail | `#breadcrumb`, `#breadcrumb-trail` | `updateBreadcrumb` function |
| Jump-to-page input | `#page-jump`, `.qa-only` | `jumpToPage` function |
| qa-mode CSS | `body.qa-mode` rules in any `<style>` block | — |

> **Known current state:** All of the "should NOT exist" items above are still present in the current book HTML. See the "qa-mode dead code" known issue section for the complete inventory and removal plan.

> **Known current issue — narration is orphaned:** A previous AI editing session removed the narration toggle from the Options panel. The play/pause/stop buttons (`#narration-controls`) and all underlying JavaScript are still fully present, but users have no UI path to enable narration. The feature presence audit would flag this as: `FEATURE_MISSING: narration toggle not found in #options-section`. Fix: restore the narration option row in the Options section HTML.

**Link text vs. target mismatch** *(static, no browser needed)*  
The most common undetected OCR error. If the surrounding prose says "Turn to page 14" but the `onclick` fires `goToSection(15)`, the reader is silently sent to the wrong place. Implementation: for each `.page-link`, read the `.choice-text` parent text, extract the mentioned number with a regex, compare to the link's `data-target` or `onclick` target. Pure DOM walk during model build.

**Back button click test** *(extra test)*  
The BFS verifies `#back-choice-btn` is enabled/disabled correctly but never actually clicks it. Implementation: navigate to a section via a real choice (so `lastChoiceSection` is set), then `click()` `#back-choice-btn` and verify `activeId()` equals `lastChoiceSection`. Tests the one navigation interaction currently exercised only by state assertions, not by real interaction.

**JavaScript console error detection** *(BFS + extras)*  
Attach `page.on('pageerror', ...)` and `page.on('console', msg => ...)` listeners at startup and collect any uncaught JS exceptions or `console.error` calls during the entire run. Errors that don't manifest as visible navigation failures can still cause subtle state corruption. Implementation: register listeners before BFS begins, accumulate in an array, report as FAILURE items after BFS. Cheap to add, high diagnostic value.

### Medium priority

**Single-choice sections** *(static)*  
Sections with exactly ONE `.page-link` are suspicious in a gamebook — not zero (dead-end, already detected), not two+ (real choice), just one. This is the pattern when OCR captures only one of two options from a page. Implementation: during model build, flag any section where `linksBySection.get(id).length === 1`. Report as NOTE since some single-option sections are legitimate.

**Options panel mobile layout** *(mobile test, medium priority)*  
The mobile test suite navigates exclusively to game sections. The Options panel (`#options-section`) is never loaded during any mobile check, meaning its layout is completely untested at 390px. Observed on a real Android device (screenshots on file):

- The `.option-row` flex layout breaks at narrow widths — the label column ("Font Size" / "Adjust text size for comfort") stacks into a tall narrow vertical block on the left, forcing the slider container into a cramped right column
- The `A+` max-size label on the font slider is clipped off the right edge and not visible at all
- The slider thumb visual position may not match the displayed setting text ("Settings: Medium Font") — worth verifying this is a rendering timing issue vs. a genuine state mismatch

None of this is caught by the current overflow or touch target checks because those tests call `bootFresh()` and `ensureAtSection()`, which always land in a game section, never the options view.

Implementation: add a dedicated Options panel mobile pass to the mobile suite — call `goToOptions()`, wait for the section to become active, then run overflow, touch target, and element-visibility checks specifically on `#options-section`. Check that `#font-size-slider`, both `A-` and `A+` labels, and the dark mode toggle are all within viewport bounds and not clipped. The `A+` clip issue is almost certainly a `max-width` or `overflow: hidden` on the slider container that needs a responsive fix in the book's CSS.

**Scroll-to-top verification** *(BFS, low overhead)*  
The book calls `window.scrollTo({top: 0})` after every navigation. If this fails, readers see the bottom of the previous section rather than the top of the new one — silent but disorienting. Implementation: during BFS, after each navigation, check `window.scrollY === 0`. The multi-step sequences BFS creates are exactly when this could fail. Negligible cost since it is a single property read per state.

**Options persistence across reload** *(extra test)*  
The save/resume test proves navigation state survives a reload but never checks that options survive. Implementation: enable dark mode via `toggleOption('dark')`, call `saveProgress()`, reload the page, verify `data-theme="dark"` is still applied. Catches the case where options are saved correctly but `applyOptions()` is not called on load.

**Reachable endings check** *(post-BFS)*  
Cross-reference `visitedSectionIds` with the set of `.ending` sections collected during model build. If zero endings are reachable the book is unwinnable. Also report how many distinct endings are reachable — a book with only one reachable outcome despite complex branching is a sign of broken links. Implementation: add `endingSections` to the model, filter against `visitedSectionIds` after BFS.

**Section number gap report** *(static, informational)*  
The script knows which section IDs exist but never reports which numbers are absent. For a book numbered 1–126 with gaps, "Missing section numbers: 7, 23, 45" helps distinguish intentional omissions (section 7 in Dungeon of Dread) from accidental deletions. Implementation: after model build, compute the max section number and compare `[1..max]` against known section numbers. Report as NOTEs.

**Missing `.page-number` div** *(static)*  
Each section should contain a `.page-number` div. Sections missing it render without a visible page number, breaking the reader's spatial orientation. Implementation: `s.querySelector('.page-number')` for each section during model build. Report as NOTE.

**Keyboard navigation** *(extra test)*  
The book has `ArrowRight`, `ArrowLeft`, and `Home` key handlers. These are currently completely untested. Implementation: `page.keyboard.press('ArrowRight')` from section 1 (verify advance), `ArrowLeft` from mid-book (verify retreat), `Home` from a game section (verify cover view).

**Axe accessibility audit** *(extra test)*  
Inject `axe-core` from the Cloudflare CDN and run `await axe.run()` on a sample of sections. Flags WCAG violations including ARIA misuse, missing labels, focus management, and color contrast failures — none of which the current script detects. Implementation:
```js
await page.addScriptTag({ url: 'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.9.1/axe.min.js' });
const results = await page.evaluate(() => axe.run());
// results.violations contains structured WCAG findings
```

### Lower priority

**Narration smoke test** *(extra test — restore toggle first)*  
The narration JS is fully intact but the Options toggle that enables it was removed by a previous AI editing session (see Feature Presence Audit above). Once the toggle is restored, a smoke test should verify: `toggleOption('narration')` flips `options.narration` to `true`, the `#narration-controls` div gets the `.visible` class, and a second call restores both. No audio testing — just that the enable/disable lifecycle works end-to-end. Mock `window.speechSynthesis` as a spy to confirm `speak()` is called when narration is active and `cancel()` is called when it is stopped.

**goToIntro() / goToOptions() navigation** *(extra test)*  
Both are currently untested. Call each, verify indicator shows `"Intro"` or `"Options"` respectively, no game section active.

**Duplicate link targets within a section** *(static)*  
Two `.page-link` elements in the same section pointing to the same target is almost always an OCR duplication. Cosmetic/content issue rather than a navigation bug.

**Word count per section** *(static)*  
More meaningful than character count alone. A section with 5 words is suspicious even if it exceeds 40 characters. Add `text.trim().split(/\s+/).filter(Boolean).length` alongside the existing char count, flag sections below ~15 words as NOTE.

---

## Future Considerations — Automated Human Playthrough

The current script validates *structure* (does every link go somewhere?) and *mechanics* (does every button do what it claims?). What it cannot do is simulate what a human reader actually *experiences* — reading the prose, looking at the page, making choices based on narrative context, and noticing when something feels wrong. The approaches below, ordered from easiest to most ambitious, would extend QA in that direction.

---

### 1. Playwright Trace and Video Recording

**Complexity: Low. Value: High for debugging and stakeholder demos.**

Playwright has built-in support for trace capture and video recording with no additional dependencies.

```js
// Video: records entire run as .mp4
const context = await browser.newContext({ recordVideo: { dir: 'videos/' } });

// Trace: captures screenshots, network, console, DOM snapshots at every step
await context.tracing.start({ screenshots: true, snapshots: true });
// ... run BFS ...
await context.tracing.stop({ path: 'trace.zip' });
// View with: npx playwright show-trace trace.zip
```

The trace viewer shows a timeline of every navigation, what was on screen at each moment, and any console errors — essentially a visual replay of the entire QA run. Particularly useful for debugging failures that are hard to reproduce interactively, and for showing non-technical stakeholders what the automation is actually doing.

---

### 2. Screenshot Regression Testing

**Complexity: Low. Value: Catches visual regressions that functional tests miss entirely.**

Playwright's `toHaveScreenshot()` takes a screenshot on first run and saves it as a baseline. On subsequent runs it diffs pixel-by-pixel and fails if the change exceeds a configurable threshold.

```js
// First run: generates baseline .png files in a __screenshots__ folder
// Subsequent runs: compares against baseline and fails on visual change
await expect(page).toHaveScreenshot(`section-${n}.png`, { maxDiffPixelRatio: 0.02 });
```

A practical implementation would capture one screenshot per section during BFS. Baseline images are committed to version control alongside the script. Any time the gamebook HTML is regenerated from a new OCR pass, running the script immediately surfaces which sections changed visually — layout shifts, font changes, missing images, dark mode bleeding, anything that does not break navigation but does break the reading experience. Expected changes can be approved by deleting the baseline for that section.

---

### 3. BFS Path Transcript Export

**Complexity: Low. Value: High for authors reviewing book structure.**

The BFS already traverses every path. With a small addition the script could write a human-readable Markdown or JSON file showing the complete branching tree:

```
Section 1
  → "Turn to page 2" → Section 2
      → "Turn to page 14" → Section 14 [ENDING]
      → "Turn to page 23" → Section 23
          → ...
  → (linear flip) → Section 2
```

This gives the author a complete map of the book's narrative structure without opening a browser. It makes immediately obvious when a branch leads to a dead end, when sections are only reachable via one specific chain, or when the book is shallower than intended despite having many sections. Implementation: accumulate the tree during BFS using the `path` already present in each state, then render as indented Markdown.

---

### 4. AI-Powered Content QA via Claude API

**Complexity: Medium. Value: Very high — the only approach that can actually "read" the pages.**

This is the most powerful option for catching errors the current script fundamentally cannot: wrong words, garbled sentences, truncated paragraphs, OCR artifacts, and mismatched narrative context. The gamebook's inner text is already accessible via `page.evaluate()`. Sending it to the Claude API with targeted prompts can answer questions no structural test can:

- **OCR artifact detection:** "Does this text contain obviously garbled words, character substitutions (l→1, O→0, rn→m), or mid-word line breaks that suggest OCR conversion errors?"
- **Link text verification:** "The prose says 'Turn to page X'. Does X match the actual link target Y? If not, which is likely correct based on narrative context?"
- **Truncation detection:** "Does this text end naturally, or does it feel cut off mid-sentence or mid-paragraph?"
- **Tone consistency:** "Does this section feel stylistically consistent with a fantasy adventure gamebook aimed at young readers?"

A practical implementation would run as a separate optional pass after BFS (`--aiReview` flag), sending each section's text to the API and collecting findings as NOTEs. The cost is one API call per section — 126 calls for this book — which at current API pricing is inexpensive. This catches the *silent wrong*: the section where the prose says "Turn to page 14" but the link fires `goToSection(15)`, and both 14 and 15 exist in the DOM, so no structural test fails. Only reading the text can catch it.

---

### 5. LLM-Guided Narrative Playthrough

**Complexity: Medium. Value: Discovers what a first-time reader actually experiences.**

BFS covers everything systematically but in an arbitrary order no real player would follow. An LLM-guided playthrough takes a different approach: at each choice section, send the section's text and available choices to the Claude API and ask it to make a natural decision — the choice a typical reader would make first. Follow that path, backtrack, try the next choice, and build a tree of natural-feeling playthroughs.

This surfaces a different class of issues:
- Sections only reachable via an implausible sequence of choices, which contain errors BFS catches but no human tester would ever find organically
- Narrative discontinuities that only appear when sections are traversed in story order rather than graph order
- Choices where one option is obviously dominant, suggesting the "wrong" branch may have been accidentally broken and never noticed

The output is a set of complete, readable adventure transcripts — "Player chose to attack → page 14 → fled → page 23 → encountered dragon → page 67..." — that a human reviewer can read to confirm the narrative makes sense end-to-end. This is also highly demonstrable to stakeholders who want to understand what the book's playthroughs actually look like.

---

### 6. Narration / Speech Synthesis Verification

**Complexity: Medium. Value: Confirms audio narration is wired correctly without needing audio hardware.**

> **Note:** The narration toggle in the Options panel was removed by a previous AI editing session. The underlying JS (`narrate`, `narrationPlay`, `narrationPause`, `narrationStop`, `prepareTextForNarration`, `speechSynth`) is fully intact, as are the control buttons (`#narration-controls`). The feature just has no UI path to enable it. Restore the toggle row in `#options-section` before pursuing this verification approach.

The book has a narration toggle. Testing actual audio output is impractical in headless Playwright. However, the Web Speech API can be mocked: replace `window.speechSynthesis` with a spy object that records what it was asked to speak, then verify the utterance text matches the active section's content.

```js
await page.evaluate(() => {
  window._narrationLog = [];
  window.speechSynthesis = {
    speak: (u) => { window._narrationLog.push(u.text); },
    cancel: () => {},
    pause: () => {},
    resume: () => {},
  };
});
// Enable narration, navigate to a section, then verify:
const log = await page.evaluate(() => window._narrationLog);
// log[0] should contain the section's text
```

This verifies the narration engine calls `speechSynthesis.speak()` with the right content, that cancel/pause/resume are wired up, and that navigating away stops narration — all without audio hardware or output.

---

### 7. Axe Accessibility Audit

**Complexity: Low. Value: Catches a whole class of issues the current script ignores.**

`axe-core` is the industry-standard accessibility testing library. A single `axe.run()` call on a loaded section catches color contrast failures (the current dark mode test only verifies `data-theme` is set, not whether the resulting colors are actually readable), missing ARIA labels, images without `alt` text, interactive elements unreachable by keyboard, and form inputs without associated labels (relevant to `#page-jump`). Implementation requires only `page.addScriptTag()` and a `page.evaluate()` call — no new Playwright features.

---

### 8. Real Device Testing

**Complexity: High. Value: Confirms actual rendering on physical hardware.**

Playwright can connect to a real Android device running Chrome with USB debugging enabled via Chrome DevTools Protocol:

```js
const browser = await chromium.connectOverCDP('http://localhost:9222');
```

This runs the same script against real hardware, confirming touch targets work with an actual finger, swipe gestures fire from real touch hardware, fonts render correctly on physical screens, and performance is acceptable on mid-range devices — not just a fast desktop CPU running a headless simulation. Requires an Android device with USB debugging enabled and `adb` installed on the host.

---

### 9. Performance Timing

**Complexity: Low. Value: Catches rendering slowdowns before readers notice them.**

Measure how long each `goToSection()` call takes to result in the new section becoming active. Flag any section exceeding a configurable threshold (e.g. 500ms). Unlikely to be a problem today but valuable insurance as the book grows — more sections, more base64-embedded illustrations, and more script complexity can all compound into noticeable navigation lag on lower-end devices.

```js
const t0 = await page.evaluate(() => performance.now());
// navigate...
const t1 = await page.evaluate(() => performance.now());
if (t1 - t0 > THRESHOLD_MS) { /* flag it */ }
```

Essentially free to add alongside existing BFS navigation, producing a useful per-section performance profile as a byproduct of the run.

---

### Summary Table

| Approach | Complexity | What it catches |
|---|---|---|
| Trace + video recording | Low | Visual state at every step; debugging; stakeholder demos |
| Screenshot regression | Low | Layout shifts and visual regressions between builds |
| BFS path transcript | Low | Full branching structure for author review |
| AI content QA (Claude API) | Medium | OCR errors, prose truncation, link-text mismatches |
| LLM-guided playthrough | Medium | Narrative continuity; natural first-player experience |
| Narration mock verification | Medium | Speech API wiring without audio hardware |
| Axe accessibility audit | Low | WCAG violations, color contrast, ARIA, focus management |
| Real device testing | High | Actual hardware rendering and physical touch behavior |
| Performance timing | Low | Navigation latency per section |

---

## Implementation Notes

### Starting a new session
The transcript of this conversation is available if Claude needs to review earlier context. Ask Claude to use the `recent_chats` or `conversation_search` tool to locate the gamebook QA conversation.

### File locations (within the project folder)
```
your-project-folder/
├── Dungeon_of_Dread_2026-02-21_0942_CST.html          ← gamebook
├── qa-gamebook-v11.11.0.js                             ← latest script
├── docs/
│   └── ai-interaction-lessons.md                       ← AI interaction learning doc
└── old_qa_js_versions/                                 ← archived previous versions
```

### Running the script
```powershell
# Basic run
node qa-gamebook-v11.11.0.js "Dungeon_of_Dread_2026-02-21_0942_CST.html"

# With progress dots and log file
node qa-gamebook-v11.11.0.js --progress --outputLog "Dungeon_of_Dread_2026-02-21_0942_CST.html"

# Fast run (BFS only, no extras or mobile)
node qa-gamebook-v11.11.0.js --skipExtras --skipMobile --progress "Dungeon_of_Dread_2026-02-21_0942_CST.html"

# Visual debugging
node qa-gamebook-v11.11.0.js --headed --slowMo=100 --progress "Dungeon_of_Dread_2026-02-21_0942_CST.html"
```

> **Note:** `--skipMobile` was added in v11.10.0. It is not present in v11.10.1 (which branched from v11.9.0 to add only the indicator fix). If you want both the ordinal check and the mobile suite, the two sets of changes need to be merged into a single file.

### Known book characteristics that affect QA output
- **Section 7 is absent.** This is intentional (absent in the original printed book). The BFS will not flag it as unreachable because it simply does not exist in the DOM.
- **Section 111 is absent.** This is a **bug, not intentional** — sections 110 and 111 were accidentally merged into a single section (currently numbered 112). Needs to be split and renumbered. Discovered by the S8 section gap check in v11.11.0.
- **All section numbers are off by one.** The original book's page 1 was converted to an "Intro" page early in the project, shifting all subsequent section numbers. The intent is to restore original page numbering so section numbers match the printed book's passage numbers. This is a gamebook content fix, not a QA script issue.
- **Some sections have no `.page-link` choices** by design (they rely on linear page-flip navigation). The dead-end check (S4) will note these. Verify each one manually to confirm it was intentional.
- **`confirm()` dialogs.** `restartAdventure()` calls `window.confirm()`. The restart test mocks `window.confirm = () => true` before calling it. The jumpToPage invalid-input test uses Playwright's `page.once('dialog', ...)` handler.

> **Gamebook content fixes are tracked separately.** The section renumbering and 110/111 split are HTML book edits, not QA script changes. They should be done in a separate session using the original PDF or JPEG page images as reference. After the book is corrected, re-run the QA script to validate.

### Known book issue — qa-mode dead code not fully removed from production HTML

The decision to remove qa-mode from the reader-facing book was made but only partially executed. The Options panel toggle row was commented out, but the underlying HTML, CSS, and JavaScript were all left in place. The full inventory of what remains:

**HTML — 254 live DOM nodes that should not exist in production:**

| Element | Count | Location |
|---|---|---|
| `.page-nav-left` / `.page-nav-right` divs | 252 (2 × 126 sections) | Inside every game section |
| `#breadcrumb` div + `#breadcrumb-trail` span | 2 | Fixed position, top of body |
| `#page-jump` label + input + Go button | 3 | Controls bar, `qa-only` group |
| `#toggle-qa` (commented out but still parsed) | 1 | Options section |

**CSS — 12+ rule blocks that should be removed:**
`.qa-only`, `.breadcrumb`, `.breadcrumb:hover`, `.breadcrumb-link`, `.breadcrumb-link:hover`, `body.qa-mode .breadcrumb`, `body:not(.qa-mode) .breadcrumb`, `body.qa-mode .page-nav`, `body:not(.qa-mode) .page-nav`, `.page-nav`, `.page-nav:hover`, `.page-nav.disabled`, `.page-nav-left`, `.page-nav-right`, `@media (max-width: 560px)` nav rules, `.page-input`

**JavaScript — functions and state that should be removed:**
- `options.qaMode` property from the options object and everywhere it is read
- The `'qa'` case in `toggleOption()`
- `'toggle-qa': options.qaMode` in `applyOptions()`
- `if (options.qaMode) parts.push('QA Mode')` in the options summary builder
- `updateBreadcrumb()` function and all three call sites (lines ~4128, ~4156, ~4260)
- `jumpToPage()` function
- `goToNextPage()` and `goToPrevPage()` functions **can stay** — they are called by the swipe handler (`handleSwipe()`) and keyboard handler (`ArrowRight`/`ArrowLeft`), so they serve a real purpose even without the arrows in the DOM

**Why this matters beyond tidiness:**
- The 252 arrow divs add real DOM weight — two fixed-position elements per section, all present in memory even when hidden
- `options.qaMode` is written to and read from localStorage, meaning qa-mode state can theoretically persist across sessions
- The `body.qa-mode` CSS rules are exactly why `bootFresh()` in the QA script accidentally reveals the arrows — if these rules are removed, that contamination problem disappears entirely
- Any future AI editing session that sees `qa-mode` in the code may reintroduce it, not realising it was intentionally removed

**Impact on the QA script if this is cleaned up:**
The QA script currently depends on two qa-mode features:

1. `document.body.classList.add("qa-mode")` in `bootFresh()` — used to ensure QA-mode CSS is active. **If qa-mode CSS is removed from the book, this line becomes a no-op and can simply be deleted from the script.**
2. `jumpToPage()` extra test — relies on `#page-jump` existing. **If `#page-jump` is removed from the book, extra test 4 will fail to find the element and should be updated to skip gracefully with a NOTE rather than failing.**

The `goToSection()` direct calls throughout the BFS and extra tests are unaffected — they never relied on qa-mode.

---

**What happens:** `bootFresh()` adds `qa-mode` to `document.body` on every page load throughout the entire run, including the mobile test suite. This is required for the BFS jump-to-page mechanism and breadcrumb visibility, but it has an unintended side effect on layout.

**The CSS rules involved:**
```css
body:not(.qa-mode) .page-nav { display: none; }   /* production: arrows hidden */
body.qa-mode       .page-nav { display: block; }   /* qa-mode:    arrows shown  */
```

The page-flip arrows (`.page-nav-left`, `.page-nav-right`) are **intentionally hidden in production** — readers navigate by swiping on mobile or using keyboard arrow keys on desktop. They are only shown in qa-mode to give the QA script a clickable target during BFS. This is correct behaviour for BFS navigation, but it means the script is testing a visually different page than what real users see.

**Observed symptom:** Running with `--headed` on Windows shows the gray left/right arrows on every section. Those arrows are not visible to real readers — the script is revealing them by adding `qa-mode`.

**Tests affected:**
- **Touch target audit (mobile test 14):** `.page-nav` elements appear in the measurement pass and get flagged as undersized, which is accurate for qa-mode but irrelevant to production layout.
- **Horizontal overflow checks (mobile test 13):** Two additional fixed-position elements are in the DOM that real users never see. Unlikely to affect overflow measurements but technically incorrect.
- **Landscape layout check (mobile test 16):** The arrow position check measures arrows that are hidden in production. Results are still valid for verifying the CSS positioning logic, but the premise is slightly off.
- **Screenshot regression (future):** Any baseline screenshots captured with `qa-mode` active would not match what readers see. Baselines would need to be captured without the class.

**Why a simple on/off `--qaMode` flag is not the right fix:**  
The need for `qa-mode` is not uniform across the script — it varies by test:

| Test category | Needs qa-mode? | Reason |
|---|---|---|
| BFS navigation | No | Uses `goToSection()` directly; never clicks arrows |
| Extra test 4 (jumpToPage) | Yes | `#page-jump` input is only visible in qa-mode |
| Extra test 2 (restart) | No | `restartAdventure()` is always accessible |
| Mobile layout tests 13, 14, 16 | No — actively harmed | Must measure production state |
| Swipe tests 15a–15d | No | Uses `handleSwipe()` directly; arrows irrelevant |

A single flag that's either on or off for the whole run would force a choice: either contaminate all layout tests, or break the jumpToPage test. Neither is acceptable.

**The correct fix — surgical scoping (not yet implemented):**  
`qa-mode` should be added only when a specific test requires it, and stripped immediately before any test that measures production layout:

```js
// Before mobile layout tests — measure production state
await page.evaluate(() => document.body.classList.remove('qa-mode'));

// ... run mobile tests 13, 14, 16 ...

// Before jumpToPage test — restore qa-mode so #page-jump is visible
await page.evaluate(() => document.body.classList.add('qa-mode'));

// ... run jumpToPage test ...

// Strip again if more layout tests follow
await page.evaluate(() => document.body.classList.remove('qa-mode'));
```

Since BFS itself only uses `goToSection()` and never clicks arrows, `qa-mode` could be removed from `bootFresh()` entirely and added only at the specific points where it is genuinely needed. This would make production parity the default throughout the run.

**The `--keepQaMode` flag (proposed, not yet implemented):**  
There is a legitimate separate use case for running the entire script with `qa-mode` permanently active: when you want to QA the qa-mode experience itself — confirming the arrows position correctly, the breadcrumb updates, and the jump input works together as a coherent developer tool. This is a different test objective from "does the book work for readers" and should be explicitly opt-in via `--keepQaMode`. Without the flag, production parity should be the default.

---

## README Outline (when ready to write)

The script has grown into a full QA framework and needs a proper README separate from this internal handoff. The handoff is a "state of the project" document — what exists, what's broken, what's next. The README is a "how to use this tool" document for anyone picking up the script cold.

### Suggested README structure

**Header**
- Script name, current version, one-sentence description
- Badge-style summary: number of checks, test phases, supported book structure

**What it does**
- The layered test architecture explained simply:
  - Phase 1 — Static analysis (before any browser navigation)
  - Phase 2 — BFS traversal (every reachable path)
  - Phase 3 — Post-BFS structural checks (coverage, unreachables)
  - Phase 4 — Extra tests (features, save/resume, UI functions)
  - Phase 5 — Mobile suite (layout, touch, swipe, landscape)
- What BFS means and why it matters for gamebooks specifically
- What the script cannot catch (content correctness, prose errors — requires AI review)

**Requirements**
- Node.js (link to nodejs.org)
- Playwright install commands — currently buried in the script header, should be front and center:
  ```powershell
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
  npm init -y
  npm i -D playwright
  npx playwright install
  ```

**Usage**
- Basic syntax: `node qa-gamebook-vX.X.X.js [flags] "path/to/Gamebook.html"`
- Common run patterns with explanations:
  ```powershell
  # Full run with log file
  node qa-gamebook-v11.11.0.js --progress --outputLog "Gamebook.html"

  # Fast structural check only
  node qa-gamebook-v11.11.0.js --skipExtras --skipMobile "Gamebook.html"

  # Visual debugging
  node qa-gamebook-v11.11.0.js --headed --slowMo=100 "Gamebook.html"

  # Mobile layout focus
  node qa-gamebook-v11.11.0.js --skipExtras "Gamebook.html"
  ```

**All CLI flags** (table: flag, default, purpose) — same as in this handoff but presented as primary reference

**Reading the output**
- Exit codes: 0 = clean, 2 = failures found, 1 = script error
- Failure types and what each means:

| Type | Meaning | Typical cause |
|---|---|---|
| `SECTION` | Duplicate section ID | HTML editing error |
| `LINK` | Broken link target | OCR miss or editing error |
| `ENDING` | Ending section also has choices | Structural inconsistency |
| `COVERAGE` | Section unreachable from start | Missing link somewhere in the book |
| `INDICATOR` | Page indicator wrong | `updatePageIndicator()` bug |
| `UI` | Bookmark or back button mismatch | UI state logic bug |
| `SWIPE` | Swipe navigation not working | `handleSwipe()` regression |
| `MOBILE_META` | Viewport tag problem | Accessibility or scaling issue |
| `MOBILE_OVERFLOW` | Horizontal scroll at 390px | CSS layout bug |
| `MOBILE_LAYOUT` | Nav element out of bounds | CSS positioning regression |
| `FEATURE_MISSING` | Expected feature absent | AI editing session removed it |
| `DEAD_CODE` | Removed feature still present | AI editing session reintroduced it |

- Note types and when to ignore vs. investigate:
  - `DEAD_END` — usually intentional; verify manually
  - `STUB` — short content; may be a real section or OCR artifact
  - `TOUCH_TARGET` — inline links almost always fail 44px; known limitation
  - `COVERAGE` note — all sections reached; good

**Gamebook HTML requirements**
- What structure the script expects (so it works on future books, not just Dungeon of Dread):
  - Sections: `section.game-section[id^="section-"][data-section]`
  - Choice links: `.page-link` with `onclick="goToSection(N)"` or `data-target`
  - Page indicator: `#page-indicator` with text format `"Page N (X/Y)"`
  - Bookmark: `.bookmark-btn` inside each section
  - Global JS functions: `goToSection`, `goToNextPage`, `goToPrevPage`, `goToCover`
  - Optional but tested if present: `saveProgress`, `hasProgress`, `restartAdventure`, `jumpToPage`, `toggleOption`, `setFontSizeFromSlider`, `handleSwipe`

**Known limitations**
- Does not test content correctness (prose, OCR quality) — use AI review for that
- qa-mode contamination affects mobile layout tests (see implementation notes)
- Touch target audit will flag inline `.page-link` elements as too small — this is a known book design tradeoff, not a script bug
- BFS explores all reachable sections but in graph order, not story order — narrative continuity issues require LLM-guided playthrough

**Version changelog** (condensed from this handoff's version history table)

---

*End of handoff document.*
