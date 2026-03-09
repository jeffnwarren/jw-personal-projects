//------------------------------------------
// qa-gamebook-v11.8.js
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
// Copy the gamebook html (e.g. Dungeon_of_Dread_Final_2026-02-20_0727_CST.html) and latest qa_gamebook-<version>.js file (e.g. qa-gamebook-v11.8.0.js) to the project folder.
//
// PURPOSE:
// Automated QA crawler for single-file HTML gamebooks (generic; not specific to Dungeon of Dread).
// Uses Playwright to navigate the book like a real player and validate:
//  - Choice links ("Turn to page X")
//  - Linear page-flip navigation (DOM order)
//  - Bottom bookmark UI ("Back to page X")
//  - Unreachable sections (never visited during BFS)
//  - Ending sections with unexpected choice links
//  - Short-content sections (stub detection)
//  - #page-indicator text accuracy
//  - Save/Resume (localStorage round-trip)
//  - Restart/goToCover behaviour
//  - goToSection() validity (valid and out-of-range inputs)
//
// WHAT IS BFS?
// BFS = Breadth-First Search. In this script, that means we explore the gamebook state-space
// level-by-level using a queue, so we systematically cover all reachable paths without
// getting stuck going deep down a single branch.
//
// NEW IN v11.8:
//  1. Unreachable section detection: any section in the DOM that BFS never visits is flagged.
//     These are genuine orphans - conversion errors where a section exists but nothing links to it.
//  2. Ending sections with unexpected links: a section with the CSS class "ending" should never
//     also contain .page-link choices. Flags accidental hybrid sections.
//  3. Short-content detection: sections with fewer than MIN_CONTENT_CHARS characters of text are
//     flagged as notes. Catches stubs left by the OCR/conversion pipeline.
//  4. Page indicator accuracy: after navigating to each section (checked once per section ID),
//     verifies that #page-indicator contains the correct section number.
//  5. Save/Resume round-trip: navigates to the first multi-choice section, reloads the page,
//     and verifies that hasProgress() is true and the book resumes at the correct section.
//  6. Restart test: mocks window.confirm, calls restartAdventure(), and verifies the page
//     returns to the cover view (#page-indicator shows "Cover", no game-section active).
//  7. goToSection validity: calls goToSection() with a valid mid-book section and an
//     out-of-range number, verifying correct navigation and graceful failure respectively.
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
//   node qa-gamebook-v11.8.js [flags] "C:\path\to\YourGamebook.html"
//
// Example:
//   node qa-gamebook-v11.8.js --headed --progress --slowMo=50 --outputLog "C:\path\to\YourGamebook.html"
//   node qa-gamebook-v11.8.js --skipExtras --progress "C:\path\to\YourGamebook.html"
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
    console.error('Usage: node qa-gamebook-v11.8.js [--headed] [--progress] [--skipExtras] [--minContent=40] [--progressEvery=25] [--maxStates=5000] [--slowMo=0] [--timeoutMs=1500] [--outputLog[=<n>]] "C:\\path\\to\\Gamebook.html"');
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

    // NEW: Ending sections that also have choice links (should be impossible)
    const endingWithLinks = [];
    for (const s of sections) {
      const isEnding = s.classList.contains("ending") || !!s.querySelector(".ending");
      const links = s.querySelectorAll(".page-link");
      if (isEnding && links.length > 0) {
        endingWithLinks.push({ id: s.id, linkCount: links.length });
      }
    }

    // NEW: Sections with suspiciously little text content (potential OCR stubs)
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

    // NEW: Ending sections that also contain choice links
    for (const { id, linkCount } of model.endingWithLinks) {
      failures.push({
        type: "ENDING",
        where: id,
        msg: `Section has .ending class but also contains ${linkCount} choice link(s) — should be one or the other`,
      });
    }

    // NEW: Short-content stub warnings (notes, not failures)
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
    logger.writeLine("\n[Extra test 1/3] Save/Resume round-trip...");
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
    logger.writeLine("[Extra test 2/3] Restart / goToCover test...");
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
    logger.writeLine("[Extra test 3/3] goToSection() validity...");
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
        const beforeInvalid = await activeId();
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
