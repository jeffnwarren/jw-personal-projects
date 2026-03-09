# jw-personal-projects — Claude Code Instructions

## Repo Overview
Personal projects and utility scripts. Each subdirectory is an independent project.

## Project Registry

| Project | Description | Status | HANDOFF |
|---------|-------------|--------|---------|
| [zorin-os-script](zorin-os-script/) | Bash script to tune a fresh Zorin OS 18 VM (VMware Fusion) for dev use — packages, performance, security | Active | [HANDOFF.md](zorin-os-script/HANDOFF.md) |
| [ova_rename](ova_rename/) | Scripts to rename a VMware OVA and all its internal references: `rename-ova-on-mac.zsh` (macOS/zsh) and `rename-ova-on-linux.sh` (Linux/bash) | Stable | — |
| [gamebooks](gamebooks/) | Conversion of classic gamebooks (EQ series) to playable HTML + Playwright QA tooling | Active | — |
| [My_AI_Interactions](My_AI_Interactions/) | Cross-project notes and patterns from AI-assisted dev sessions | Reference | — |

## Session Workflow

### Start of session
- Check the project's `HANDOFF.md` (if one exists) before starting work.
- Note current state and open TODOs.

### During the session
- Update the `HANDOFF.md` as work happens — don't batch at the end.
- Check off completed TODOs immediately.

### End of session
- Update the relevant `HANDOFF.md`: current state, any new TODOs, decisions made.
- Commit open work.
- Review the session for anything worth adding to [My_AI_Interactions/effective-ai-interaction-patterns.md](My_AI_Interactions/effective-ai-interaction-patterns.md). Candidates include:
  - A question or reframing that led to a meaningfully better solution
  - A prompting technique or workflow that worked especially well
  - A design or architecture decision with transferable reasoning
  - A mistake caught or avoided that generalizes beyond this project
  If something qualifies, add it as a new pattern or strengthen an existing one.
- Review the session for anything that may warrant updating this file (project registry, repo conventions). Do NOT update the Session Workflow section autonomously. Instead, add dated entries to the `## Pending Considerations` section below for review.

## Repo Conventions
- Root `.gitignore` covers all projects: `.DS_Store`, `Thumbs.db`, `__MACOSX/`, `.vscode/`, `.claude/settings.local.json`
- Per-project `.gitignore` files for project-specific rules only (e.g. `node_modules/`)
- Shell scripts should have the git executable bit set (mode 100755)

## Pending Considerations
> Candidates for promoting to Project Registry, Repo Conventions, or Session Workflow.
> Review each entry and either promote it to the relevant section or delete it.
> Do NOT act on these automatically — they require deliberate review.

<!-- Add dated entries below this line -->
