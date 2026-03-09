//------------------------------------------
// qa-gamebook-v11.9.js
//
// REQUIREMENTS:
// Install Node.js from https://nodejs.org/en/download
// Create a new folder for node project.
// Launch Windows PowerShell and navigate to the newly-created project folder.
// Run the following commands:
//		Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
//		npm init -y
//		npm i -D playwright
//		npx playwright install
// Copy the gamebook html (e.g. Dungeon_of_Dread_Final_2026-02-20_0727_CST.html) and latest qa_gamebook-<version>.js file (e.g. qa-gamebook-v11.9.0.js) to the project folder.
//
// PURPOSE:
// Automated QA crawler for single-file HTML gamebooks (generic; not specific to Dungeon of Dread).
// Uses Playwright to navigate the book like a real player and validate:
//  - Choice links ("Turn to page X")
//  - Linear page-flip navigation (DOM order)
//  - Bottom bookmark UI ("Back to page X")
//  - Unreachable sections (never visited during BFS)
//  - Dead-end sections (no links out, no .ending class)
//  - Ending sections with unexpected choice links
//  - Short-content sections (stub detection)
//  - #page-indicator text accuracy
//  - Save/Resume (localStorage round-trip)
//  - Restart/goToCover behaviour
//  - goToSection() validity (valid and out-of-range inputs)
//  - jumpToPage() UI function (valid input, invalid/out-of-range, empty)
//  - Dark mode toggle (data-theme attribute, CSS variable)
//  - Font size slider (--font-size CSS variable across all 5 positions)
//
// WHAT IS BFS?
// BFS = Breadth-First Search. In this script, that means we explore the gamebook state-space
// level-by-level using a queue, so we systematically cover all reachable paths without
// getting stuck going deep down a single branch.
//
// NEW IN v11.8:
//  1. Unreachable section detection: any section in the DOM that BFS never visits is flagged.
//  2. Ending sections with unexpected links: a section with the CSS class "ending" should never
//     also contain .page-link choices.
//  3. Short-content detection: sections with fewer than MIN_CONTENT_CHARS characters of text.
//  4. Page indicator accuracy: verifies #page-indicator text after each navigation.
//  5. Save/Resume round-trip: verifies localStorage save/load across a page reload.
//  6. Restart test: verifies restartAdventure() returns to cover view.
//  7. goToSection validity: tests valid jump and graceful handling of out-of-range input.
//
// NEW IN v11.9:
//  8. Dead-end section detection: sections with no outgoing .page-link choices AND no .ending
//     class marker. These sections leave the reader stranded with no visible exit. Flagged as
//     DEAD_END notes (not failures, since some may be intentional single-passage sections, but
//     the absence of an .ending class is almost always an oversight).
//  9. jumpToPage() validation: sets the #page-jump input to a valid section number and confirms
//     the engine navigates there correctly. Then tests an out-of-range number (expects a dialog)
//     and an empty input (expects no navigation change). Dialogs are captured and dismissed
//     automatically without stalling headless mode.
// 10. Dark mode smoke test: calls toggleOption('dark') and verifies data-theme="dark" is applied
//     to <html>. Toggles again and verifies the attribute is removed. Also checks that the
//     --font-size CSS variable is still intact after the toggle (regression guard).
// 11. Font slider smoke test: iterates all 5 slider positions (0-4 = X-Small through X-Large),
//     calls setFontSizeFromSlider() for each, and verifies that the --font-size CSS variable
//     changes to the expected pixel value. Then restores the original position.
//
// RUNTIME SWITCHES (optional):
//
//   --progress
//       Prints a simple progress indicator so you know the script is alive.
//       By default this prints a dot (.) every N states.
//
//   --progressEvery=<N>
//       Controls how often progress is printed.
//       Example: --progressEvery=10  (prints every 10 states)
//       Default: 25
//
//   --headed
//       Runs Playwright in non-headless mode.
//       Opens a visible Chromium window so you can watch page flips and navigation.
//
//   --slowMo=<ms>
//       Slows down Playwright actions (in milliseconds).
//       Useful with --headed for visually debugging navigation.
//       Example: --slowMo=50
//
//   --timeoutMs=<ms>
//       Overrides default wait timeouts for navigation and page activation.
//       Example: --timeoutMs=3000
//
//   --maxStates=<N>
//       Hard cap on how many BFS states will be explored.
//       Acts as a safety valve for very large or unexpectedly looping books.
//
//   --outputLog[=<n>]
//       Writes console output to a log file in the directory you run the script from.
//       If <n> is omitted, a meaningful default name is generated with a Central-time
//       timestamp and CST/CDT abbreviation (DST-aware).
//
//   --debug
//       Enables verbose logging of navigation paths and state transitions.
//       Noisy, but useful when diagnosing a specific failure.
//
//   --skipExtras
//       Skips the post-BFS tests (save/resume, restart, goToSection validity).
//       Use this for faster runs when you only need the BFS coverage checks.
//
//   --minContent=<N>
//       Minimum character count for section text content before flagging as a stub.
//       Default: 40.  Set to 0 to disable the check.
//
// USAGE:
//   node qa-gamebook-v11.9.js [flags] "C:\path\to\YourGamebook.html"
//
// Example:
//   node qa-gamebook-v11.9.js --headed --progress --slowMo=50 --outputLog "C:\path\to\YourGamebook.html"
//   node qa-gamebook-v11.9.js --skipExtras --progress "C:\path\to\YourGamebook.html"
//
// NOTES:
// - Does NOT rely on window.goToSection being globally exposed.
// - Linear navigation follows DOM order, not numeric adjacency.
// - Bookmark visibility is evaluated ONLY within the active section.
// - The save/resume test uses whatever the book's own saveProgress()/hasProgress() expose.
//   If those functions are not globally accessible, the test is skipped with a note.
// - The restart test mocks window.confirm = () => true to bypass the confirmation dialog.
//------------------------------------------
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

