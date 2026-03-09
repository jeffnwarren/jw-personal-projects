# Effective AI Interaction Patterns
### Lessons from real collaboration sessions

These patterns are drawn from real moments across multiple AI-assisted development sessions. They cover what actually worked — not generic advice, but specific behaviours that led to better outcomes. The underlying principle throughout: AI tools work best when the human brings domain knowledge, historical context, and real-world observation.

---

## Starting a Session

### 1. Set up session context before the session starts

**What I did:**
> Created a `CLAUDE.md` at the root of the repo with a project registry, session workflow, and repo conventions. Claude Code auto-reads this file at the start of every session.

**Why it worked:**
Pattern 2 below describes manually pointing the AI at context within a session. This is the step before that: building infrastructure so the context loads automatically and doesn't depend on remembering to ask. Each session starts already oriented — what projects exist, what state they're in, what conventions apply — without any setup work.

**The pattern:**
> Invest time once in a session bootstrap file (CLAUDE.md, copilot-instructions.md, or equivalent). The payoff is every future session starting grounded rather than blank.

The bootstrap file should cover: what the repo/project is, what's currently active, and any conventions the AI should follow throughout.

---

### 2. Point the AI at your context before asking questions

**What I did:**
> "Can you read through the HANDOFF.md, and then I have some input"

**Why it worked:**
Asking the AI to read relevant documentation *before* jumping into questions grounds every answer in your actual project rather than generic assumptions. The AI will otherwise fill gaps with reasonable defaults that may not match your setup at all.

**The pattern:**
> "Read [HANDOFF.md / README / this context doc] first, then I have questions."

One front-loaded read buys better answers for the entire session.

---

### 3. Connect observations across sessions

> *"I am fairly certain a previous AI session removed narration from the book."*

You remembered something from a separate session, connected it to the current topic, and flagged it as a hypothesis rather than a certainty. That led to actually checking the HTML, which confirmed: the narration toggle was gone from the Options panel, but all the underlying JavaScript was intact — a complete picture that wouldn't have emerged without your historical context.

AI sessions are stateless by default. You are the continuity. Your long-term awareness of the project — even uncertain memories ("I'm fairly certain...") — is a capability the AI genuinely doesn't have.

**The pattern:**
> Surface memories from previous sessions, even uncertain ones. You are the thread that connects otherwise isolated conversations.

---

## Framing Requests

### 3. Evaluate before implementing

**What I did:**
> "Let me know what you think of this idea (I'm not sure if it is a good idea or not)..."
> "If you have suggestions for an even more improved strategy let me know (before you implement)"

**Why it worked:**
Describing an idea, flagging your own uncertainty, and asking for evaluation rather than immediate implementation lets the AI confirm the concept, suggest improvements, and explain tradeoffs — all before any code is written. Asking "do you think this is worth doing?" produces a more honest answer than "do this," because it gives the AI permission to say "actually, not really."

**The pattern:**
> "Here's my idea. Is this a good approach, or do you see a better way? Tell me before you code it."

Once code exists, there's psychological inertia to keep it. This is faster than implementing something, finding it's suboptimal, and then redoing it.

---

### 4. Think out loud about the "why" — not just the "what"

**What I did:**
> "Should there be an option flag to auto clean the download folder after successful run? Or does that not really matter if the program knows what file to look for?"

**Why it worked:**
Instead of just asking "add an auto-clean flag," I described the concern behind it and then questioned my own assumption. The AI was able to address both the feature request AND the underlying concern — confirming that the snapshot/diff approach means old files never cause confusion, so auto-clean is a tidiness feature rather than a correctness one.

**The pattern:**
> "I'm thinking about [feature]. My concern is [reason]. Does that concern actually exist, or am I solving a non-problem?"

---

### 5. Separate "can you do this?" from "do this now"

**What I did:**
> "I don't want to push them into CIC yet but just wondering if you're able to do that."
> "Just add to handoff."

**Why it worked:**
Scoping questions cleanly — asking about feasibility without triggering implementation — prevents accidentally building something you're not ready to use. In the other direction, constraining scope ("just add it here", "don't create a new file") prevents the AI's tendency to generate new artifacts when updating an existing thing is more appropriate.

**The pattern:**
> "Is this technically possible, and what would it require? I'm not ready to use it yet."

Every new artifact the AI creates is something you have to track, version, and eventually reconcile. Less is often more.

---

### 6. Name the problem even when you can't diagnose it

**What I did:**
> "Maybe not parity in PC and mobile, or something up with Playwright Chromium showing old features? I don't know."
> "Sorry I'm confused on how to approach."

**Why it worked:**
Sharing incomplete hypotheses alongside your uncertainty gives the AI a direction to investigate while making clear that the diagnosis is open. And when you're genuinely confused, naming the confusion invites the AI to organize the choices rather than leaving you to pick from an unclear set.

**The pattern:**
> "I noticed X. My instinct is Y. Does that make sense, or is there a better way?"
> "I'm not sure how to think about this. Can you frame the options for me?"

