//------------------------------------------
// qa-gamebook-v11.5.js
//
// PURPOSE:
// Automated QA crawler for single-file HTML gamebooks.
// Uses Playwright to navigate the book exactly like a real player,
// validating links, linear navigation, and "Back to page X" bookmark logic.
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
//       Opens a visible Chromium window so you can watch page flips,
//       breadcrumb updates, and navigation behavior in real time.
//
//   --slowMo=<ms>
//       Slows down Playwright actions (in milliseconds).
//       Useful with --headed for visually debugging navigation.
//       Example: --slowMo=50
//
//   --timeoutMs=<ms>
//       Overrides default wait timeouts for navigation and page activation.
//       Useful on slower machines or when animations are involved.
//       Example: --timeoutMs=3000
//
//   --maxStates=<N>
//       Hard cap on how many BFS states will be explored.
//       Acts as a safety valve for very large or unexpectedly looping books.
//
//
//   --outputLog[=<name>]
//       Writes console output to a log file in the directory you run the script from.
//       If <name> is omitted, a meaningful default name is generated with a Central-time
//       timestamp and CST/CDT abbreviation (DST-aware).
//       Example:
//         --outputLog
//         --outputLog=runlog.txt
//
//   --debug
//       Enables verbose logging of navigation paths and state transitions.
//       Noisy, but extremely useful when diagnosing a specific failure.
//
// USAGE:
//   node qa-gamebook-v11.5.js [flags] "Dungeon_of_Dread.html"
//
// Example:
//   node qa-gamebook-v11.5.js --headed --progress --slowMo=50 "Dungeon_of_Dread.html"
//
// NOTES:
// - Does NOT rely on window.goToSection being globally exposed.
// - Linear navigation follows DOM order, not numeric adjacency.
// - Bookmark visibility is evaluated ONLY within the active section.
//
//------------------------------------------
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