// -----------------------------------------
// CLI options
function parseArgs(argv) {
  const opts = {
    headed: false,
    progress: false,
    progressEvery: 25,
    maxStates: 5000,
    slowMo: 0,
    timeoutMs: 1500,
    outputLog: false,
    debug: false,
    skipExtras: false,
    minContent: 40,
  };
  const positional = [];
  for (const a of argv) {
    if (!a.startsWith("--")) { positional.push(a); continue; }
    if (a === "--headed" || a === "--showBrowser") { opts.headed = true; continue; }
    if (a === "--progress") { opts.progress = true; continue; }
    if (a === "--debug") { opts.debug = true; continue; }
    if (a === "--outputLog") { opts.outputLog = true; continue; }
    if (a === "--skipExtras") { opts.skipExtras = true; continue; }
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) {
      const k = m[1];
      const v = m[2];
      if (k === "progressEvery") opts.progressEvery = Math.max(1, parseInt(v, 10) || opts.progressEvery);
      if (k === "maxStates") opts.maxStates = Math.max(1, parseInt(v, 10) || opts.maxStates);
      if (k === "slowMo") opts.slowMo = Math.max(0, parseInt(v, 10) || 0);
      if (k === "timeoutMs") opts.timeoutMs = Math.max(100, parseInt(v, 10) || opts.timeoutMs);
      if (k === "minContent") opts.minContent = Math.max(0, parseInt(v, 10) || 0);
      if (k === "outputLog") opts.outputLog = (v === "" ? true : v);
      if (k === "headless") opts.headed = (String(v).toLowerCase() === "false");
      continue;
    }
  }
  return { opts, positional };
}

function toFileUrl(p) {
  const abs = path.resolve(p);
  if (!fs.existsSync(abs)) throw new Error(`File not found: ${abs}`);
  return "file:///" + abs.replace(/\\/g, "/");
}

function numFromSectionId(id) {
  const m = String(id).match(/section-(\d+)/);
  return m ? parseInt(m[1], 10) : null;
}

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}