Confusion is information. Your guesses, even wrong ones, narrow the search space.

---

### 7. Bring concrete evidence

**What I did:**
> *Attached screenshots of the Options panel instead of describing what looked wrong.*
> *Pasted the exact command and exact error output when something failed.*

**Why it worked:**
A screenshot turned a vague "the font slider looks weird" into three specific findings. An exact command + exact error output is the most efficient path to a diagnosis — one message with all three (command, error, expectation) is worth five back-and-forth exchanges.

**The pattern:**
> Attach screenshots instead of describing. Paste exact commands and exact errors. Images and logs contain information you didn't know was relevant.

AI can only reason about what you tell it. Concrete evidence collapses ambiguity.

---

### 8. Share real-world constraints explicitly

**What I did:**
> "I think the minimum initial wait for any file sent in to CIC is 30 seconds."

**Why it worked:**
This single piece of domain knowledge changed the algorithm design completely. Instead of building a formula that looked elegant on paper but started checking too early, the polling strategy used the real-world floor as its starting point.

**The pattern:**
> When you know something concrete about how your system behaves — timing, limits, edge cases — say it explicitly. Don't assume the AI can infer it.

---

## What to Watch For During Work

### 9. Trust your eyes — then verify the result

> *"I watched --headed on my Windows PC and saw little gray arrows... I thought it was weird."*

You noticed something that looked wrong, and you said so — even though you couldn't fully explain it yet. That observation led directly to uncovering a real bug.

Later, after a "fix" was committed, you checked the actual GitHub URL and found the file was still there. Terminal output can be truncated or misleading. Direct verification is the only way to be sure.

**The pattern:**
> When something looks off, say so — even vaguely. "This seems weird" is a valid prompt.
> After any fix or cleanup, verify by looking at the actual output — the rendered page, the live URL, the file listing — not just the commit message.

AI-generated output can be technically correct and still be wrong in context. Your eyes on the actual running software are a check that automated testing cannot replace.

---

### 10. Flag inconsistencies — in naming, in code, in decisions

**What I did:**
> "I forgot we got rid of qa mode from gamebook!"
> "What about --autoclean for the download folder. Should we add the similar options we did to remove ambiguity?"

**Why it worked:**
Your sense of what *should* be true, based on decisions made earlier, is valuable even when you can't verify it immediately. And when you add or rename something, scanning for similar things that should now match catches inconsistencies while they're cheap to fix.

**The pattern:**
> Flag anything that doesn't match what you remember deciding. Check that new additions follow established naming patterns. Consistency is cheap to fix early and expensive to fix later.

---

### 11. Think about shared-repo impact before accepting changes

**What I did:**
> "Wait a minute — what about the gitignore that is at same level as the FedEx folder level — if this branch ever gets merged to main would it overwrite anything important?"

**Why it worked:**
The AI had just added a root `.gitignore` to solve a local problem. Pausing to ask about the downstream merge consequence caught a real issue — main had its own `.gitignore` with different content.

**The pattern:**
> Before accepting any change to shared infrastructure (gitignore, config, CI), ask: "If this branch were merged to main today, what would it affect for other contributors?"

---

### 12. Trust your organizational instincts

**What I did:**
> "Can the 997s be put in a 997 subfolder under verify folder? And can the files that were source files be placed in a subfolder called 'sourcefiles' under the verify? Just thinking of organization."

**Why it worked:**
I almost dismissed this ("Maybe I'm overthinking it") but surfaced it anyway. The folder reorganization made the runs immediately more navigable.

**The pattern:**
> Organizational ideas that feel like "maybe I'm overthinking it" are usually worth a quick ask. Implementation cost is usually low; navigation benefit is ongoing.

---

### 13. Check that code and documentation actually match

**What I did:**
> "997 generation option isn't documented in the readme? Isn't it --gen997?"

**Why it worked:**
A feature existed in the script but wasn't in the user-facing README. That kind of cross-referencing — checking whether what the code does and what the docs say actually match — is a habit developers often skip. The AI won't automatically audit this unless you ask.

**The pattern:**
> When a feature is added, explicitly ask: "Is this fully documented? Are the README, HANDOFF, and help text all consistent with the code?"

---

## Stepping Back

### 14. Ask "anything else?" at stopping points

> *"Great! Anything else at all you think would be good additions?"*

Several of the most valuable items in these sessions — JS console error detection, single-choice section checks, scroll-to-top verification, reachable endings checks — came from open-ended questions that invited the AI to surface things it hadn't been asked about directly.

**The pattern:**
> At logical stopping points, ask "anything else?", "what am I missing?", or "what would you add?" AI tools tend to answer the question asked and stop. Explicitly inviting broader thinking opens the door to unprompted observations.

---

### 15. Think about who will read the output

**What I did:**
> "And that JSON report — could that have an option or also be automatically converted to an Excel file (for higher-ups review)..."
> "At some point the QA checker will need its own README. It has really grown."