// -----------------------------------------
// CLI options
//   node qa-gamebook-v11.5.js [--headed] [--progress] [--progressEvery=25] [--maxStates=5000] [--slowMo=0] [--timeoutMs=1500] "path/to/book.html"
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
  };
  const positional = [];
  for (const a of argv) {
    if (!a.startsWith("--")) { positional.push(a); continue; }
    if (a === "--headed" || a === "--showBrowser") { opts.headed = true; continue; }
    if (a === "--progress") { opts.progress = true; continue; }
    if (a === "--debug") { opts.debug = true; continue; }
    if (a === "--outputLog") { opts.outputLog = true; continue; }
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) {
      const k = m[1];
      const v = m[2];
      if (k === "progressEvery") opts.progressEvery = Math.max(1, parseInt(v, 10) || opts.progressEvery);
      if (k === "maxStates") opts.maxStates = Math.max(1, parseInt(v, 10) || opts.maxStates);
      if (k === "slowMo") opts.slowMo = Math.max(0, parseInt(v, 10) || 0);
      if (k === "timeoutMs") opts.timeoutMs = Math.max(100, parseInt(v, 10) || opts.timeoutMs);
      if (k === "outputLog") opts.outputLog = (v === "" ? true : v);
      if (k === "headless") opts.headed = (String(v).toLowerCase() === "false"); // --headless=false => headed
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
  // outputLogOpt:
  //   - falsey => no file logging
  //   - true   => auto-generate a timestamped name
  //   - string => use that filename
  if (!outputLogOpt) {
    return {
      writeLine: (s) => console.log(s),
      close: () => {}
    };
  }

  // DST-aware Central time stamp (America/Chicago)
  const dt = new Date();
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Chicago",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZoneName: "short",
  }).formatToParts(dt);

  const get = (type) => (parts.find(p => p.type === type)?.value || "");
  const yyyy = get("year");
  const mm = get("month");
  const dd = get("day");
  const hh = get("hour");
  const min = get("minute");
  const tz = get("timeZoneName").replace(/\s+/g, ""); // "CST" or "CDT"

  const bookBase = bookFilePath
    ? path.basename(bookFilePath, path.extname(bookFilePath))
    : "run";

  function sanitize(name) {
    return String(name).replace(/[<>:"/\\|?*\x00-\x1F]/g, "_").trim();
  }

  let filename;
  if (outputLogOpt === true) {
    filename = `qa_${sanitize(bookBase)}_${yyyy}-${mm}-${dd}_${hh}${min}_${tz}.txt`;
  } else {
    filename = String(outputLogOpt);
    if (!filename.toLowerCase().endsWith(".txt")) filename += ".txt";
    filename = sanitize(filename);
  }

  const fullPath = path.resolve(process.cwd(), filename);
  const stream = fs.createWriteStream(fullPath, { flags: "a" });

  // Tee console output to file
  const orig = {
    log: console.log,
    error: console.error,
    warn: console.warn,
  };

  function write(prefix, args) {
    const line = args.map(a => {
      if (typeof a === "string") return a;
      try { return JSON.stringify(a, null, 2); } catch { return String(a); }
    }).join(" ");
    stream.write(prefix + line + "\n");
  }

  console.log = (...args) => { orig.log(...args); write("", args); };
  console.error = (...args) => { orig.error(...args); write("ERROR: ", args); };
  console.warn = (...args) => { orig.warn(...args); write("WARN: ", args); };

  orig.log(`(logging to ${fullPath})`);

  return {
    writeLine: (s) => { console.log(s); },
    close: () => {
      try { stream.end(); } catch {}
      console.log = orig.log;
      console.error = orig.error;
      console.warn = orig.warn;
    }
  };
}


(async () => {
  const { opts, positional } = parseArgs(process.argv.slice(2));
  const filePath = positional[0];
  if (!filePath) {
    console.error('Usage: node qa-gamebook-v11.5.js [--headed] [--progress] [--progressEvery=25] [--maxStates=5000] [--slowMo=0] [--timeoutMs=1500] [--outputLog[=<name>]] "C:\\path\\to\\Dungeon_of_Dread.html"');
    process.exit(1);
  }

  const logger = makeLogger(opts.outputLog, filePath);

  // Ensure logger is closed on normal exit / Ctrl+C.
  process.on("exit", () => { try { logger.close(); } catch {} });
  process.on("SIGINT", () => { try { logger.close(); } catch {} process.exit(130); });

  const url = toFileUrl(filePath);

  const browser = await chromium.launch({ headless: !opts.headed, slowMo: opts.slowMo });
  const page = await browser.newPage({
    viewport: { width: 390, height: 844 },
  });

  const failures = [];
  const notes = [];

  await page.goto(url, { waitUntil: "load" });

  // Build section index + link map from DOM
  const model = await page.evaluate(() => {
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
    return {
      sectionNums,
      allIds: Array.from(allIds),
      linksBySection: Array.from(linksBySection.entries()),
    };
  });

  const allIds = new Set(model.allIds);
  const sectionsOrdered = model.sectionNums.map(x => x.id);

// Linear navigation maps (based on DOM order of numbered sections)
// Some books may skip numbers (e.g., section-2 missing), so we use order not n+1.
const nextMap = new Map();
const prevMap = new Map();
for (let i = 0; i < sectionsOrdered.length; i++) {
  const id = sectionsOrdered[i];
  if (i > 0) prevMap.set(id, sectionsOrdered[i - 1]);
  if (i < sectionsOrdered.length - 1) nextMap.set(id, sectionsOrdered[i + 1]);
}


  // 1) Basic integrity checks
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
  }

  const outDegree = new Map(model.linksBySection);
  function isRealChoiceSection(sectionId) {
    const targets = outDegree.get(sectionId) || [];
    return targets.length >= 2;
  }

  const startId = sectionsOrdered[0];
  if (!startId) throw new Error("No sections found. Expected section.game-section elements with id='section-N'.");

  async function bootFresh() {
    await page.goto(url, { waitUntil: "load" });

    // Clean slate: avoid resume-to-weird-state
    await page.evaluate(() => {
      try { localStorage.clear(); } catch {}
      try { sessionStorage.clear(); } catch {}
      document.body.classList.add("qa-mode");
      // Some builds require indexing sections for next/prev nav
      if (typeof refreshSectionIndex === "function") {
        try { refreshSectionIndex(); } catch {}
      }
    });

    // Click a begin/start button if present
    const beginSelectors = [".cover-begin-btn", ".begin-button", ".start-button", "#begin-btn", "#start-btn"];
    for (const sel of beginSelectors) {
      const el = await page.$(sel);
      if (el) {
        try { await el.click({ timeout: 500 }); await sleep(80); break; } catch {}
      }
    }
  }

  async function activeId() {
    return await page.evaluate(() => {
      const a = document.querySelector("section.game-section.active");
      return a ? a.id : null;
    });
  }

  async function ensureAtSection(sectionId) {
    // Try to initialize via engine if available; fall back to class toggle only.
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

    // Wait for the DOM to reflect it
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

    // 1) Prefer calling engine functions (most reliable).
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
      return null;
    }, dir);

    // Give the UI a moment to update; if we're already at the expected target, stop.
    await page.waitForTimeout(60);
    const afterEngine = await activeId();
    if (afterEngine === toId) return;

    // 2) Fallback: click the overlay arrow in the current section.
    const arrowSel = (dir === "next")
      ? `section#${fromId} .page-nav-right, section#${fromId} .page-nav.page-nav-right`
      : `section#${fromId} .page-nav-left, section#${fromId} .page-nav.page-nav-left`;

    try {
      await page.locator(arrowSel).first().click({ force: true, timeout: 500 });
    } catch {
      // 3) Last fallback: dispatch click
      await page.evaluate((sel) => {
        const el = document.querySelector(sel);
        if (el) el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
      }, arrowSel.split(",")[0]);
    }

    // Wait for expected active
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

    // Ensure start
    await ensureAtSection(pathIds[0]);

    for (let i = 0; i < pathIds.length - 1; i++) {
      const fromId = pathIds[i];
      const toId = pathIds[i + 1];

      // Try explicit choice link first
      const toN = numFromSectionId(toId);
      const selector = `section#${fromId} .page-link[data-target="${toId}"]` + (toN != null ? `, section#${fromId} .page-link[onclick*="goToSection(${toN})"]` : "");
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
        // If the target is the next/prev section in DOM order, treat as linear (page-flip)
        const nextId = nextMap.get(fromId);
        const prevId = prevMap.get(fromId);
        if (toId === nextId || toId === prevId) {
          await stepLinear(fromId, toId);
        } else {
          // As a fallback, try any matching choice link anywhere
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

      // True visibility (accounts for hidden parent sections)
      const isVisible = (el) => !!(el && el.offsetParent !== null);

      return {
        top: topBtn ? { disabled: !!topBtn.disabled, text: topBtn.textContent.trim(), visible: isVisible(topBtn) } : null,
        bottom: bottom ? { visible: isVisible(bottom), text: bottom.textContent.trim() } : null,
      };
    });
  }

  function expectedBackText(n) {
    return `Back to page ${n}`;
  }

  const queue = [{ at: startId, lastChoice: null, path: [startId] }];
  const visited = new Set();
  const maxStates = opts.maxStates;
  let states = 0;

  while (queue.length && states < maxStates) {
    const state = queue.shift();
    const key = `${state.at}|${state.lastChoice ?? "null"}`;
    if (visited.has(key)) continue;
    visited.add(key);
    states++;

    if (opts.debug) logger.writeLine(`DEBUG: visiting ${state.at} (lastChoice=${state.lastChoice ?? 'null'}) pathLen=${state.path.length}`);


    if (opts.progress && states % opts.progressEvery === 0) {
      logger.writeLine(".");
    }
    if (opts.debug) {
      console.log(`\n[DEBUG] state=${states} at=${state.at} lastChoice=${state.lastChoice ?? "null"} pathLen=${state.path.length}`);
    }


    await gotoSectionByPath(state.path);

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

      // If top button exists, it should be enabled unless we're on that same page.
      if (ui.top && lastN != null && atN != null && atN !== lastN && ui.top.disabled) {
        failures.push({ type: "UI", where: state.at, msg: "Top back disabled when it should be enabled" });
      }
    } else {
      // No lastChoice yet
      if (ui.top && !ui.top.disabled) failures.push({ type: "UI", where: state.at, msg: "Top back enabled before any real choice encountered" });
      if (ui.bottom && ui.bottom.visible) failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark visible before any real choice encountered" });
    }

    // Enqueue neighbors:
    // - explicit choice links
    // - if none, linear "next page" in DOM order (page-flip)
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

  await browser.close();
  logger.close();

  console.log(`\nQA finished. States explored: ${states}`);
  if (notes.length) {
    console.log("\nNotes:");
    for (const n of notes) console.log(" -", n);
  }

  if (!failures.length) {
    logger.writeLine("\n✅ No issues found.");
    process.exit(0);
  } else {
    logger.writeLine(`\n❌ Found ${failures.length} issue(s):`);
    for (const f of failures) logger.writeLine(" - " + JSON.stringify(f, null, 2));
    process.exit(2);
  }
})().catch((err) => {
  console.error("\nQA script error:", err && err.stack ? err.stack : err);
  process.exit(1);
});