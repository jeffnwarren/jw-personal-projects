# AI Interaction Lessons Learned

**Purpose:** A running record of effective strategies for working with AI coding assistants. Captured from real project interactions so they can be applied to future projects.

---

## Session 1 — 2026-02-22: Project Kickoff

### What Went Well

**1. Providing a thorough handoff document**
Before starting, you had a detailed `gamebook-qa-handoff-5.md` that documented: current state, architecture, known issues, prioritized next steps, and future considerations. This is the single most effective thing you can do when starting an AI session. It gives the AI complete context in one read, preventing the back-and-forth of "what does this do?" and "where is that?"

> **Takeaway:** For any non-trivial project, maintain a handoff document. It pays for itself immediately.

**2. Asking about model selection before starting work**
You asked which model (Sonnet vs Opus) to use and whether you could switch mid-session. This shows good resource awareness — different models have different strengths and costs. Asking upfront avoids wasted tokens on an underpowered model or unnecessary expense on an overpowered one.

> **Takeaway:** When starting a session, ask: "What model fits this task?" The answer may be different for different phases of the same project.

**3. Requesting an incremental approach ("probably not big bang")**
You correctly identified that trying to implement everything in one pass would likely fail. This is a common failure mode with AI: asking for too much at once leads to subtle bugs, lost context, and code that doesn't integrate well. Your instinct to break it up was exactly right.

> **Takeaway:** Break large tasks into phases. Complete and test each phase before starting the next. AI works best with focused, well-scoped tasks.

**4. Asking the AI to maintain project documents**
Requesting handoff updates and this learning document means the project state stays current across sessions. Without this, each new session starts from a stale snapshot and risks duplicating or contradicting earlier work.

> **Takeaway:** Explicitly ask the AI to update project documents as decisions are made and work is completed.

**5. Asking all setup questions in one message**
You combined five related requests (explore, recommend model, plan approach, update handoff, create learning doc) into a single message. This is efficient — the AI can address all of them with full context rather than piecemeal.

> **Takeaway:** When you have multiple related questions, batch them. The AI can answer them more coherently together than separately.

---

## General Principles (to be expanded across sessions)

### Scoping Requests
- **Be specific about what "done" looks like.** "Add the feature presence audit" is good. "Make the script better" is not.
- **State constraints upfront.** "Don't modify the BFS logic" or "Keep backward compatibility with the current CLI flags" prevents the AI from making unwanted changes.
- **One logical task per request.** If two features are independent, make them separate requests so each can be reviewed and tested in isolation.

### Reviewing AI Output
- **Always run the code.** AI-generated code may look correct but have subtle runtime issues. Run it before moving on.
- **Read diffs, not just the final file.** Understanding what changed (and what didn't) is faster and more reliable than re-reading the whole file.
- **Test edge cases the AI might miss.** AI tends to handle the happy path well but may overlook boundary conditions specific to your data.

### Context Management
- **The AI forgets between sessions.** Everything important must be written down in files that persist (handoff docs, CLAUDE.md, this document).
- **Long sessions lose context too.** Even within a session, very long conversations can cause the AI to "forget" earlier decisions. Periodically confirm current state matches expectations.
- **If the AI seems confused, re-state the current goal clearly.** Don't assume it remembers the nuance of a request from 20 messages ago.

### Workflow and Cost Management
- **Know your tool's limits.** Claude Code's Bash tool has a 10-minute timeout. A 25-minute QA run will be killed. The fix: you run long processes locally, the AI writes the code.
- **Divide labor by cost.** AI writes, you test. Watching a terminal for 25 minutes burns tokens for zero value. Paste back the summary or failures — that's all the AI needs.
- **Ask about runtime costs before starting.** "Would this eat up usage?" is a great question. The answer might change your workflow (as it did here — you'll run QA locally instead of having Claude do it).
- **Don't optimize prematurely.** Asking "should we speed this up first?" shows good instinct, but the answer was "profile first, optimize second." Apply this pattern generally: measure before guessing.
- **Commit after testing, not before.** Don't push code you haven't run. The workflow is: AI writes → you test → confirm clean → commit → push.

### Knowing What the AI Can Access
- **Ask what the AI can read directly.** Instead of copying output into the chat, ask: "Can you read this file?" Claude Code can read any file on disk — log files, build output, screenshots. Pasting wastes your time and the AI's context window.
- **Grayed-out files in VS Code are gitignored, not invisible.** The AI can still read them. Gitignore affects version control, not the AI's file access.

### Documentation Persistence
- **Redundant documentation requests are fine.** If you've been burned by lost context, asking the AI to keep documents updated is the right response. Better to over-document than to lose work.
- **Handoff docs are session insurance.** If a session dies mid-work, the handoff captures where you left off. Each new session reads it and picks up seamlessly.
- **This learning doc is curated, not a transcript.** Not every exchange gets added — only patterns that would help on a different project. The filter: Is it reusable? Is it a pattern? Did it change the workflow?

---

*This document will be updated as new patterns and lessons emerge from future sessions.*