**Why it worked:**
Thinking beyond the immediate technical artifact — who else will read this, and what do they need — shaped the entire report design: JSON as the durable format, CSV as the readable export, SHA-256 checksums for provable evidence. And recognizing when a project has outgrown its current structure catches maintenance debt before it accumulates.

**The pattern:**
> "Who else will read this, and what do they need to trust or act on it?"
> Periodically ask: "What does this mean for how we manage this going forward?"

Engineers want structured data. Managers want readable summaries. Auditors want provable evidence.

---

### 16. Restate key decisions to confirm understanding

**What I did:**
> "So we're not keeping runs on github, right?"

**Why it worked:**
Asked after several commits and gitignore changes, this one-sentence confirmation clarified both the current state and the future plan. This is especially useful when multiple things changed in the same area, or you'll need to explain the decision to someone else later.

**The pattern:**
> After a complex sequence of changes, restate your understanding as a question: "So the result is X — is that right?"

---

## Wrapping Up

### 17. Capture context before ending a session

**What I did:**
> "I'm going to make a backup of this project directory. Is there any additional information such a HANDOFF doc or something that should be made?"

**Why it worked:**
The AI has full context right now. Five minutes spent documenting that context will save thirty minutes of re-explanation later.

**The pattern:**
> "Before I stop — what information should be captured so this project can resume smoothly next time?"

Do this at the end of any substantial session.

---

### 18. Ask the meta-question

**What I did:**
> "If you think I asked any intelligent questions or suggestions anywhere in this chat that can help me learn better how to interact with AI, please put them in my notes."

**Why it worked:**
Reflecting on the *interaction itself* — not just the work product — is a high-leverage habit. Most people only use AI to do tasks. Occasionally asking "what did I do well in how I framed things?" turns the AI into a coach rather than just a tool.

**The pattern:**
> At the end of a productive session, ask: "What did I do in how I asked questions that worked well? What could I have framed better?"

This is how this document came to exist.

---

### 19. Let content scope determine organizational location

**What I did:**
> Moved `My_AI_Interactions/` from inside `gamebooks/` to the repo root after noticing that its content drew from multiple projects (gamebooks, EDI processing, git workflows) — not just gamebooks.

**Why it worked:**
Where a file lives is a signal about who it belongs to. A cross-project reference doc inside a single project folder creates a false impression that it's project-specific, and people working on other projects won't look for it there.

**The pattern:**
> Ask "who is the real audience for this, and where would they naturally look?" A file that belongs to one project lives in that project's folder. A file that belongs to everyone lives at the root.

This applies beyond files: shared config, conventions, and tooling should also live at the scope that reflects their actual reach.

---

## The Underlying Principle

The most effective moments across these sessions weren't "tell me what to do" exchanges — they were genuine back-and-forth. You bring observations, memories, domain knowledge, and real-world constraints. The AI brings breadth, implementation, and systematic analysis. The interface between those two things is where the most useful work happens.

---

## Quick Reference

| Phase | Pattern | One-liner |
|-------|---------|-----------|
| **Start** | Session bootstrap | Invest once in a CLAUDE.md / instruction file so every session starts grounded. |
| **Start** | Point AI at context | "Read the HANDOFF.md first, then I have questions." |
| **Start** | Connect across sessions | Surface memories from previous sessions, even uncertain ones. |
| **Frame** | Evaluate before implementing | "What do you think — before you write any code?" |
| **Frame** | Surface the why | "My concern is X. Is that actually a real concern?" |
| **Frame** | Scope the question | "Can you do this? I'm not ready to use it yet." |
| **Frame** | Name confusion | "I'm not sure how to think about this — frame the options?" |
| **Frame** | Bring evidence | Screenshots and exact error output beat descriptions. |
| **Frame** | Share constraints | State real-world timing, limits, and edge cases explicitly. |
| **Watch** | Trust your eyes, verify outputs | Check the actual result, not the commit message. |
| **Watch** | Flag inconsistencies | Notice when new changes break established patterns. |
| **Watch** | Think about shared impact | "If this merged to main today, what would it affect?" |
| **Watch** | Voice organizational instincts | Small polish ideas are usually cheap and worth asking. |
| **Watch** | Cross-check code vs. docs | "Is this fully documented?" whenever a feature is added. |
| **Step back** | Ask "anything else?" | Invite unprompted observations at stopping points. |
| **Step back** | Think about consumers | "Who will read this output? What format do they need?" |
| **Step back** | Confirm key decisions | Restate important decisions back as a question. |
| **Wrap up** | Document at end of session | "What should we capture before I stop?" |
| **Wrap up** | Ask the meta-question | "What did I do well? What could I improve?" |
| **Organize** | Scope drives location | A file that belongs to everyone lives at the root, not inside one project. |

---

*Consolidated from multiple AI-assisted development sessions. Last updated: March 9, 2026*
