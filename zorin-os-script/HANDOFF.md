# zorin-os-script — Handoff

## What This Is
`zorin-tune.sh` is an interactive bash script that tunes a fresh Zorin OS 18 VM (VMware Fusion) for use as a dev workstation with VS Code + Claude Pro. It covers three areas:
1. **Package management** — system update, install Git, Python 3, Node.js LTS, VS Code, Sublime Text, GitHub CLI; remove bloat
2. **Performance** — swappiness, I/O scheduler, GNOME optimizations, open-vm-tools, CPU governor, tmpfs, disable suspend/hibernate
3. **Security** — UFW, SSH hardening, fail2ban, AppArmor, rkhunter, sysctl hardening

Run with `sudo ./zorin-tune.sh` (interactive) or `sudo ./zorin-tune.sh -y` (unattended). See script header for full usage.

## Current State
Script is functional and covers the three areas above. Visual effects/animations section is incomplete (see TODOs). Claude Pro + VSCode wiring instructions are not yet in the script.

## TODOs
- [ ] **Disable animations/visual effects** — Add a section to the script that disables:
  - Window open/close animations via Zorin Appearance (or `gsettings set org.gnome.desktop.interface enable-animations false`)
  - Gelatin (wobble) effect if enabled
  - Transparency effects
  - Consider switching to non-floating panel layout to reduce GPU load
  - *Trigger:* "Enable Automations" was still on after running the script; this section is missing
- [ ] **VSCode + Claude Pro + Git wiring instructions** — Add a post-install section or README note covering:
  - Setting up the Claude Code VS Code extension with a Claude Pro account
  - Linking VS Code to GitHub (SSH key or GitHub CLI auth)
  - Terminal git config (name, email, default branch)
  - Both Claude Pro and GitHub are associated with the Google account
- [ ] **Verify animations are fully suppressed** — After adding the animations section, test on a fresh VM to confirm all visual effects are off post-run

## Key Context for AI Sessions
- The script is idempotent-ish — most sections check before applying, but `--restore` is available for rollback
- Target environment: Zorin OS 18 Core, VMware Fusion, used as a dev VM (not bare metal)
- The script prompts Y/N for each section interactively; `-y` skips prompts
- `zorin-tune.sh` should be `chmod +x` — executable bit is set in git (mode 100755)