function makeLogger(outputLogOpt, bookFilePath) {
  if (!outputLogOpt) {
    return {
      writeLine: (s) => console.log(s),
      writeRaw: (s) => process.stdout.write(String(s)),
      close: () => {}
    };
  }

  const dt = new Date();
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Chicago",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
    timeZoneName: "short",
  }).formatToParts(dt);

  const get = (type) => (parts.find(p => p.type === type)?.value || "");
  const yyyy = get("year"); const mm = get("month"); const dd = get("day");
  const hh = get("hour"); const min = get("minute");
  const tz = get("timeZoneName").replace(/\s+/g, "");

  const bookBase = bookFilePath ? path.basename(bookFilePath, path.extname(bookFilePath)) : "run";
  function sanitize(name) { return String(name).replace(/[<>:"/\\|?*\x00-\x1F]/g, "_").trim(); }

  let filename;
  if (outputLogOpt === true) {
    filename = `qa_${sanitize(bookBase)}_${yyyy}-${mm}-${dd}_${hh}${min}_${tz}.txt`;
  } else {
    filename = String(outputLogOpt);
    if (!filename.toLowerCase().endsWith(".txt")) filename += ".txt";
    filename = sanitize(filename);
  }

  const fullPath = path.resolve(process.cwd(), filename);
  function appendLine(s) { try { fs.appendFileSync(fullPath, s, { encoding: "utf8" }); } catch {} }

  const orig = {
    log: console.log, error: console.error, warn: console.warn,
    out: process.stdout.write.bind(process.stdout),
    err: process.stderr.write.bind(process.stderr),
  };

  function normalizeArgs(args) {
    return args.map(a => {
      if (typeof a === "string") return a;
      try { return JSON.stringify(a, null, 2); } catch { return String(a); }
    }).join(" ");
  }

  console.log = (...args) => { orig.log(...args); appendLine(normalizeArgs(args) + "\n"); };
  console.error = (...args) => { orig.error(...args); appendLine("ERROR: " + normalizeArgs(args) + "\n"); };
  console.warn = (...args) => { orig.warn(...args); appendLine("WARN: " + normalizeArgs(args) + "\n"); };

  orig.log(`(logging to ${fullPath})`);
  appendLine(`(logging to ${fullPath})\n`);

  process.stdout.write = (chunk, encoding, cb) => {
    orig.out(chunk, encoding, cb);
    try { fs.appendFileSync(fullPath, String(chunk), { encoding: "utf8" }); } catch {}
    return true;
  };
  process.stderr.write = (chunk, encoding, cb) => {
    orig.err(chunk, encoding, cb);
    try { fs.appendFileSync(fullPath, String(chunk), { encoding: "utf8" }); } catch {}
    return true;
  };

  return {
    writeLine: (s) => console.log(s),
    writeRaw: (s) => process.stdout.write(String(s)),
    close: () => {
      try {
        console.log = orig.log; console.error = orig.error; console.warn = orig.warn;
        process.stdout.write = orig.out; process.stderr.write = orig.err;
      } catch {}
    }
  };
}


(async () => {
  const { opts, positional } = parseArgs(process.argv.slice(2));
  const filePath = positional[0];
  if (!filePath) {
    console.error('Usage: node qa-gamebook-v11.9.js [--headed] [--progress] [--skipExtras] [--minContent=40] [--progressEvery=25] [--maxStates=5000] [--slowMo=0] [--timeoutMs=1500] [--outputLog[=<n>]] "C:\\path\\to\\Gamebook.html"');
    process.exit(1);
  }

  const logger = makeLogger(opts.outputLog, filePath);
  process.on("exit", () => { try { logger.close(); } catch {} });
  process.on("SIGINT", () => { try { logger.close(); } catch {} process.exit(130); });

  const url = toFileUrl(filePath);

  const browser = await chromium.launch({ headless: !opts.headed, slowMo: opts.slowMo });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

  const failures = [];
  const notes = [];

  await page.goto(url, { waitUntil: "load" });

  // -----------------------------------------
  // Build section model from DOM
  // Also collects: endingWithLinks, shortContentSections
  const model = await page.evaluate((minContent) => {
    const sections = Array.from(document.querySelectorAll("section.game-section[id^='section-'][data-section]"));
    const sectionNums = sections
      .map(s => ({ id: s.id, n: parseInt(s.dataset.section, 10) }))
      .filter(x => Number.isFinite(x.n))
      .sort((a, b) => a.n - b.n);

    const linksBySection = new Map();
    for (const s of sections) {
      const links = Array.from(s.querySelectorAll(".page-link"))
        .map(a => {
          const dt = a.getAttribute("data-target");
          if (dt) return dt;
          const oc = a.getAttribute("onclick") || "";
          const m = oc.match(/goToSection\((\d+)\)/);
          return m ? `section-${m[1]}` : null;
        })
        .filter(Boolean);
      linksBySection.set(s.id, links);
    }

    const allIds = new Set(sectionNums.map(x => x.id));

    // NEW v11.8: Ending sections that also have choice links (should be impossible)
    const endingWithLinks = [];
    for (const s of sections) {
      const isEnding = s.classList.contains("ending") || !!s.querySelector(".ending");
      const links = s.querySelectorAll(".page-link");
      if (isEnding && links.length > 0) {
        endingWithLinks.push({ id: s.id, linkCount: links.length });
      }
    }

    // NEW v11.9: Dead-end sections — no outgoing .page-link choices AND no .ending class.
    // These leave the reader with no visible exit path (can't choose, and not marked as an ending).
    // Common causes: OCR missed the "Turn to page X" line, or an .ending class was forgotten.
    const deadEndSections = [];
    for (const s of sections) {
      const hasLinks = (linksBySection.get(s.id) || []).length > 0;
      const isEnding = s.classList.contains("ending") || !!s.querySelector(".ending");
      if (!hasLinks && !isEnding) {
        deadEndSections.push(s.id);
      }
    }

    // NEW v11.8: Sections with suspiciously little text content (potential OCR stubs)
    const shortContentSections = [];
    if (minContent > 0) {
      for (const s of sections) {
        // Exclude images and script/style noise; get visible text only
        const clone = s.cloneNode(true);
        for (const el of clone.querySelectorAll("script, style, img")) el.remove();
        const text = (clone.textContent || "").replace(/\s+/g, " ").trim();
        if (text.length < minContent) {
          shortContentSections.push({ id: s.id, len: text.length, preview: text.slice(0, 60) });
        }
      }
    }

    return {
      sectionNums,
      allIds: Array.from(allIds),
      linksBySection: Array.from(linksBySection.entries()),
      endingWithLinks,
      deadEndSections,
      shortContentSections,
    };
  }, opts.minContent);

  const allIds = new Set(model.allIds);
  const sectionsOrdered = model.sectionNums.map(x => x.id);

  // Linear navigation maps (DOM order)
  const nextMap = new Map();
  const prevMap = new Map();
  for (let i = 0; i < sectionsOrdered.length; i++) {
    const id = sectionsOrdered[i];
    if (i > 0) prevMap.set(id, sectionsOrdered[i - 1]);
    if (i < sectionsOrdered.length - 1) nextMap.set(id, sectionsOrdered[i + 1]);
  }

  // -----------------------------------------
  // Static integrity checks
  {
    const seen = new Set();
    for (const s of model.sectionNums) {
      if (seen.has(s.id)) failures.push({ type: "SECTION", where: s.id, msg: "Duplicate section id" });
      seen.add(s.id);
    }

    for (const [fromId, targets] of model.linksBySection) {
      for (const t of targets) {
        if (!allIds.has(t)) failures.push({ type: "LINK", where: fromId, msg: `Broken target: ${t}` });
      }
    }

    // NEW v11.8: Ending sections that also contain choice links
    for (const { id, linkCount } of model.endingWithLinks) {
      failures.push({
        type: "ENDING",
        where: id,
        msg: `Section has .ending class but also contains ${linkCount} choice link(s) — should be one or the other`,
      });
    }

    // NEW v11.9: Dead-end sections (no choices out, no .ending class)
    for (const id of model.deadEndSections) {
      notes.push({
        type: "DEAD_END",
        where: id,
        msg: "Section has no outgoing .page-link choices and no .ending marker — reader has no visible exit path",
      });
    }

    // NEW v11.8: Short-content stub warnings (notes, not failures)
    for (const { id, len, preview } of model.shortContentSections) {
      notes.push({
        type: "STUB",
        where: id,
        msg: `Section text is only ${len} char(s) — possible OCR stub. Preview: "${preview}"`,
      });
    }
  }

  const outDegree = new Map(model.linksBySection);
  function isRealChoiceSection(sectionId) {
    return (outDegree.get(sectionId) || []).length >= 2;
  }

  const startId = sectionsOrdered[0];
  if (!startId) throw new Error("No sections found. Expected section.game-section elements with id='section-N'.");

  async function bootFresh() {
    await page.goto(url, { waitUntil: "load" });
    await page.evaluate(() => {
      try { localStorage.clear(); } catch {}
      try { sessionStorage.clear(); } catch {}
      document.body.classList.add("qa-mode");
      if (typeof refreshSectionIndex === "function") { try { refreshSectionIndex(); } catch {} }
    });
    const beginSelectors = [".cover-begin-btn", ".begin-button", ".start-button", "#begin-btn", "#start-btn"];
    for (const sel of beginSelectors) {
      const el = await page.$(sel);
      if (el) { try { await el.click({ timeout: 500 }); await sleep(80); break; } catch {} }
    }
  }

  async function activeId() {
    return await page.evaluate(() => {
      const a = document.querySelector("section.game-section.active");
      return a ? a.id : null;
    });
  }

  async function ensureAtSection(sectionId) {
    await page.evaluate((id) => {
      const m = String(id).match(/section-(\d+)/);
      const n = m ? parseInt(m[1], 10) : null;
      if (n != null && typeof goToSection === "function") {
        try { goToSection(n, false); return; } catch {}
      }
      const secs = Array.from(document.querySelectorAll("section.game-section"));
      for (const s of secs) s.classList.remove("active", "flip-left");
      const t = document.getElementById(id);
      if (t) t.classList.add("active");
    }, sectionId);

    try {
      await page.waitForFunction((expectedId) => {
        const a = document.querySelector("section.game-section.active");
        return a && a.id === expectedId;
      }, sectionId, { timeout: opts.timeoutMs });
    } catch {
      const now = await activeId();
      throw new Error(`Could not activate ${sectionId}; active is ${now ?? "null"}`);
    }
  }

  async function stepLinear(fromId, toId) {
    const fromN = numFromSectionId(fromId);
    const toN = numFromSectionId(toId);
    const dir = (toN > fromN) ? "next" : "prev";

    await page.evaluate((dir) => {
      try {
        if (dir === "next") {
          if (typeof goToNextPage === "function") return goToNextPage();
          if (typeof window.goToNextPage === "function") return window.goToNextPage();
        } else {
          if (typeof goToPrevPage === "function") return goToPrevPage();
          if (typeof window.goToPrevPage === "function") return window.goToPrevPage();
        }
      } catch {}
    }, dir);

    await page.waitForTimeout(60);
    const afterEngine = await activeId();
    if (afterEngine === toId) return;

    const arrowSel = (dir === "next")
      ? `section#${fromId} .page-nav-right, section#${fromId} .page-nav.page-nav-right`
      : `section#${fromId} .page-nav-left, section#${fromId} .page-nav.page-nav-left`;

    try {
      await page.locator(arrowSel).first().click({ force: true, timeout: 500 });
    } catch {
      await page.evaluate((sel) => {
        const el = document.querySelector(sel);
        if (el) el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
      }, arrowSel.split(",")[0]);
    }

    try {
      await page.waitForFunction((expectedId) => {
        const a = document.querySelector("section.game-section.active");
        return a && a.id === expectedId;
      }, toId, { timeout: opts.timeoutMs });
    } catch {
      const now = await activeId();
      throw new Error(`After linear step ${fromId} -> ${toId}, active section is ${now ?? "null"}`);
    }
  }

  async function gotoSectionByPath(pathIds) {
    await bootFresh();
    await ensureAtSection(pathIds[0]);

    for (let i = 0; i < pathIds.length - 1; i++) {
      const fromId = pathIds[i];
      const toId = pathIds[i + 1];

      const toN = numFromSectionId(toId);
      const selector = `section#${fromId} .page-link[data-target="${toId}"]` +
        (toN != null ? `, section#${fromId} .page-link[onclick*="goToSection(${toN})"]` : "");
      const link = await page.$(selector);

      if (link) {
        await link.click();
        try {
          await page.waitForFunction((expectedId) => {
            const a = document.querySelector("section.game-section.active");
            return a && a.id === expectedId;
          }, toId, { timeout: opts.timeoutMs });
        } catch {
          const now = await activeId();
          throw new Error(`After choice click ${fromId} -> ${toId}, active is ${now ?? "null"}`);
        }
      } else {
        const nextId = nextMap.get(fromId);
        const prevId = prevMap.get(fromId);
        if (toId === nextId || toId === prevId) {
          await stepLinear(fromId, toId);
        } else {
          const alt = await page.$(`.page-link[data-target="${toId}"]`);
          if (!alt) throw new Error(`Could not find navigation from ${fromId} to ${toId}`);
          await alt.click();
          await page.waitForTimeout(60);
        }
      }
    }
  }

  async function readBackUI() {
    return await page.evaluate(() => {
      const topBtn = document.getElementById("back-choice-btn");
      const active = document.querySelector("section.game-section.active");
      const bottom = active ? active.querySelector(".bookmark-link") : null;
      const isVisible = (el) => !!(el && el.offsetParent !== null);
      return {
        top: topBtn ? { disabled: !!topBtn.disabled, text: topBtn.textContent.trim(), visible: isVisible(topBtn) } : null,
        bottom: bottom ? { visible: isVisible(bottom), text: bottom.textContent.trim() } : null,
      };
    });
  }

  function expectedBackText(n) { return `Back to page ${n}`; }

  // -----------------------------------------
  // BFS state
  const queue = [{ at: startId, lastChoice: null, path: [startId] }];
  const visited = new Set();
  const testedBottomBookmark = new Set();

  // NEW: track which section IDs were ever the active section during BFS
  const visitedSectionIds = new Set();

  // NEW: track which section IDs have had their page indicator verified
  const checkedIndicator = new Set();

  const maxStates = opts.maxStates;
  let states = 0;

  while (queue.length && states < maxStates) {
    const state = queue.shift();
    const key = `${state.at}|${state.lastChoice ?? "null"}`;
    if (visited.has(key)) continue;
    visited.add(key);
    states++;

    // NEW: record that this section ID was reached
    visitedSectionIds.add(state.at);

    if (opts.debug) logger.writeLine(`DEBUG: visiting ${state.at} (lastChoice=${state.lastChoice ?? "null"}) pathLen=${state.path.length}`);
    if (opts.progress && states % opts.progressEvery === 0) logger.writeLine(".");

    await gotoSectionByPath(state.path);

    // -----------------------------------------
    // NEW: Page indicator check (once per unique section ID)
    // Verifies that #page-indicator contains the correct section number after navigation.
    if (!checkedIndicator.has(state.at)) {
      checkedIndicator.add(state.at);
      const expectedN = numFromSectionId(state.at);
      if (expectedN != null) {
        const indicatorResult = await page.evaluate((n) => {
          const el = document.getElementById("page-indicator");
          if (!el) return { found: false };
          const text = el.textContent.trim();
          // Expected format: "Page N (X/Y)"
          const ok = text.includes("Page " + n + " ") || text === "Page " + n;
          return { found: true, text, ok };
        }, expectedN);

        if (indicatorResult.found && !indicatorResult.ok) {
          failures.push({
            type: "INDICATOR",
            where: state.at,
            msg: `#page-indicator shows "${indicatorResult.text}", expected it to contain "Page ${expectedN}"`,
          });
        }
        // If not found at all, skip silently (book may not use this element in all states)
      }
    }

    // -----------------------------------------
    // Bookmark UI checks (existing logic)
    const ui = await readBackUI();

    if (state.lastChoice) {
      const lastN = numFromSectionId(state.lastChoice);
      const atN = numFromSectionId(state.at);

      if (ui.bottom) {
        if (!ui.bottom.visible) failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark hidden but should be visible" });
        if (lastN != null && !ui.bottom.text.includes(expectedBackText(lastN))) {
          failures.push({ type: "UI", where: state.at, msg: `Bottom back text mismatch: got "${ui.bottom.text}", expected to include "${expectedBackText(lastN)}"` });
        }
      } else {
        failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark element missing" });
      }

      if (ui.top && lastN != null && atN != null && atN !== lastN && ui.top.disabled) {
        failures.push({ type: "UI", where: state.at, msg: "Top back disabled when it should be enabled" });
      }
    } else {
      if (ui.top && !ui.top.disabled) failures.push({ type: "UI", where: state.at, msg: "Top back enabled before any real choice encountered" });
      if (ui.bottom && ui.bottom.visible) failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark visible before any real choice encountered" });
    }

    // -----------------------------------------
    // Bottom bookmark click test (existing logic)
    if (state.lastChoice && ui.bottom && ui.bottom.visible && !testedBottomBookmark.has(state.at)) {
      const m = ui.bottom.text.match(/Back to page\s+(\d+)/i);
      const targetNum = m ? parseInt(m[1], 10) : null;

      if (Number.isFinite(targetNum)) {
        testedBottomBookmark.add(state.at);
        const expectedId = `section-${targetNum}`;
        try {
          const btn = await page.$("section.game-section.active .bookmark-btn");
          if (!btn) throw new Error("bookmark button not found (.bookmark-btn)");
          await btn.click();
          await page.waitForTimeout(80);
          const landed = await activeId();
          if (landed !== expectedId) {
            failures.push({ type: "UI", where: state.at, msg: `Bottom bookmark click mismatch: expected ${expectedId}, landed on ${landed ?? "null"}` });
          }
          await ensureAtSection(state.at);
        } catch (e) {
          failures.push({ type: "UI", where: state.at, msg: `Bottom bookmark click test failed: ${e && e.message ? e.message : String(e)}` });
          try { await ensureAtSection(state.at); } catch {}
        }
      }
    }

    // -----------------------------------------
    // Enqueue neighbours
    let targets = outDegree.get(state.at) || [];
    if (!targets.length) {
      const nextId = nextMap.get(state.at);
      if (nextId) targets = [nextId];
    }

    for (const targetId of targets) {
      const nextLastChoice = isRealChoiceSection(state.at) ? state.at : state.lastChoice;
      queue.push({
        at: targetId,
        lastChoice: nextLastChoice,
        path: state.path.concat([targetId]),
      });
    }
  }

  if (states >= maxStates) {
    notes.push({ type: "NOTE", where: "CRAWL", msg: `Stopped early at ${states} states (maxStates=${maxStates}).` });
  }

  // -----------------------------------------
  // NEW: Unreachable section detection
  // Any section ID in the DOM that BFS never set as state.at is an orphan.
  {
    const unreached = model.allIds.filter(id => !visitedSectionIds.has(id));
    for (const id of unreached) {
      failures.push({
        type: "COVERAGE",
        where: id,
        msg: "Section exists in DOM but was never reached during BFS — no link or page-flip path leads here",
      });
    }
    if (unreached.length === 0) {
      notes.push({ type: "NOTE", where: "COVERAGE", msg: `All ${model.allIds.length} sections were reached during BFS.` });
    }
  }

  // -----------------------------------------
  // NEW: Post-BFS extra tests (save/resume, restart, goToSection validity)
  // These run after BFS so the main traversal isn't affected by any side-effects.
  // Skip with --skipExtras for faster runs.

  if (!opts.skipExtras) {

    // -----------------------------------------------
    // EXTRA TEST 1: Save / Resume round-trip
    // Navigate to the first multi-choice section via the engine (which auto-saves progress),
    // reload the page, and verify that hasProgress() is true and the book resumes there.
    logger.writeLine("\n[Extra test 1/6] Save/Resume round-trip...");
    try {
      const choiceSectionId = sectionsOrdered.find(id => (outDegree.get(id) || []).length >= 2);
      if (!choiceSectionId) {
        notes.push({ type: "NOTE", where: "SAVE_RESUME", msg: "No multi-choice section found; save/resume test skipped." });
      } else {
        const targetN = numFromSectionId(choiceSectionId);

        // Fresh load (keep localStorage clean so goToSection triggers a real save)
        await page.goto(url, { waitUntil: "load" });
        await page.evaluate(() => {
          try { localStorage.clear(); } catch {}
          document.body.classList.add("qa-mode");
        });

        // Navigate using the engine so it records history and calls saveProgress()
        const navOk = await page.evaluate((n) => {
          try {
            if (typeof goToSection === "function") { goToSection(n, false); return true; }
            return false;
          } catch { return false; }
        }, targetN);

        if (!navOk) {
          notes.push({ type: "NOTE", where: "SAVE_RESUME", msg: "goToSection() not accessible; save/resume test skipped." });
        } else {
          await sleep(200); // let saveProgress() run

          // Reload without clearing localStorage
          await page.goto(url, { waitUntil: "load" });
          await page.evaluate(() => { document.body.classList.add("qa-mode"); });
          await sleep(300); // let openBook()/resume logic run

          const resumeResult = await page.evaluate((expectedId) => {
            const hasProg = typeof hasProgress === "function" ? hasProgress() : null;
            const active = document.querySelector("section.game-section.active");
            return { hasProg, activeId: active ? active.id : null };
          }, choiceSectionId);

          if (resumeResult.hasProg === false) {
            failures.push({
              type: "SAVE_RESUME",
              where: choiceSectionId,
              msg: "hasProgress() returned false immediately after saveProgress() + reload",
            });
          } else if (resumeResult.hasProg === null) {
            notes.push({ type: "NOTE", where: "SAVE_RESUME", msg: "hasProgress() not globally accessible; skipped result check." });
          }

          if (resumeResult.hasProg !== false && resumeResult.activeId !== choiceSectionId) {
            failures.push({
              type: "SAVE_RESUME",
              where: choiceSectionId,
              msg: `After reload, expected active section ${choiceSectionId}, got ${resumeResult.activeId ?? "null"}`,
            });
          } else if (resumeResult.activeId === choiceSectionId) {
            notes.push({ type: "NOTE", where: "SAVE_RESUME", msg: `✓ Resumed correctly at ${choiceSectionId} after reload.` });
          }
        }
      }
    } catch (e) {
      notes.push({ type: "NOTE", where: "SAVE_RESUME", msg: `Save/resume test threw: ${e && e.message ? e.message : String(e)}` });
    }

    // -----------------------------------------------
    // EXTRA TEST 2: Restart / goToCover behaviour
    // Navigate into the book, call restartAdventure() (mocking window.confirm),
    // and verify the page returns to the cover view.
    logger.writeLine("[Extra test 2/6] Restart / goToCover test...");
    try {
      await bootFresh();
      const midSectionId = sectionsOrdered[Math.min(10, sectionsOrdered.length - 1)];
      await ensureAtSection(midSectionId);
      await sleep(100);

      // Mock confirm so restartAdventure() doesn't stall headless Chromium
      await page.evaluate(() => { window.confirm = () => true; });

      const restartOk = await page.evaluate(() => {
        try {
          if (typeof restartAdventure === "function") { restartAdventure(); return "restartAdventure"; }
          if (typeof goToCover === "function") { goToCover(); return "goToCover"; }
          return null;
        } catch (e) { return "threw:" + e.message; }
      });

      if (!restartOk) {
        notes.push({ type: "NOTE", where: "RESTART", msg: "Neither restartAdventure() nor goToCover() accessible; restart test skipped." });
      } else if (String(restartOk).startsWith("threw:")) {
        failures.push({ type: "RESTART", where: "RESTART", msg: `Restart function threw: ${restartOk}` });
      } else {
        await sleep(300);

        const afterRestart = await page.evaluate(() => {
          const active = document.querySelector("section.game-section.active");
          const indicator = document.getElementById("page-indicator");
          return {
            activeId: active ? active.id : null,
            indicatorText: indicator ? indicator.textContent.trim() : null,
          };
        });

        // After restart, no game-section should be active, and indicator should say "Cover"
        const indicatorOk = afterRestart.indicatorText === "Cover" || afterRestart.indicatorText === null;
        const sectionOk = afterRestart.activeId === null;

        if (!indicatorOk) {
          failures.push({
            type: "RESTART",
            where: "RESTART",
            msg: `After ${restartOk}(), #page-indicator shows "${afterRestart.indicatorText}", expected "Cover"`,
          });
        }
        if (!sectionOk) {
          failures.push({
            type: "RESTART",
            where: "RESTART",
            msg: `After ${restartOk}(), a game-section is still active: ${afterRestart.activeId}`,
          });
        }
        if (indicatorOk && sectionOk) {
          notes.push({ type: "NOTE", where: "RESTART", msg: `✓ ${restartOk}() correctly returned to cover view.` });
        }
      }
    } catch (e) {
      notes.push({ type: "NOTE", where: "RESTART", msg: `Restart test threw: ${e && e.message ? e.message : String(e)}` });
    }

    // -----------------------------------------------
    // EXTRA TEST 3: goToSection() validity
    // (a) Valid mid-book section: verify landing is correct.
    // (b) Out-of-range number: verify no crash and no broken active state.
    logger.writeLine("[Extra test 3/6] goToSection() validity...");
    try {
      await bootFresh();
      // Pick a section roughly in the middle of the book
      const midIdx = Math.floor(sectionsOrdered.length / 2);
      const midSectionId = sectionsOrdered[midIdx];
      const midN = numFromSectionId(midSectionId);

      // (a) Valid jump
      const validJump = await page.evaluate((n) => {
        try {
          if (typeof goToSection !== "function") return { ok: false, reason: "goToSection not available" };
          goToSection(n, false);
          return { ok: true };
        } catch (e) { return { ok: false, reason: e.message }; }
      }, midN);

      if (!validJump.ok) {
        notes.push({ type: "NOTE", where: "GOTO_SECTION", msg: `goToSection() not testable: ${validJump.reason}` });
      } else {
        await sleep(150);
        const landed = await activeId();
        if (landed !== midSectionId) {
          failures.push({
            type: "NAVIGATION",
            where: midSectionId,
            msg: `goToSection(${midN}) landed on ${landed ?? "null"}, expected ${midSectionId}`,
          });
        } else {
          notes.push({ type: "NOTE", where: "GOTO_SECTION", msg: `✓ goToSection(${midN}) correctly landed on ${midSectionId}.` });
        }

        // (b) Out-of-range: large number not in the book
        const invalidN = 99999;
        const invalidJump = await page.evaluate((n) => {
          try {
            if (typeof goToSection === "function") goToSection(n, false);
            return { threw: false };
          } catch (e) { return { threw: true, msg: e.message }; }
        }, invalidN);

        await sleep(100);
        const afterInvalid = await activeId();

        if (afterInvalid === null) {
          failures.push({
            type: "NAVIGATION",
            where: "GOTO_INVALID",
            msg: `goToSection(${invalidN}) left the page with no active section`,
          });
        } else {
          notes.push({
            type: "NOTE",
            where: "GOTO_INVALID",
            msg: `✓ goToSection(${invalidN}) handled gracefully; active section remained ${afterInvalid}`,
          });
        }
      }
    } catch (e) {
      notes.push({ type: "NOTE", where: "GOTO_SECTION", msg: `goToSection test threw: ${e && e.message ? e.message : String(e)}` });
    }

    // -----------------------------------------------
    // EXTRA TEST 4: jumpToPage() UI function
    // jumpToPage() reads #page-jump input, calls goToSection() if valid, calls alert() if not.
    // Tests: (a) valid section number, (b) out-of-range number that triggers an alert dialog,
    // (c) empty input that should produce no navigation side-effect.
    logger.writeLine("[Extra test 4/6] jumpToPage() UI function...");
    try {
      const jumpInputId = "page-jump";
      const hasInput = await page.$(`#${jumpInputId}`);

      if (!hasInput) {
        notes.push({ type: "NOTE", where: "JUMP_TO_PAGE", msg: `#${jumpInputId} input not found; jumpToPage test skipped.` });
      } else {
        // Check jumpToPage is accessible
        const hasFunc = await page.evaluate(() => typeof jumpToPage === "function");
        if (!hasFunc) {
          notes.push({ type: "NOTE", where: "JUMP_TO_PAGE", msg: "jumpToPage() not globally accessible; test skipped." });
        } else {
          await bootFresh();

          // (a) Valid jump: pick a section in the latter third of the book
          const jumpTargetIdx = Math.floor(sectionsOrdered.length * 0.67);
          const jumpTargetId = sectionsOrdered[jumpTargetIdx];
          const jumpTargetN = numFromSectionId(jumpTargetId);

          await page.evaluate((n) => {
            const inp = document.getElementById("page-jump");
            if (inp) inp.value = String(n);
          }, jumpTargetN);

          await page.evaluate(() => { try { jumpToPage(); } catch {} });
          await sleep(150);

          const jumpLanded = await activeId();
          if (jumpLanded !== jumpTargetId) {
            failures.push({
              type: "JUMP_TO_PAGE",
              where: jumpTargetId,
              msg: `jumpToPage() with input "${jumpTargetN}" landed on ${jumpLanded ?? "null"}, expected ${jumpTargetId}`,
            });
          } else {
            notes.push({ type: "NOTE", where: "JUMP_TO_PAGE", msg: `✓ jumpToPage(${jumpTargetN}) correctly navigated to ${jumpTargetId}.` });
          }

          // (b) Out-of-range: should trigger an alert(), not navigate.
          // Register a one-time dialog handler BEFORE calling jumpToPage so it dismisses
          // automatically without stalling headless Chromium.
          let alertFired = false;
          let alertMsg = "";
          const dialogHandler = (dialog) => {
            alertFired = true;
            alertMsg = dialog.message();
            dialog.dismiss().catch(() => {});
          };
          page.once("dialog", dialogHandler);

          const beforeInvalid = await activeId();
          await page.evaluate(() => {
            const inp = document.getElementById("page-jump");
            if (inp) inp.value = "99999";
          });
          await page.evaluate(() => { try { jumpToPage(); } catch {} });
          await sleep(200);

          // Remove handler in case it didn't fire (don't leave it dangling)
          page.off("dialog", dialogHandler);

          const afterInvalidJump = await activeId();
          if (!alertFired) {
            notes.push({
              type: "NOTE",
              where: "JUMP_TO_PAGE",
              msg: "jumpToPage(99999) did not trigger an alert() — may silently fail on invalid input",
            });
          } else {
            notes.push({
              type: "NOTE",
              where: "JUMP_TO_PAGE",
              msg: `✓ jumpToPage(99999) fired alert: "${alertMsg}"`,
            });
          }
          if (afterInvalidJump !== beforeInvalid) {
            failures.push({
              type: "JUMP_TO_PAGE",
              where: "JUMP_INVALID",
              msg: `jumpToPage(99999) changed active section from ${beforeInvalid} to ${afterInvalidJump} — should not navigate`,
            });
          }

          // (c) Empty input: should do nothing (no alert, no navigation).
          const beforeEmpty = await activeId();
          page.once("dialog", (d) => d.dismiss().catch(() => {})); // safety dismiss if unexpected
          await page.evaluate(() => {
            const inp = document.getElementById("page-jump");
            if (inp) inp.value = "";
          });
          await page.evaluate(() => { try { jumpToPage(); } catch {} });
          await sleep(100);
          const afterEmpty = await activeId();

          if (afterEmpty !== beforeEmpty) {
            failures.push({
              type: "JUMP_TO_PAGE",
              where: "JUMP_EMPTY",
              msg: `jumpToPage("") changed active section from ${beforeEmpty} to ${afterEmpty} — should do nothing`,
            });
          } else {
            notes.push({ type: "NOTE", where: "JUMP_TO_PAGE", msg: `✓ jumpToPage("") correctly did nothing.` });
          }
        }
      }
    } catch (e) {
      notes.push({ type: "NOTE", where: "JUMP_TO_PAGE", msg: `jumpToPage test threw: ${e && e.message ? e.message : String(e)}` });
    }

    // -----------------------------------------------
    // EXTRA TEST 5: Dark mode smoke test
    // Calls toggleOption('dark') and verifies data-theme="dark" on <html>.
    // Calls again to toggle off and verifies the attribute is removed.
    // Also confirms --font-size is unchanged by the toggle (regression guard).
    logger.writeLine("[Extra test 5/6] Dark mode smoke test...");
    try {
      await bootFresh();
      await ensureAtSection(startId);

      const darkResult = await page.evaluate(() => {
        const hasFn = typeof toggleOption === "function";
        if (!hasFn) return { skip: true, reason: "toggleOption() not accessible" };

        const getTheme = () => document.documentElement.getAttribute("data-theme");
        const getFont = () => getComputedStyle(document.documentElement).getPropertyValue("--font-size").trim();

        // Capture starting state
        const initialTheme = getTheme();
        const initialFont = getFont();

        // Toggle ON
        try { toggleOption("dark"); } catch (e) { return { skip: false, err: "toggleOn threw: " + e.message }; }
        const afterOn = getTheme();
        const fontAfterOn = getFont();

        // Toggle OFF
        try { toggleOption("dark"); } catch (e) { return { skip: false, err: "toggleOff threw: " + e.message }; }
        const afterOff = getTheme();
        const fontAfterOff = getFont();

        return { skip: false, initialTheme, afterOn, afterOff, initialFont, fontAfterOn, fontAfterOff };
      });

      if (darkResult.skip) {
        notes.push({ type: "NOTE", where: "DARK_MODE", msg: `Dark mode test skipped: ${darkResult.reason}` });
      } else if (darkResult.err) {
        failures.push({ type: "DARK_MODE", where: "DARK_MODE", msg: darkResult.err });
      } else {
        if (darkResult.afterOn !== "dark") {
          failures.push({
            type: "DARK_MODE",
            where: "DARK_MODE",
            msg: `After toggleOption('dark'), expected data-theme="dark", got "${darkResult.afterOn ?? "(none)"}"`,
          });
        } else {
          notes.push({ type: "NOTE", where: "DARK_MODE", msg: `✓ toggleOption('dark') applied data-theme="dark".` });
        }

        if (darkResult.afterOff !== null && darkResult.afterOff !== "") {
          failures.push({
            type: "DARK_MODE",
            where: "DARK_MODE",
            msg: `After second toggleOption('dark'), expected data-theme removed, but got "${darkResult.afterOff}"`,
          });
        } else {
          notes.push({ type: "NOTE", where: "DARK_MODE", msg: `✓ Second toggleOption('dark') correctly removed data-theme.` });
        }

        // Regression: font size should survive the dark toggle
        if (darkResult.fontAfterOn !== darkResult.initialFont) {
          failures.push({
            type: "DARK_MODE",
            where: "DARK_MODE",
            msg: `--font-size changed from "${darkResult.initialFont}" to "${darkResult.fontAfterOn}" during dark mode toggle-on`,
          });
        }
        if (darkResult.fontAfterOff !== darkResult.initialFont) {
          failures.push({
            type: "DARK_MODE",
            where: "DARK_MODE",
            msg: `--font-size changed from "${darkResult.initialFont}" to "${darkResult.fontAfterOff}" during dark mode toggle-off`,
          });
        }
        if (darkResult.fontAfterOn === darkResult.initialFont && darkResult.fontAfterOff === darkResult.initialFont) {
          notes.push({ type: "NOTE", where: "DARK_MODE", msg: `✓ --font-size ("${darkResult.initialFont}") unchanged by dark mode toggle.` });
        }
      }
    } catch (e) {
      notes.push({ type: "NOTE", where: "DARK_MODE", msg: `Dark mode test threw: ${e && e.message ? e.message : String(e)}` });
    }

    // -----------------------------------------------
    // EXTRA TEST 6: Font slider smoke test
    // Iterates all 5 slider positions (0=X-Small/15px through 4=X-Large/23px).
    // For each position calls setFontSizeFromSlider() and verifies --font-size changes correctly.
    // Restores the original slider position (2 = Medium/19px) at the end.
    logger.writeLine("[Extra test 6/6] Font slider smoke test...");
    try {
      await bootFresh();
      await ensureAtSection(startId);

      // Expected px values per slider position — mirrors the fontSizes array in the book.
      // If the book changes its fontSizes array these will need updating.
      const EXPECTED_FONT_SIZES = {
        0: "15px",   // X-Small
        1: "17px",   // Small
        2: "19px",   // Medium  (default)
        3: "21px",   // Large
        4: "23px",   // X-Large
      };

      const sliderResult = await page.evaluate((expectedMap) => {
        const hasFn = typeof setFontSizeFromSlider === "function";
        if (!hasFn) return { skip: true, reason: "setFontSizeFromSlider() not accessible" };

        const getFont = () => getComputedStyle(document.documentElement).getPropertyValue("--font-size").trim();

        const results = [];
        for (const [pos, expectedPx] of Object.entries(expectedMap)) {
          const posNum = parseInt(pos, 10);
          try {
            setFontSizeFromSlider(posNum);
          } catch (e) {
            results.push({ pos: posNum, expected: expectedPx, actual: null, err: e.message });
            continue;
          }
          const actual = getFont();
          results.push({ pos: posNum, expected: expectedPx, actual, ok: actual === expectedPx });
        }

        // Restore default (pos 2 = Medium)
        try { setFontSizeFromSlider(2); } catch {}

        return { skip: false, results };
      }, EXPECTED_FONT_SIZES);

      if (sliderResult.skip) {
        notes.push({ type: "NOTE", where: "FONT_SLIDER", msg: `Font slider test skipped: ${sliderResult.reason}` });
      } else {
        let allOk = true;
        for (const r of sliderResult.results) {
          if (r.err) {
            failures.push({
              type: "FONT_SLIDER",
              where: "FONT_SLIDER",
              msg: `setFontSizeFromSlider(${r.pos}) threw: ${r.err}`,
            });
            allOk = false;
          } else if (!r.ok) {
            failures.push({
              type: "FONT_SLIDER",
              where: "FONT_SLIDER",
              msg: `Slider pos ${r.pos}: expected --font-size="${r.expected}", got "${r.actual}"`,
            });
            allOk = false;
          }
        }
        if (allOk) {
          const summary = sliderResult.results.map(r => `${r.pos}=${r.actual}`).join(", ");
          notes.push({ type: "NOTE", where: "FONT_SLIDER", msg: `✓ All 5 font sizes correct: ${summary}` });
        }
      }
    } catch (e) {
      notes.push({ type: "NOTE", where: "FONT_SLIDER", msg: `Font slider test threw: ${e && e.message ? e.message : String(e)}` });
    }

  } else {
    notes.push({ type: "NOTE", where: "EXTRAS", msg: "Post-BFS extra tests skipped (--skipExtras)." });
  }

  // -----------------------------------------
  await browser.close();

  logger.writeLine(`\nQA finished. States explored: ${states}`);
  logger.writeLine(`Sections in DOM: ${model.allIds.length}  |  Unique sections visited: ${visitedSectionIds.size}`);

  if (notes.length) {
    logger.writeLine("\nNotes:");
    for (const n of notes) logger.writeLine(" - " + JSON.stringify(n));
  }

  if (!failures.length) {
    logger.writeLine("\n✅ No issues found.");
    logger.close();
    process.exit(0);
  } else {
    logger.writeLine(`\n❌ Found ${failures.length} issue(s):`);
    for (const f of failures) logger.writeLine(" - " + JSON.stringify(f, null, 2));
    logger.close();
    process.exit(2);
  }
})().catch((err) => {
  console.error("\nQA script error:", err && err.stack ? err.stack : err);
  process.exit(1);
});
