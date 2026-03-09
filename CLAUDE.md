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

## Repo Conventions
- Root `.gitignore` covers all projects: `.DS_Store`, `Thumbs.db`, `__MACOSX/`, `.vscode/`, `.claude/settings.local.json`
- Per-project `.gitignore` files for project-specific rules only (e.g. `node_modules/`)
- Shell scripts should have the git executable bit set (mode 100755)
