//------------------------------------------
// qa-gamebook.js
// Usage:
//   node qa-gamebook.js "C:\path\to\Dungeon_of_Dread.html"
//
// What it checks:
//  - every section exists + unique
//  - every .page-link target exists
//  - crawl from the first section via choices (BFS)
//  - verifies "Back to page X" (top + bottom) matches the last *real choice page* on the path
//
// Assumptions based on your build:
//  - sections have id="section-N" and data-section="N"
//  - choice links are .page-link with data-target like "section-82"
//  - top back button id="back-choice-btn"
//  - bottom bookmark container uses .bookmark-link (as in your code)

const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

function toFileUrl(p) {
  const abs = path.resolve(p);
  if (!fs.existsSync(abs)) throw new Error(`File not found: ${abs}`);
  // Windows file URL
  return "file:///" + abs.replace(/\\/g, "/");
}

function numFromSectionId(id) {
  const m = String(id).match(/section-(\d+)/);
  return m ? parseInt(m[1], 10) : null;
}

(async () => {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: node qa-gamebook.js "C:\\path\\to\\Dungeon_of_Dread.html"');
    process.exit(1);
  }

  const url = toFileUrl(filePath);

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({
    // Mobile-ish viewport to catch fixed header issues similar to Android
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

    // Choice links: .page-link with data-target="section-XX"
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

  // Helper: “real choice page” = 2+ outgoing links (so early linear “turn to” pages don’t count)
  const outDegree = new Map(model.linksBySection);
  function isRealChoiceSection(sectionId) {
    const targets = outDegree.get(sectionId) || [];
    return targets.length >= 2;
  }

  // 2) Crawl via BFS from the first section
  const startId = sectionsOrdered[0];
  if (!startId) throw new Error("No sections found. Expected section.game-section elements with id='section-N'.");

  const queue = [{ at: startId, lastChoice: null, path: [startId] }];
  const visited = new Set(); // stateful: section + lastChoice
  const maxStates = 5000;

  async function gotoSectionByPath(pathIds) {
    // Reload fresh each time so internal history/bookmark state matches the path we take.
    await page.goto(url, { waitUntil: "load" });

    // Try to "begin" if the book starts on a cover/options page.
    const beginSelectors = [".cover-begin-btn", ".begin-button", ".start-button", "[data-action='begin']", "button:has-text('Begin')"];
    for (const sel of beginSelectors) {
      const el = await page.$(sel);
      if (el) {
        try {
          await el.click({ timeout: 250 });
          await page.waitForTimeout(50);
          break;
        } catch {}
      }
    }

    // Helper to get current active section id
    async function activeId() {
      return await page.evaluate(() => {
        const a = document.querySelector("section.game-section.active");
        return a ? a.id : null;
      });
    }

    // If we still don't have an active section, force-activate the first id in the path
    // (Fallback only; we also record a note so you know it happened.)
    const firstTarget = pathIds[0];
    let cur = await activeId();
    if (!cur) {
      await page.evaluate((id) => {
        const secs = Array.from(document.querySelectorAll("section.game-section"));
        for (const s of secs) s.classList.remove("active", "flip-left");
        const t = document.getElementById(id);
        if (t) t.classList.add("active");
      }, firstTarget);
      notes.push({ type: "NOTE", where: firstTarget, msg: "Fallback: forced first active section (no active section after load/begin)." });
      await page.waitForTimeout(20);
      cur = await activeId();
    }

    // If active section isn't our expected start, attempt to jump there by clicking a link to it (rare),
    // otherwise fallback-force it.
    if (cur !== firstTarget) {
      // Try clicking any link that targets the first target
      const jump = await page.$(`.page-link[data-target="${firstTarget}"]`);
      if (jump) {
        try {
          await jump.click({ timeout: 250 });
          await page.waitForTimeout(30);
        } catch {}
      }
      cur = await activeId();
      if (cur !== firstTarget) {
        await page.evaluate((id) => {
          const secs = Array.from(document.querySelectorAll("section.game-section"));
          for (const s of secs) s.classList.remove("active", "flip-left");
          const t = document.getElementById(id);
          if (t) t.classList.add("active");
        }, firstTarget);
        notes.push({ type: "NOTE", where: firstTarget, msg: `Fallback: forced active section to ${firstTarget} (couldn't reach via UI).` });
        await page.waitForTimeout(20);
      }
    }

    // Replay clicks along the path
    for (let i = 0; i < pathIds.length - 1; i++) {
      const fromId = pathIds[i];
      const toId = pathIds[i + 1];

      // Click the specific choice link in the current section that points to the next section.
      const selector = `section#${fromId} .page-link[data-target="${toId}"]`;
      const link = await page.$(selector);

      if (!link) {
        // As a fallback, try any matching link (in case markup is slightly different)
        const alt = await page.$(`.page-link[data-target="${toId}"]`);
        if (!alt) throw new Error(`Could not find link from ${fromId} to ${toId}`);
        await alt.click();
      } else {
        await link.click();
      }

      await page.waitForTimeout(30);

      const now = await activeId();
      if (now !== toId) {
        // Some engines animate / delay updates; give it a little more time
        await page.waitForTimeout(80);
        const now2 = await activeId();
        if (now2 !== toId) {
          throw new Error(`After clicking ${fromId} -> ${toId}, active section is ${now2 ?? "null"}`);
        }
      }
    }
  }

  async function readBackUI() {
    return await page.evaluate(() => {
      const topBtn = document.getElementById("back-choice-btn");
      const bottom = document.querySelector(".bookmark-link");
      return {
        top: topBtn
          ? { disabled: !!topBtn.disabled, text: topBtn.textContent.trim() }
          : null,
        bottom: bottom
          ? { display: getComputedStyle(bottom).display, text: bottom.textContent.trim() }
          : null,
      };
    });
  }

  function expectedBackText(n) {
    return `Back to page ${n}`;
  }
  function expectedTopText(n) {
    return `↩ Back to ${n}`;
  }

  let states = 0;

  while (queue.length && states < maxStates) {
    const state = queue.shift();
    const key = `${state.at}|${state.lastChoice ?? "null"}`;
    if (visited.has(key)) continue;
    visited.add(key);
    states++;

    // Navigate to this section in the real browser
    await gotoSectionByPath(state.path);

    // Verify UI matches expected lastChoice for this path
    const ui = await readBackUI();

    // If we have a lastChoice, top should be enabled unless we’re on that page
    if (state.lastChoice) {
      const lastN = numFromSectionId(state.lastChoice);
      const atN = numFromSectionId(state.at);

      // Top button expectations
      if (!ui.top) {
        failures.push({ type: "UI", where: state.at, msg: "Missing top back button (#back-choice-btn)" });
      } else {
        if (atN !== lastN) {
          if (ui.top.disabled) failures.push({ type: "UI", where: state.at, msg: "Top back button disabled but should be enabled" });
          if (ui.top.text !== expectedTopText(lastN)) failures.push({ type: "UI", where: state.at, msg: `Top back text mismatch: got "${ui.top.text}", expected "${expectedTopText(lastN)}"` });
        }
      }

      // Bottom bookmark expectations: should show only after first real branching has been reached in THIS path.
      // We implement the same idea here: only expect bottom to show if we’ve already encountered any real choice page.
      const pathHasBranch = state.path.some(id => isRealChoiceSection(id));
      if (pathHasBranch) {
        if (!ui.bottom) {
          failures.push({ type: "UI", where: state.at, msg: "Missing bottom bookmark (.bookmark-link) after branching began" });
        } else if (ui.bottom.display === "none") {
          failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark hidden but should be visible after branching began" });
        } else {
          if (!ui.bottom.text.includes(expectedBackText(lastN))) {
            failures.push({ type: "UI", where: state.at, msg: `Bottom back text mismatch: got "${ui.bottom.text}", expected to include "${expectedBackText(lastN)}"` });
          }
        }
      }
    } else {
      // No lastChoice yet → top should be disabled and bottom should be hidden
      if (ui.top && !ui.top.disabled) failures.push({ type: "UI", where: state.at, msg: "Top back enabled before any real choice encountered" });
      if (ui.bottom && ui.bottom.display !== "none") failures.push({ type: "UI", where: state.at, msg: "Bottom bookmark visible before any real choice encountered" });
    }

    // Enqueue next states based on outgoing links
    const targets = outDegree.get(state.at) || [];
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
    notes.push(`Stopped early at ${states} states (maxStates=${maxStates}). If you have huge branching, bump maxStates.`);
  }

  await browser.close();

  // Report
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
    for (const f of failures.slice(0, 200)) {
      console.log(`- [${f.type}] @ ${f.where}: ${f.msg}`);
    }
    if (failures.length > 200) console.log(`(Showing first 200 of ${failures.length})`);
    process.exit(2);
  }
})().catch(err => {
  console.error("\nQA script error:", err);
  process.exit(3);
});
//------------------------------------------