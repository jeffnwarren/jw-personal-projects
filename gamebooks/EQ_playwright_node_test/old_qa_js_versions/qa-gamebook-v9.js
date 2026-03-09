//------------------------------------------
// qa-gamebook-v9.js
// Usage:
//   node qa-gamebook-v9.js "C:\path\to\Dungeon_of_Dread.html"
//
// What it checks:
//  - every section exists + unique
//  - every .page-link target exists
//  - crawl from the first section (BFS):
//      * follows explicit choice links (.page-link)
//      * for linear pages with no choices, advances via goToNextPage()/goToPrevPage() or page-nav arrows
//  - verifies "Back to page X" (bottom bookmark) matches the last *real choice page* on the path
//
// Assumptions (based on your build):
//  - sections have id="section-N" and data-section="N"
//  - choice links are .page-link with data-target like "section-82"
//  - bottom bookmark container uses .bookmark-link
//
// Notes:
//  - This script does NOT rely on window.goToSection being exposed.

const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

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

(async () => {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: node qa-gamebook-v9.js "C:\\path\\to\\Dungeon_of_Dread.html"');
    process.exit(1);
  }

  const url = toFileUrl(filePath);

  const browser = await chromium.launch({ headless: true });
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
        .map(a => a.getAttribute("data-target"))
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
      }, sectionId, { timeout: 1500 });
    } catch {
      const now = await activeId();
      throw new Error(`Could not activate ${sectionId}; active is ${now ?? "null"}`);
    }
  }

  async function stepLinear(fromId, toId) {
    const fromN = numFromSectionId(fromId);
    const toN = numFromSectionId(toId);
    const dir = (toN > fromN) ? "next" : "prev";

    // Prefer calling engine functions if available (more reliable than clicking overlay arrows).
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

    // As fallback, click arrow in the current section
    const arrowSel = (dir === "next")
      ? `section#${fromId} .page-nav-right, section#${fromId} .page-nav.page-nav-right`
      : `section#${fromId} .page-nav-left, section#${fromId} .page-nav.page-nav-left`;

    try {
      await page.locator(arrowSel).first().click({ force: true, timeout: 500 });
    } catch {
      // As last fallback: dispatch click
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
      }, toId, { timeout: 1500 });
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
      const selector = `section#${fromId} .page-link[data-target="${toId}"]`;
      const link = await page.$(selector);

      if (link) {
        await link.click();
        try {
          await page.waitForFunction((expectedId) => {
            const a = document.querySelector("section.game-section.active");
            return a && a.id === expectedId;
          }, toId, { timeout: 1500 });
        } catch {
          const now = await activeId();
          throw new Error(`After choice click ${fromId} -> ${toId}, active is ${now ?? "null"}`);
        }
      } else {
        // If numeric-adjacent, treat as linear
        const fromN = numFromSectionId(fromId);
        const toN = numFromSectionId(toId);
        if (fromN != null && toN != null && Math.abs(toN - fromN) === 1) {
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
      const bottom = document.querySelector(".bookmark-link");
      return {
        top: topBtn ? { disabled: !!topBtn.disabled, text: topBtn.textContent.trim() } : null,
        bottom: bottom ? { display: getComputedStyle(bottom).display, text: bottom.textContent.trim() } : null,
      };
    });
  }

  function expectedBackText(n) {
    return `Back to page ${n}`;
  }

  const queue = [{ at: startId, lastChoice: null, path: [startId] }];
  const visited = new Set();
  const maxStates = 5000;
  let states = 0;

  while (queue.length && states < maxStates) {
    const state = queue.shift();
    const key = `${state.at}|${state.lastChoice ?? "null"}`;
    if (visited.has(key)) continue;
    visited.add(key);
    states++;

    await gotoSectionByPath(state.path);

    const ui = await readBackUI();

    if (state.lastChoice) {
      const lastN = numFromSectionId(state.lastChoice);
      const atN = numFromSectionId(state.at);

      if (ui.bottom) {
        if (ui.bottom.display === "none") failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark hidden but should be visible" });
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
      if (ui.bottom && ui.bottom.display !== "none") failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark visible before any real choice encountered" });
    }

    // Enqueue neighbors:
    // - explicit choice links
    // - if none, linear next section number (n+1) if it exists
    let targets = outDegree.get(state.at) || [];
    if (!targets.length) {
      const n = numFromSectionId(state.at);
      if (n != null) {
        const nextId = `section-${n + 1}`;
        if (allIds.has(nextId)) targets = [nextId];
      }
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

  console.log(`\nQA finished. States explored: ${states}`);
  if (notes.length) {
    console.log("\nNotes:");
    for (const n of notes) console.log(" -", n);
  }

  if (!failures.length) {
    console.log("\n✅ No issues found.");
    process.exit(0);
  } else {
    console.log(`\n❌ Found ${failures.length} issue(s):`);
    for (const f of failures) console.log(" -", f);
    process.exit(2);
  }
})().catch((err) => {
  console.error("\nQA script error:", err && err.stack ? err.stack : err);
  process.exit(1);
});
