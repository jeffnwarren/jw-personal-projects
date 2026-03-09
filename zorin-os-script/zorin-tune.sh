#!/usr/bin/env bash
#
# ============================================================================
#  zorin-tune.sh — Performance & Security Tuning for Zorin OS 18 (VM)
# ============================================================================
#
#  QUICK START
#  -----------
#    chmod +x zorin-tune.sh
#    sudo ./zorin-tune.sh            # Interactive (prompts Y/N for each item)
#    sudo ./zorin-tune.sh --dry-run  # Preview changes without applying
#    sudo ./zorin-tune.sh -y         # Unattended — apply ALL items
#    sudo ./zorin-tune.sh --restore  # Restore from most recent backup
#
#  DESCRIPTION
#  -----------
#    Analyzes and hardens a Zorin OS 18 VM (VMware Fusion) for use as a
#    development workstation with VS Code + Claude Pro. Covers three areas:
#
#    1. PACKAGE MANAGEMENT — system update, install dev tools (Git, Python 3,
#       Node.js LTS, VS Code, Sublime Text, GitHub CLI), replace Flatpaks with
#       apt equivalents, remove bloat.
#
#    2. PERFORMANCE — swappiness, I/O scheduler, unnecessary services,
#       open-vm-tools, sysctl network tuning, CPU governor, preload,
#       tmpfs /tmp, GNOME desktop optimization (incl. screen lock + animations),
#       journald limits, fstrim, apt cache cleanup, disable suspend/hibernate.
#
#    3. SECURITY — UFW firewall, SSH hardening, fail2ban, unattended
#       upgrades, sysctl hardening, AppArmor, IPv6 disable, rkhunter,
#       SUID/SGID audit.
#
#    Each item is prompted individually (Y/N). All changes are backed up
#    before modification. A restore script and HANDOFF.md are auto-generated.
#
#  USAGE
#  -----
#    ./zorin-tune.sh [OPTIONS]
#
#    Options:
#      -y, --unattended   Apply all improvements without prompting.
#      --dry-run           Show what would be done; make no changes.
#      --restore           Restore from the most recent backup.
#      -h, --help          Show this help message and exit.
#
#  DIRECTORY STRUCTURE (created automatically)
#  -------------------------------------------
#    ~/scripts/
#    ├── backups/
#    │   └── zorin-tune_<timestamp>/
#    │       ├── zorin-tune-restore.sh
#    │       └── <backed-up config files>
#    ├── logs/
#    │   └── zorin-tune_<timestamp>.log
#    ├── HANDOFF.md
#    └── zorin-tune_<timestamp>.zip   ← single archive of everything above
#
#  NOTES
#  -----
#    - Designed for Zorin OS 18 Core on VMware Fusion (VMware20,1).
#    - Auto-elevates to root via sudo if not already running as root.
#    - Restore script is generated per-run with only changes that were made.
#    - SSH password auth is NOT disabled by default to prevent lockout.
#    - Network adapter should be vmxnet3 (paravirtualized). The companion
#      vmware-fusion-setup.sh handles this on the host side.
#    - ulm.disableMitigations = "TRUE" is set in .vmx (host-side perf choice).
#
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & globals
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="zorin-tune"
readonly SCRIPT_VERSION="2.2.0"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME}.lock"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S_%Z)"
readonly TIMESTAMP

# Resolve the real (non-root) user's home directory, even under sudo
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    REAL_USER="$(whoami)"
    REAL_HOME="$HOME"
fi
readonly REAL_USER
readonly REAL_HOME

readonly BASE_DIR="$REAL_HOME/scripts"
readonly BACKUP_DIR="$BASE_DIR/backups/${SCRIPT_NAME}_${TIMESTAMP}"
readonly LOG_DIR="$BASE_DIR/logs"
readonly LOG_FILE="$LOG_DIR/${SCRIPT_NAME}_${TIMESTAMP}.log"
readonly RESTORE_SCRIPT="$BACKUP_DIR/${SCRIPT_NAME}-restore.sh"
readonly HANDOFF_FILE="$BASE_DIR/HANDOFF.md"

UNATTENDED=false
DRY_RUN=false
RESTORE_MODE=false
CHANGES_MADE=0
CHANGES_SKIPPED=0
CHANGES_FAILED=0
CHANGES_ALREADY=0
ROLLBACKS=0

# Track items for restore script and HANDOFF.md
declare -a RESTORE_COMMANDS=()
declare -a APPLIED_ITEMS=()
declare -a SKIPPED_ITEMS=()
declare -a FAILED_ITEMS=()
declare -a ALREADY_ITEMS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
    sed -n '/^#  QUICK START/,/^# ====/p' "$0" | sed 's/^#//' | sed 's/^ //'
    exit 0
}

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    local line="[$ts] [$level] $msg"
    echo "$line" >> "$LOG_FILE"
    case "$level" in
        INFO)    echo -e "\033[0;32m[✓]\033[0m $msg" ;;
        SKIP)    echo -e "\033[0;33m[–]\033[0m $msg" ;;
        WARN)    echo -e "\033[0;33m[!]\033[0m $msg" ;;
        ERROR)   echo -e "\033[0;31m[✗]\033[0m $msg" ;;
        DRY)     echo -e "\033[0;36m[D]\033[0m (dry-run) $msg" ;;
        *)       echo "    $msg" ;;
    esac
}

prompt_yn() {
    local question="$1"
    if $UNATTENDED; then
        return 0
    fi
    while true; do
        read -rp "$question [Y/n]: " ans
        case "${ans,,}" in
            y|yes|"") return 0 ;;
            n|no)     return 1 ;;
            *)        echo "Please answer y or n." ;;
        esac
    done
}

backup_file() {
    local src="$1"
    if [[ -f "$src" ]]; then
        local dest="$BACKUP_DIR/$(basename "$src").bak"
        if ! $DRY_RUN; then
            cp -a "$src" "$dest"
            log INFO "  Backed up $src → $dest"
        else
            log DRY "  Would back up $src → $dest"
        fi
    fi
}

add_restore() {
    RESTORE_COMMANDS+=("$1")
}

abort_prompt() {
    local msg="$1"
    log ERROR "$msg"
    if ! $UNATTENDED; then
        read -rp "A failure occurred. Abort the script? [Y/n]: " ans
        case "${ans,,}" in
            n|no) log WARN "Continuing after failure..." ;;
            *)
                write_restore_script
                write_handoff
                write_log_summary
                log INFO "Aborting. Log: $LOG_FILE"
                exit 1
                ;;
        esac
    else
        log WARN "Unattended mode — continuing after failure."
    fi
}

# ---------------------------------------------------------------------------
# Apply a single tuning item with rollback support
#   apply_item <id> <description> <check_fn> <apply_fn> <rollback_fn>
# ---------------------------------------------------------------------------
apply_item() {
    local id="$1"
    local desc="$2"
    local check_fn="$3"
    local apply_fn="$4"
    local rollback_fn="$5"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $id. $desc"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if already applied
    if $check_fn 2>/dev/null; then
        log INFO "$id. $desc — already in desired state."
        ALREADY_ITEMS+=("$id. $desc")
        ((CHANGES_ALREADY++)) || true
        return 0
    fi

    if $DRY_RUN; then
        log DRY "Would apply: $id. $desc"
        return 0
    fi

    if prompt_yn "Apply: $desc?"; then
        if $apply_fn; then
            log INFO "$id. $desc — applied."
            APPLIED_ITEMS+=("$id. $desc")
            ((CHANGES_MADE++)) || true
        else
            log ERROR "$id. $desc — FAILED to apply."
            FAILED_ITEMS+=("$id. $desc")
            ((CHANGES_FAILED++)) || true
            # Attempt rollback
            if [[ -n "$rollback_fn" ]] && $rollback_fn 2>/dev/null; then
                log WARN "$id. $desc — rolled back successfully."
                ((ROLLBACKS++)) || true
            else
                log ERROR "$id. $desc — rollback failed or unavailable."
            fi
            abort_prompt "Failed to apply: $id. $desc"
        fi
    else
        log SKIP "$id. $desc — skipped by user."
        SKIPPED_ITEMS+=("$id. $desc")
        ((CHANGES_SKIPPED++)) || true
    fi
}

# ===========================================================================
#
#   RESTORE SCRIPT GENERATION
#
# ===========================================================================
write_restore_script() {
    if [[ ${#RESTORE_COMMANDS[@]} -eq 0 ]]; then
        return
    fi
    cat > "$RESTORE_SCRIPT" <<'RESTORE_HEADER'
#!/usr/bin/env bash
#
# ============================================================================
#  zorin-tune-restore.sh — Restore Script (auto-generated)
# ============================================================================
#
#  HOW TO USE
#  ----------
#    This script reverses the changes made during a specific zorin-tune.sh run.
#
#    1. Review the commands below to understand what will be restored.
#    2. Run:  sudo ./zorin-tune-restore.sh
#    3. Reboot if prompted.
#
#  Each section corresponds to one change that was applied.
#  Comment out sections you do NOT want to restore.
#
# ============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This restore script must be run as root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

RESTORE_HEADER

    cat >> "$RESTORE_SCRIPT" <<RESTORE_META
# Resolve paths relative to this restore script's location
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RESTORE_LOG="$LOG_DIR/${SCRIPT_NAME}-restore_${TIMESTAMP}.log"

log_restore() {
    local ts
    ts="\$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "[\$ts] \$*" | tee -a "\$RESTORE_LOG"
}

echo "Starting restore from backup: \$SCRIPT_DIR"
log_restore "Restore started"
RESTORE_META

    for cmd in "${RESTORE_COMMANDS[@]}"; do
        echo "" >> "$RESTORE_SCRIPT"
        echo "$cmd" >> "$RESTORE_SCRIPT"
    done

    cat >> "$RESTORE_SCRIPT" <<'RESTORE_FOOTER'

echo ""
log_restore "Restore complete."
echo "You may want to reboot: sudo reboot"
RESTORE_FOOTER

    chmod +x "$RESTORE_SCRIPT"
    log INFO "Restore script generated: $RESTORE_SCRIPT"
}

# ===========================================================================
#
#   RESTORE MODE — find and run the most recent restore script
#
# ===========================================================================
run_restore_mode() {
    local latest
    latest="$(find "$BASE_DIR/backups" -name "${SCRIPT_NAME}-restore.sh" -type f 2>/dev/null \
        | sort -r | head -1)"
    if [[ -z "$latest" ]]; then
        echo "No restore scripts found in $BASE_DIR/backups/"
        exit 1
    fi
    echo "Found most recent restore script: $latest"
    echo ""
    head -30 "$latest" | tail -20
    echo ""
    read -rp "Run this restore script? [y/N]: " ans
    case "${ans,,}" in
        y|yes) exec bash "$latest" ;;
        *)     echo "Aborted."; exit 0 ;;
    esac
}

# ===========================================================================
#
#   LOG SUMMARY
#
# ===========================================================================
write_log_summary() {
    {
        echo ""
        echo "============================================================"
        echo "  SUMMARY"
        echo "============================================================"
        echo "  Applied:       $CHANGES_MADE"
        echo "  Already OK:    $CHANGES_ALREADY"
        echo "  Skipped:       $CHANGES_SKIPPED"
        echo "  Failed:        $CHANGES_FAILED"
        echo "  Rollbacks:     $ROLLBACKS"
        echo "  Backup:        $BACKUP_DIR"
        echo "  Log:           $LOG_FILE"
        if [[ -f "$RESTORE_SCRIPT" ]]; then
            echo "  Restore:       $RESTORE_SCRIPT"
        fi
        echo "  HANDOFF:       $HANDOFF_FILE"
        echo "============================================================"
    } | tee -a "$LOG_FILE"
}

# ===========================================================================
#
#   HANDOFF.md GENERATION
#
# ===========================================================================
write_handoff() {
    cat > "$HANDOFF_FILE" <<HANDOFF_HEADER
# HANDOFF.md — zorin-tune.sh Project

**Last updated:** $(date '+%Y-%m-%d %H:%M:%S %Z')
**Script version:** $SCRIPT_VERSION
**Run mode:** $(if $UNATTENDED; then echo "unattended"; elif $DRY_RUN; then echo "dry-run"; else echo "interactive"; fi)

---

## What This Project Is

A bash script (\`zorin-tune.sh\`) that interactively applies performance tuning,
security hardening, and package management to a Zorin OS 18 VM on VMware Fusion.
Designed for a dev workstation used with VS Code + Claude Pro.

## System Target

| Detail | Value |
|--------|-------|
| OS | Zorin OS 18 Core |
| Hypervisor | VMware Fusion 25H2u1 |
| Hardware | VMware20,1, 5 vCPUs (i9-9880H), 10 GB RAM, NVMe |
| Network | NAT (vmxnet3 adapter) |
| Firmware | EFI |

## Run Results

HANDOFF_HEADER

    # Applied items
    {
        echo ""
        echo "### Applied (${#APPLIED_ITEMS[@]})"
        if [[ ${#APPLIED_ITEMS[@]} -gt 0 ]]; then
            for item in "${APPLIED_ITEMS[@]}"; do
                echo "- [x] $item"
            done
        else
            echo "_None_"
        fi

        echo ""
        echo "### Already in Desired State (${#ALREADY_ITEMS[@]})"
        if [[ ${#ALREADY_ITEMS[@]} -gt 0 ]]; then
            for item in "${ALREADY_ITEMS[@]}"; do
                echo "- [x] $item _(already OK)_"
            done
        else
            echo "_None_"
        fi

        echo ""
        echo "### Skipped by User (${#SKIPPED_ITEMS[@]})"
        if [[ ${#SKIPPED_ITEMS[@]} -gt 0 ]]; then
            for item in "${SKIPPED_ITEMS[@]}"; do
                echo "- [ ] $item"
            done
        else
            echo "_None_"
        fi

        echo ""
        echo "### Failed (${#FAILED_ITEMS[@]})"
        if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
            for item in "${FAILED_ITEMS[@]}"; do
                echo "- [!] $item"
            done
        else
            echo "_None_"
        fi
    } >> "$HANDOFF_FILE"

    cat >> "$HANDOFF_FILE" <<HANDOFF_PATHS

## File Locations

| File | Path |
|------|------|
| Script | $(readlink -f "$0" 2>/dev/null || echo "$0") |
| Log | $LOG_FILE |
| Backup | $BACKUP_DIR/ |
| Restore script | $RESTORE_SCRIPT |

## Key Design Decisions

- **SSH password auth NOT disabled** — user is learning SSH keys. Script adds
  commented-out instructions for switching to key-only auth later.
- **Restore script is auto-generated per-run** — only contains rollback commands
  for changes actually made.
- **Node.js via NodeSource** — distro package is outdated; NodeSource repo
  provides current LTS (v22.x) via apt.
- **Flatpak→apt replacement** — prompted individually per app; won't blindly swap.
- **GNOME optimizations** — reduced animations/effects but kept Zorin theme intact.

## VMware Host-Side Notes

- \`ethernet0.virtualDev = "vmxnet3"\` — paravirtualized adapter, already configured.
  Interface name is \`ens192\` (altname \`enp11s0\`). See \`VMware_Fusion_Host-Side_Setup_Manual.md\`.
- \`ulm.disableMitigations = "TRUE"\` — Spectre/Meltdown mitigations disabled at
  hypervisor level for performance. This is a host-side choice the script doesn't touch.
- Static IP (DHCP reservation) and SSH/NAT port forwarding (port 2222) are
  configured. See \`VMware_Fusion_Host-Side_Setup_Manual.md\` for details.

## TODOs / Future Enhancements

- [ ] SSH key generation helper — interactive walkthrough for ed25519 keys
- [ ] Config file for unattended mode — YAML/key=value to select items
- [ ] Logwatch / weekly log digest
- [ ] Colored --dry-run diff output
- [ ] Checksum verification for backups (sha256)
- [x] SSH/NAT port forwarding setup documentation (see VMware_Fusion_Host-Side_Setup_Manual.md)

## How to Use This File

If you're an AI assistant picking up this project:
1. Read this file first for full context.
2. Check \`$LOG_DIR/\` for run logs.
3. Check \`$BASE_DIR/backups/\` for restore scripts.
4. The requirements doc is \`request_for_performance_and_security_script_v2.txt\`.
HANDOFF_PATHS

    log INFO "HANDOFF.md generated: $HANDOFF_FILE"
}

# ===========================================================================
#
#   PACKAGE MANAGEMENT FUNCTIONS
#
# ===========================================================================

# --- K1. Full system update ------------------------------------------------
check_sysupdate() { return 1; }  # Always offer
apply_sysupdate() {
    log INFO "  Running apt update..."
    apt-get update -qq
    log INFO "  Running apt full-upgrade..."
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq
    add_restore "# Note: System packages were upgraded. Downgrade is not practical.
log_restore 'System update was applied — manual downgrade required if needed.'"
}
rollback_sysupdate() { return 0; }  # Can't downgrade

# --- K2. Install Git -------------------------------------------------------
check_git() { command -v git &>/dev/null; }
apply_git() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
    local ver
    ver="$(git --version 2>/dev/null || echo 'unknown')"
    log INFO "  Git installed: $ver"
    add_restore "# Note: Git was installed. Removing is not recommended.
log_restore 'Git was installed — not removing (recommended to keep).'"
}
rollback_git() { return 0; }

# --- K3. Install Python 3 + pip -------------------------------------------
check_python() {
    command -v python3 &>/dev/null && command -v pip3 &>/dev/null
}
apply_python() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 python3-pip python3-venv
    local ver
    ver="$(python3 --version 2>/dev/null || echo 'unknown')"
    log INFO "  Python installed: $ver"
    add_restore "# Note: Python 3 was installed/verified. Removing is not recommended.
log_restore 'Python 3 was installed — not removing.'"
}
rollback_python() { return 0; }

# --- K4. Install Node.js LTS via NodeSource --------------------------------
check_nodejs() {
    command -v node &>/dev/null && \
    node --version 2>/dev/null | grep -qE '^v(2[0-9]|[3-9][0-9])\.'
}
apply_nodejs() {
    # Remove distro nodejs if present (likely outdated)
    if dpkg -l nodejs 2>/dev/null | grep -q '^ii'; then
        local current_ver
        current_ver="$(node --version 2>/dev/null || echo 'v0')"
        if ! echo "$current_ver" | grep -qE '^v(2[0-9]|[3-9][0-9])\.'; then
            log INFO "  Removing outdated distro Node.js ($current_ver)..."
            apt-get remove -y -qq nodejs 2>/dev/null || true
        fi
    fi

    # Install NodeSource repo and Node.js LTS
    if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]] && \
       [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
        log INFO "  Adding NodeSource repository for Node.js LTS..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl gnupg
        mkdir -p /etc/apt/keyrings
        local tmp_key
        tmp_key="$(mktemp)"
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o "$tmp_key"
        gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg < "$tmp_key"
        rm -f "$tmp_key"
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
            > /etc/apt/sources.list.d/nodesource.list
        apt-get update -qq
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
    local ver
    ver="$(node --version 2>/dev/null || echo 'unknown')"
    log INFO "  Node.js installed: $ver"
    add_restore "# Remove NodeSource Node.js (restores to no Node.js or distro version)
log_restore 'Removing NodeSource Node.js'
apt-get remove -y -qq nodejs 2>/dev/null || true
rm -f /etc/apt/sources.list.d/nodesource.list
rm -f /etc/apt/keyrings/nodesource.gpg
apt-get update -qq"
}
rollback_nodejs() {
    apt-get remove -y -qq nodejs 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/nodesource.list
    rm -f /etc/apt/keyrings/nodesource.gpg
}

# --- K5. Install VS Code via Microsoft apt repo ----------------------------
check_vscode() { command -v code &>/dev/null; }
apply_vscode() {
    # Install prerequisites
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apt-transport-https curl gpg

    # Add Microsoft GPG key
    if [[ ! -f /etc/apt/keyrings/microsoft.gpg ]]; then
        mkdir -p /etc/apt/keyrings
        local tmp_key
        tmp_key="$(mktemp)"
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "$tmp_key"
        gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg < "$tmp_key"
        rm -f "$tmp_key"
    fi

    # Add VS Code repository
    if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            > /etc/apt/sources.list.d/vscode.list
        apt-get update -qq
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq code
    local ver
    ver="$(code --version 2>/dev/null | head -1 || echo 'unknown')"
    log INFO "  VS Code installed: $ver"
    add_restore "# Remove VS Code and Microsoft repo
log_restore 'Removing VS Code'
apt-get remove -y -qq code 2>/dev/null || true
rm -f /etc/apt/sources.list.d/vscode.list
rm -f /etc/apt/keyrings/microsoft.gpg
apt-get update -qq"
}
rollback_vscode() {
    apt-get remove -y -qq code 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/vscode.list
    rm -f /etc/apt/keyrings/microsoft.gpg
}

# --- K6. Replace Flatpaks with apt equivalents -----------------------------
check_flatpak_replace() {
    # Check if any Flatpaks are installed at all
    command -v flatpak &>/dev/null && [[ "$(flatpak list --app 2>/dev/null | wc -l)" -eq 0 ]]
}
apply_flatpak_replace() {
    if ! command -v flatpak &>/dev/null; then
        log INFO "  Flatpak not installed — nothing to replace."
        return 0
    fi

    local flatpak_list
    flatpak_list="$(flatpak list --app --columns=application,name 2>/dev/null || true)"
    if [[ -z "$flatpak_list" ]]; then
        log INFO "  No Flatpak applications installed."
        return 0
    fi

    log INFO "  Installed Flatpaks:"
    echo "$flatpak_list" | while IFS= read -r line; do
        log INFO "    $line"
    done

    # Known Flatpak → apt mappings
    declare -A flatpak_to_apt=(
        ["com.brave.Browser"]="brave-browser"
        ["org.mozilla.firefox"]="firefox"
        ["org.mozilla.Thunderbird"]="thunderbird"
        ["org.gnome.Calculator"]="gnome-calculator"
        ["org.gnome.TextEditor"]="gnome-text-editor"
        ["org.gnome.Evince"]="evince"
        ["org.gnome.FileRoller"]="file-roller"
        ["org.gnome.Logs"]="gnome-logs"
        ["org.gnome.baobab"]="baobab"
        ["org.gnome.font-viewer"]="gnome-font-viewer"
    )

    local replaced=0
    while IFS=$'\t' read -r app_id app_name _rest; do
        app_id="$(echo "$app_id" | xargs)"  # trim whitespace
        if [[ -n "${flatpak_to_apt[$app_id]+x}" ]]; then
            local apt_pkg="${flatpak_to_apt[$app_id]}"
            if prompt_yn "  Replace Flatpak '$app_name' ($app_id) with apt package '$apt_pkg'?"; then
                log INFO "  Removing Flatpak: $app_id"
                flatpak uninstall -y "$app_id" 2>/dev/null || true

                # Brave needs its own repo
                if [[ "$apt_pkg" == "brave-browser" ]]; then
                    if [[ ! -f /etc/apt/sources.list.d/brave-browser-release.list ]]; then
                        log INFO "  Adding Brave Browser apt repository..."
                        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl
                        local tmp_brave
                        tmp_brave="$(mktemp)"
                        curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg -o "$tmp_brave"
                        mv "$tmp_brave" /usr/share/keyrings/brave-browser-archive-keyring.gpg
                        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
                            > /etc/apt/sources.list.d/brave-browser-release.list
                        apt-get update -qq
                    fi
                fi

                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$apt_pkg" 2>/dev/null || {
                    log WARN "  Could not install apt package '$apt_pkg' — Flatpak was already removed."
                }
                ((replaced++)) || true
            fi
        else
            if prompt_yn "  Flatpak '$app_name' ($app_id) has no known apt equivalent. Remove it anyway?"; then
                flatpak uninstall -y "$app_id" 2>/dev/null || true
                ((replaced++)) || true
            fi
        fi
    done <<< "$flatpak_list"

    if [[ $replaced -gt 0 ]]; then
        # Clean up unused Flatpak runtimes
        flatpak uninstall --unused -y 2>/dev/null || true
        log INFO "  Replaced/removed $replaced Flatpak(s)."
    fi
    add_restore "# Note: Flatpaks were replaced with apt packages. Manual reinstall if needed.
log_restore 'Flatpak replacements were made — reinstall Flatpaks manually if needed.'"
}
rollback_flatpak_replace() { return 0; }  # Can't automatically re-install Flatpaks

# --- K7. Remove bloat applications -----------------------------------------
BLOAT_APPS_KNOWN=(
    brasero
    gnome-camera
    gnome-characters
    gnome-clocks
    gnome-contacts
    evolution
    "libreoffice*"
    remmina
    rhythmbox
)

check_bloat_removal() {
    local found=false
    for pkg in "${BLOAT_APPS_KNOWN[@]}"; do
        if dpkg -l $pkg 2>/dev/null | grep -q '^ii'; then
            found=true
            break
        fi
    done
    ! $found
}
apply_bloat_removal() {
    local removed=()
    for pkg in "${BLOAT_APPS_KNOWN[@]}"; do
        if dpkg -l $pkg 2>/dev/null | grep -q '^ii'; then
            log INFO "  Found: $pkg"
            if $UNATTENDED || prompt_yn "  Remove $pkg?"; then
                DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq $pkg 2>/dev/null || true
                removed+=("$pkg")
                log INFO "  Removed: $pkg"
            fi
        fi
    done

    # Look for other potential bloat and prompt individually
    local extra_bloat=(
        gnome-games
        gnome-maps
        gnome-music
        gnome-photos
        gnome-weather
        totem
        shotwell
        simple-scan
        aisleriot
        gnome-mines
        gnome-sudoku
        gnome-mahjongg
        cheese
    )
    for pkg in "${extra_bloat[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            if prompt_yn "  Also found '$pkg' — remove it?"; then
                DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq "$pkg" 2>/dev/null || true
                removed+=("$pkg")
                log INFO "  Removed: $pkg"
            fi
        fi
    done

    if [[ ${#removed[@]} -gt 0 ]]; then
        apt-get autoremove -y -qq 2>/dev/null || true
        local removed_list="${removed[*]}"
        add_restore "# Note: These packages were purged: ${removed_list}
# Reinstall with: sudo apt-get install <package-name>
log_restore 'Bloat packages were removed: ${removed_list}. Reinstall manually if needed.'"
    fi
}
rollback_bloat_removal() { return 0; }  # Can't auto-reinstall purged packages

# --- K8. Install Sublime Text via official apt repo ------------------------
check_sublime() { command -v subl &>/dev/null; }
apply_sublime() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apt-transport-https curl gpg

    if [[ ! -f /etc/apt/keyrings/sublimehq.gpg ]]; then
        mkdir -p /etc/apt/keyrings
        local tmp_key
        tmp_key="$(mktemp)"
        curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o "$tmp_key"
        gpg --dearmor -o /etc/apt/keyrings/sublimehq.gpg < "$tmp_key"
        rm -f "$tmp_key"
    fi

    if [[ ! -f /etc/apt/sources.list.d/sublime-text.list ]]; then
        echo "deb [signed-by=/etc/apt/keyrings/sublimehq.gpg] https://download.sublimetext.com/ apt/stable/" \
            > /etc/apt/sources.list.d/sublime-text.list
        apt-get update -qq
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sublime-text
    local ver
    ver="$(subl --version 2>/dev/null || echo 'unknown')"
    log INFO "  Sublime Text installed: $ver"
    add_restore "# Remove Sublime Text and repo
log_restore 'Removing Sublime Text'
apt-get remove -y -qq sublime-text 2>/dev/null || true
rm -f /etc/apt/sources.list.d/sublime-text.list
rm -f /etc/apt/keyrings/sublimehq.gpg
apt-get update -qq"
}
rollback_sublime() {
    apt-get remove -y -qq sublime-text 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/sublime-text.list
    rm -f /etc/apt/keyrings/sublimehq.gpg
}

# --- K9. Install GitHub CLI (gh) via official apt repo --------------------
check_gh() { command -v gh &>/dev/null; }
apply_gh() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl gpg

    if [[ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]]; then
        local tmp_key
        tmp_key="$(mktemp)"
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$tmp_key"
        mv "$tmp_key" /usr/share/keyrings/githubcli-archive-keyring.gpg
        chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    fi

    if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            > /etc/apt/sources.list.d/github-cli.list
        apt-get update -qq
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh
    local ver
    ver="$(gh --version 2>/dev/null | head -1 || echo 'unknown')"
    log INFO "  GitHub CLI installed: $ver"
    add_restore "# Remove GitHub CLI and repo
log_restore 'Removing GitHub CLI'
apt-get remove -y -qq gh 2>/dev/null || true
rm -f /etc/apt/sources.list.d/github-cli.list
rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
apt-get update -qq"
}
rollback_gh() {
    apt-get remove -y -qq gh 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/github-cli.list
    rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
}

# ===========================================================================
#
#   PERFORMANCE TUNING FUNCTIONS
#
# ===========================================================================

# --- P1. Reduce swappiness (60 → 10) --------------------------------------
check_swappiness() { [[ "$(cat /proc/sys/vm/swappiness)" -le 10 ]]; }
apply_swappiness() {
    backup_file /etc/sysctl.conf
    sysctl -w vm.swappiness=10 > /dev/null
    if grep -q '^vm.swappiness' /etc/sysctl.conf 2>/dev/null; then
        sed -i 's/^vm.swappiness.*/vm.swappiness=10/' /etc/sysctl.conf
    else
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi
    add_restore "# Restore swappiness to default (60)
log_restore 'Restoring vm.swappiness to 60'
sysctl -w vm.swappiness=60
sed -i 's/^vm.swappiness.*/vm.swappiness=60/' /etc/sysctl.conf"
}
rollback_swappiness() {
    sysctl -w vm.swappiness=60 > /dev/null
    if [[ -f "$BACKUP_DIR/sysctl.conf.bak" ]]; then
        cp -a "$BACKUP_DIR/sysctl.conf.bak" /etc/sysctl.conf
    fi
}

# --- P2. I/O scheduler → none (NVMe) --------------------------------------
check_iosched() {
    local sched_file
    sched_file="$(find /sys/block/*/queue -name 'scheduler' 2>/dev/null | head -1)"
    # No scheduler file = VM pass-through, already optimal
    [[ -z "$sched_file" ]] && return 0
    grep -q '\[none\]' "$sched_file"
}
apply_iosched() {
    local sched_file
    sched_file="$(find /sys/block/*/queue -name 'scheduler' 2>/dev/null | head -1)"
    if [[ -z "$sched_file" ]]; then
        log INFO "  No block device scheduler file — VM I/O is already pass-through."
        return 0
    fi
    echo "none" > "$sched_file"
    # Persist via udev rule
    backup_file /etc/udev/rules.d/60-ioscheduler.rules
    echo 'ACTION=="add|change", KERNEL=="nvme[0-9]*|sd[a-z]", ATTR{queue/scheduler}="none"' \
        > /etc/udev/rules.d/60-ioscheduler.rules
    add_restore "# Restore I/O scheduler
log_restore 'Removing I/O scheduler udev rule'
rm -f /etc/udev/rules.d/60-ioscheduler.rules"
}
rollback_iosched() {
    rm -f /etc/udev/rules.d/60-ioscheduler.rules
}

# --- P3. Disable unneeded services ----------------------------------------
UNNECESSARY_SERVICES=(bluetooth ModemManager avahi-daemon cups)
check_services() {
    local all_inactive=true
    for svc in "${UNNECESSARY_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            all_inactive=false
            break
        fi
    done
    $all_inactive
}
apply_services() {
    local stopped=()
    for svc in "${UNNECESSARY_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
            systemctl mask "$svc" 2>/dev/null || true
            stopped+=("$svc")
            log INFO "  Stopped and masked: $svc"
        else
            log INFO "  Already inactive: $svc"
        fi
    done
    if [[ ${#stopped[@]} -gt 0 ]]; then
        local restore_block="# Restore disabled services
log_restore 'Re-enabling previously disabled services'"
        for svc in "${stopped[@]}"; do
            restore_block+="
systemctl unmask $svc 2>/dev/null || true
systemctl enable $svc 2>/dev/null || true
systemctl start $svc 2>/dev/null || true"
        done
        add_restore "$restore_block"
    fi
}
rollback_services() {
    for svc in "${UNNECESSARY_SERVICES[@]}"; do
        systemctl unmask "$svc" 2>/dev/null || true
        systemctl enable "$svc" 2>/dev/null || true
        systemctl start "$svc" 2>/dev/null || true
    done
}

# --- P4. Install/verify open-vm-tools -------------------------------------
check_vmtools() { dpkg -l open-vm-tools 2>/dev/null | grep -q '^ii'; }
apply_vmtools() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq open-vm-tools open-vm-tools-desktop
    add_restore "# Note: open-vm-tools was installed. Removing is not recommended.
log_restore 'open-vm-tools was installed — not removing (recommended to keep).'"
}
rollback_vmtools() {
    apt-get remove -y -qq open-vm-tools open-vm-tools-desktop 2>/dev/null || true
}

# --- P5. Sysctl network tuning --------------------------------------------
check_net_tuning() {
    [[ "$(sysctl -n net.core.rmem_max 2>/dev/null)" -ge 16777216 ]]
}
apply_net_tuning() {
    backup_file /etc/sysctl.d/90-zorin-net.conf
    cat > /etc/sysctl.d/90-zorin-net.conf <<'NET_CONF'
# Network performance tuning — zorin-tune.sh
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.netdev_max_backlog=5000
net.ipv4.tcp_fastopen=3
NET_CONF
    sysctl --system > /dev/null 2>&1
    add_restore "# Restore network sysctl tuning
log_restore 'Removing network sysctl tuning'
rm -f /etc/sysctl.d/90-zorin-net.conf
sysctl --system > /dev/null 2>&1"
}
rollback_net_tuning() {
    rm -f /etc/sysctl.d/90-zorin-net.conf
    sysctl --system > /dev/null 2>&1
}

# --- P6. CPU governor → performance ---------------------------------------
check_cpugov() {
    local gov_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    [[ -f "$gov_file" ]] && [[ "$(cat "$gov_file")" == "performance" ]]
}
apply_cpugov() {
    if ! command -v cpufreq-set &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cpufrequtils 2>/dev/null || true
    fi
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        local gov_file="$cpu_dir/cpufreq/scaling_governor"
        if [[ -f "$gov_file" ]]; then
            echo "performance" > "$gov_file"
        fi
    done
    # Persist
    backup_file /etc/default/cpufrequtils
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
    add_restore "# Restore CPU governor to default
log_restore 'Restoring CPU governor to ondemand'
echo 'GOVERNOR=\"ondemand\"' > /etc/default/cpufrequtils
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo 'ondemand' > \"\$g\" 2>/dev/null || true
done"
}
rollback_cpugov() {
    for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "ondemand" > "$g" 2>/dev/null || true
    done
    if [[ -f "$BACKUP_DIR/cpufrequtils.bak" ]]; then
        cp -a "$BACKUP_DIR/cpufrequtils.bak" /etc/default/cpufrequtils
    fi
}

# --- P7. Install preload daemon --------------------------------------------
check_preload() { dpkg -l preload 2>/dev/null | grep -q '^ii'; }
apply_preload() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq preload
    systemctl enable preload 2>/dev/null || true
    add_restore "# Remove preload
log_restore 'Removing preload'
apt-get remove -y -qq preload 2>/dev/null || true"
}
rollback_preload() {
    apt-get remove -y -qq preload 2>/dev/null || true
}

# --- P8. Mount /tmp as tmpfs -----------------------------------------------
check_tmpfs() { mount | grep -q 'tmpfs on /tmp'; }
apply_tmpfs() {
    backup_file /etc/fstab
    if ! grep -q 'tmpfs.*/tmp' /etc/fstab 2>/dev/null; then
        echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,mode=1777,size=1G 0 0" >> /etc/fstab
        mount -o remount /tmp 2>/dev/null \
            || mount tmpfs /tmp -t tmpfs -o defaults,noatime,nosuid,nodev,mode=1777,size=1G 2>/dev/null \
            || true
    fi
    add_restore "# Remove tmpfs for /tmp
log_restore 'Removing tmpfs mount for /tmp from fstab'
sed -i '/tmpfs.*\/tmp.*tmpfs/d' /etc/fstab"
}
rollback_tmpfs() {
    sed -i '/tmpfs.*\/tmp.*tmpfs/d' /etc/fstab 2>/dev/null || true
}

# --- P9. GNOME desktop optimization ---------------------------------------
check_gnome_opt() {
    # Check if animations are already disabled
    local anim
    anim="$(sudo -u "$REAL_USER" dbus-launch gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null || echo 'true')"
    [[ "$anim" == "false" ]]
}
apply_gnome_opt() {
    log INFO "  Optimizing GNOME desktop settings for VM performance..."

    # Disable animations (biggest visual perf win)
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
    log INFO "  Disabled desktop animations"

    # Reduce font hinting for render speed (keep readable)
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.interface font-hinting 'medium' 2>/dev/null || true

    # Disable hot corners if enabled
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.interface enable-hot-corners false 2>/dev/null || true
    log INFO "  Disabled hot corners"

    # Reduce event sounds
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.sound event-sounds false 2>/dev/null || true
    log INFO "  Disabled event sounds"

    # Disable screen lock and auto screen-blank (VM shouldn't lock itself)
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    log INFO "  Disabled screen lock and auto screen-blank"

    add_restore "# Restore GNOME desktop settings
log_restore 'Restoring GNOME desktop settings'
sudo -u '$REAL_USER' dbus-launch gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
sudo -u '$REAL_USER' dbus-launch gsettings set org.gnome.desktop.interface font-hinting 'full' 2>/dev/null || true
sudo -u '$REAL_USER' dbus-launch gsettings set org.gnome.desktop.interface enable-hot-corners true 2>/dev/null || true
sudo -u '$REAL_USER' dbus-launch gsettings set org.gnome.desktop.sound event-sounds true 2>/dev/null || true
sudo -u '$REAL_USER' dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled true 2>/dev/null || true
sudo -u '$REAL_USER' dbus-launch gsettings set org.gnome.desktop.session idle-delay 300 2>/dev/null || true"
}
rollback_gnome_opt() {
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.interface enable-hot-corners true 2>/dev/null || true
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.sound event-sounds true 2>/dev/null || true
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled true 2>/dev/null || true
    sudo -u "$REAL_USER" dbus-launch gsettings set org.gnome.desktop.session idle-delay 300 2>/dev/null || true
}

# --- P10. Journald log size limit ------------------------------------------
check_journald() {
    grep -q '^SystemMaxUse=200M' /etc/systemd/journald.conf 2>/dev/null
}
apply_journald() {
    backup_file /etc/systemd/journald.conf
    if grep -q '^#\?SystemMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
        sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=200M/' /etc/systemd/journald.conf
    else
        echo "SystemMaxUse=200M" >> /etc/systemd/journald.conf
    fi
    systemctl restart systemd-journald 2>/dev/null || true
    log INFO "  Journald capped at 200 MB persistent storage."
    add_restore "# Restore journald config
log_restore 'Restoring journald config'
cp -a \"\$SCRIPT_DIR/journald.conf.bak\" /etc/systemd/journald.conf 2>/dev/null || true
systemctl restart systemd-journald 2>/dev/null || true"
}
rollback_journald() {
    if [[ -f "$BACKUP_DIR/journald.conf.bak" ]]; then
        cp -a "$BACKUP_DIR/journald.conf.bak" /etc/systemd/journald.conf
        systemctl restart systemd-journald 2>/dev/null || true
    fi
}

# --- P11. Enable fstrim timer (TRIM for NVMe) -----------------------------
check_fstrim() {
    systemctl is-enabled fstrim.timer &>/dev/null
}
apply_fstrim() {
    systemctl enable fstrim.timer 2>/dev/null || true
    systemctl start fstrim.timer 2>/dev/null || true
    log INFO "  fstrim.timer enabled for periodic TRIM."
    add_restore "# Disable fstrim timer
log_restore 'Disabling fstrim.timer'
systemctl stop fstrim.timer 2>/dev/null || true
systemctl disable fstrim.timer 2>/dev/null || true"
}
rollback_fstrim() {
    systemctl stop fstrim.timer 2>/dev/null || true
    systemctl disable fstrim.timer 2>/dev/null || true
}

# --- P12. Apt cache cleanup -----------------------------------------------
check_apt_clean() { return 1; }  # Always offer
apply_apt_clean() {
    apt-get autoremove -y -qq
    apt-get autoclean -y -qq
    log INFO "  Cleaned apt cache and removed orphan packages."
    # No restore needed for cache cleanup
}
rollback_apt_clean() { return 0; }

# --- P13. Disable suspend/hibernate (VM power management) -----------------
check_suspend_disabled() {
    systemctl is-masked sleep.target &>/dev/null && \
    systemctl is-masked suspend.target &>/dev/null
}
apply_suspend_disabled() {
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
    log INFO "  Masked sleep, suspend, hibernate, and hybrid-sleep targets."
    add_restore "# Re-enable suspend/hibernate targets
log_restore 'Unmasking suspend/hibernate targets'
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true"
}
rollback_suspend_disabled() {
    systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
}

# ===========================================================================
#
#   SECURITY TUNING FUNCTIONS
#
# ===========================================================================

# --- S1. UFW firewall ------------------------------------------------------
check_ufw() {
    ufw status 2>/dev/null | grep -q 'Status: active' &&
    ufw status 2>/dev/null | grep -q '22/tcp.*ALLOW'
}
apply_ufw() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    ufw allow ssh > /dev/null
    ufw --force enable > /dev/null
    log INFO "  UFW enabled: default deny incoming, allow SSH (22/tcp)."
    add_restore "# Disable UFW firewall
log_restore 'Disabling UFW'
ufw --force disable"
}
rollback_ufw() { ufw --force disable 2>/dev/null || true; }

# --- S2. SSH server install + hardening ------------------------------------
check_ssh() {
    dpkg -l openssh-server 2>/dev/null | grep -q '^ii' &&
    grep -q '^PermitRootLogin no' /etc/ssh/sshd_config 2>/dev/null
}
apply_ssh() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server
    backup_file /etc/ssh/sshd_config
    local conf="/etc/ssh/sshd_config"

    # Hardening settings — applied via sed for each known directive
    declare -A ssh_settings=(
        [PermitRootLogin]="no"
        [MaxAuthTries]="3"
        [X11Forwarding]="no"
        [PermitEmptyPasswords]="no"
        [ClientAliveInterval]="300"
        [ClientAliveCountMax]="2"
    )
    for key in "${!ssh_settings[@]}"; do
        local val="${ssh_settings[$key]}"
        if grep -qE "^#?${key}\b" "$conf" 2>/dev/null; then
            sed -i "s/^#*${key}.*/${key} ${val}/" "$conf"
        else
            echo "${key} ${val}" >> "$conf"
        fi
    done

    # Add instructions for future key-based auth (don't disable password auth now)
    if ! grep -q '# zorin-tune: password auth note' "$conf"; then
        cat >> "$conf" <<'SSH_NOTE'

# zorin-tune: password auth note
# To switch to key-only authentication (more secure):
#   1. On your Mac, generate a key:
#        ssh-keygen -t ed25519 -C "your-email@example.com"
#   2. Copy it to this server:
#        ssh-copy-id -p <port> jeff@<host>
#   3. Test that key login works, THEN uncomment the line below:
# PasswordAuthentication no
SSH_NOTE
    fi

    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    add_restore "# Restore SSH config
log_restore 'Restoring original sshd_config'
cp -a \"\$SCRIPT_DIR/sshd_config.bak\" /etc/ssh/sshd_config
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true"
}
rollback_ssh() {
    if [[ -f "$BACKUP_DIR/sshd_config.bak" ]]; then
        cp -a "$BACKUP_DIR/sshd_config.bak" /etc/ssh/sshd_config
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    fi
}

# --- S3. Fail2ban for SSH --------------------------------------------------
check_fail2ban() { dpkg -l fail2ban 2>/dev/null | grep -q '^ii'; }
apply_fail2ban() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban
    backup_file /etc/fail2ban/jail.local
    cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 1800
findtime = 600
maxretry = 3

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
F2B
    systemctl enable fail2ban
    systemctl restart fail2ban
    add_restore "# Remove fail2ban
log_restore 'Removing fail2ban'
systemctl stop fail2ban 2>/dev/null || true
apt-get remove -y -qq fail2ban 2>/dev/null || true"
}
rollback_fail2ban() {
    apt-get remove -y -qq fail2ban 2>/dev/null || true
}

# --- S4. Unattended security upgrades -------------------------------------
check_unattended() { dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; }
apply_unattended() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
    # Configure non-interactively
    echo 'Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";' > /etc/apt/apt.conf.d/50unattended-upgrades-zorin 2>/dev/null || true
    add_restore "# Disable unattended-upgrades
log_restore 'Removing unattended-upgrades'
rm -f /etc/apt/apt.conf.d/50unattended-upgrades-zorin
apt-get remove -y -qq unattended-upgrades 2>/dev/null || true"
}
rollback_unattended() {
    rm -f /etc/apt/apt.conf.d/50unattended-upgrades-zorin
    apt-get remove -y -qq unattended-upgrades 2>/dev/null || true
}

# --- S5. Sysctl security hardening ----------------------------------------
check_sysctl_sec() {
    [[ "$(sysctl -n net.ipv4.conf.all.send_redirects 2>/dev/null)" == "0" ]]
}
apply_sysctl_sec() {
    backup_file /etc/sysctl.d/91-zorin-security.conf
    cat > /etc/sysctl.d/91-zorin-security.conf <<'SYSCTL_SEC'
# Security hardening — zorin-tune.sh
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
SYSCTL_SEC
    sysctl --system > /dev/null 2>&1
    add_restore "# Remove security sysctl hardening
log_restore 'Removing security sysctl hardening'
rm -f /etc/sysctl.d/91-zorin-security.conf
sysctl --system > /dev/null 2>&1"
}
rollback_sysctl_sec() {
    rm -f /etc/sysctl.d/91-zorin-security.conf
    sysctl --system > /dev/null 2>&1
}

# --- S6. AppArmor verification ---------------------------------------------
check_apparmor() { aa-status 2>/dev/null | grep -q 'apparmor module is loaded'; }
apply_apparmor() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apparmor apparmor-utils
    systemctl enable apparmor 2>/dev/null || true
    systemctl start apparmor 2>/dev/null || true
    log INFO "  AppArmor status:"
    aa-status 2>/dev/null | head -5 | while read -r line; do log INFO "    $line"; done
    add_restore "# Note: AppArmor was verified/enabled. Disabling is not recommended.
log_restore 'AppArmor was verified — not disabling (recommended to keep).'"
}
rollback_apparmor() { return 0; }

# --- S7. Disable IPv6 (optional) ------------------------------------------
check_ipv6_disabled() {
    [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)" == "1" ]]
}
apply_ipv6_disable() {
    backup_file /etc/sysctl.d/92-disable-ipv6.conf
    cat > /etc/sysctl.d/92-disable-ipv6.conf <<'IPV6'
# Disable IPv6 — zorin-tune.sh
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
IPV6
    sysctl --system > /dev/null 2>&1
    add_restore "# Re-enable IPv6
log_restore 'Re-enabling IPv6'
rm -f /etc/sysctl.d/92-disable-ipv6.conf
sysctl --system > /dev/null 2>&1"
}
rollback_ipv6_disable() {
    rm -f /etc/sysctl.d/92-disable-ipv6.conf
    sysctl --system > /dev/null 2>&1
}

# --- S8. Rkhunter ----------------------------------------------------------
check_rkhunter() { dpkg -l rkhunter 2>/dev/null | grep -q '^ii'; }
apply_rkhunter() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rkhunter
    rkhunter --update 2>/dev/null || true
    rkhunter --propupd 2>/dev/null || true
    local cron_file="/etc/cron.weekly/rkhunter-check"
    cat > "$cron_file" <<'RKH_CRON'
#!/bin/bash
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only --logfile /var/log/rkhunter.log
RKH_CRON
    chmod +x "$cron_file"
    add_restore "# Remove rkhunter
log_restore 'Removing rkhunter'
rm -f /etc/cron.weekly/rkhunter-check
apt-get remove -y -qq rkhunter 2>/dev/null || true"
}
rollback_rkhunter() {
    rm -f /etc/cron.weekly/rkhunter-check
    apt-get remove -y -qq rkhunter 2>/dev/null || true
}

# --- S9. Audit SUID/SGID binaries -----------------------------------------
check_suid_audit() { return 1; }  # Always offer
apply_suid_audit() {
    local audit_file="$BACKUP_DIR/suid_sgid_audit.txt"
    log INFO "  Scanning for SUID/SGID binaries..."
    {
        echo "# SUID/SGID Audit — $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "# Review these binaries. Remove SUID/SGID bits from any that are unnecessary."
        echo "# Example: sudo chmod u-s /path/to/binary"
        echo ""
        echo "=== SUID binaries ==="
        find / -perm -4000 -type f 2>/dev/null || true
        echo ""
        echo "=== SGID binaries ==="
        find / -perm -2000 -type f 2>/dev/null || true
    } > "$audit_file"
    log INFO "  Audit written to: $audit_file"
    log INFO "  (Read-only scan — no changes made.)"
}
rollback_suid_audit() { return 0; }

# ===========================================================================
#
#   MAIN
#
# ===========================================================================
main() {
    # --- Parse arguments ---------------------------------------------------
    for arg in "$@"; do
        case "$arg" in
            -y|--unattended) UNATTENDED=true ;;
            --dry-run)       DRY_RUN=true ;;
            --restore)       RESTORE_MODE=true ;;
            -h|--help)       usage ;;
            *) echo "Unknown option: $arg"; usage ;;
        esac
    done

    # --- Elevate to root if needed -----------------------------------------
    if [[ $EUID -ne 0 ]]; then
        echo "Elevating to root..."
        exec sudo "$0" "$@"
    fi

    # --- Prevent concurrent runs -------------------------------------------
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "Another instance of $SCRIPT_NAME is already running. Exiting."
        exit 1
    fi

    # --- Restore mode ------------------------------------------------------
    if $RESTORE_MODE; then
        run_restore_mode
        exit 0
    fi

    # --- Create directory structure ----------------------------------------
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"

    # --- Network connectivity check ----------------------------------------
    if ! curl -fsS --max-time 5 https://packages.microsoft.com >/dev/null 2>&1 && \
       ! curl -fsS --max-time 5 https://deb.nodesource.com >/dev/null 2>&1; then
        echo ""
        echo "  ⚠  No internet connectivity detected."
        echo "     Package installs and repo additions will fail."
        echo ""
        if ! $UNATTENDED; then
            read -rp "Continue anyway? [y/N]: " ans
            case "${ans,,}" in
                y|yes) ;;
                *)     echo "Aborted."; exit 0 ;;
            esac
        fi
    fi

    # --- Banner ------------------------------------------------------------
    {
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  zorin-tune.sh v${SCRIPT_VERSION}                                      ║"
        echo "║  Performance & Security Tuning for Zorin OS 18 (VM)        ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        if $DRY_RUN; then
            echo "  *** DRY RUN MODE — no changes will be made ***"
            echo ""
        fi
        if $UNATTENDED; then
            echo "  *** UNATTENDED MODE — all items will be applied ***"
            echo ""
        fi
        echo "  Backup dir: $BACKUP_DIR"
        echo "  Log file:   $LOG_FILE"
        echo ""
    } | tee -a "$LOG_FILE"

    log INFO "Script started — $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log INFO "Mode: interactive=$( ! $UNATTENDED && echo yes || echo no) dry-run=$($DRY_RUN && echo yes || echo no)"

    # ===================================================================
    #  GROUP 1: PACKAGE MANAGEMENT (run first — everything else depends
    #  on a current system)
    # ===================================================================
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  PACKAGE MANAGEMENT & UPDATES                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"

    apply_item "K1" \
        "Full system update (apt update + full-upgrade)" \
        check_sysupdate apply_sysupdate rollback_sysupdate

    apply_item "K2" \
        "Install/verify Git" \
        check_git apply_git rollback_git

    apply_item "K3" \
        "Install/verify Python 3 + pip + venv" \
        check_python apply_python rollback_python

    apply_item "K4" \
        "Install Node.js LTS (v22.x via NodeSource)" \
        check_nodejs apply_nodejs rollback_nodejs

    apply_item "K5" \
        "Install VS Code (via Microsoft apt repo)" \
        check_vscode apply_vscode rollback_vscode

    apply_item "K6" \
        "Replace Flatpaks with apt equivalents" \
        check_flatpak_replace apply_flatpak_replace rollback_flatpak_replace

    apply_item "K7" \
        "Remove bloat apps (Brasero, LibreOffice, Remmina, etc.)" \
        check_bloat_removal apply_bloat_removal rollback_bloat_removal

    apply_item "K8" \
        "Install Sublime Text (via official apt repo)" \
        check_sublime apply_sublime rollback_sublime

    apply_item "K9" \
        "Install GitHub CLI — gh command (via official apt repo)" \
        check_gh apply_gh rollback_gh

    # ===================================================================
    #  GROUP 2: PERFORMANCE TUNING
    # ===================================================================
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  PERFORMANCE TUNING                                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"

    apply_item "P1" \
        "Reduce swappiness (60 → 10) — biggest easy win for 10 GB RAM" \
        check_swappiness apply_swappiness rollback_swappiness

    apply_item "P2" \
        "I/O scheduler → none (NVMe) — remove redundant VM queueing" \
        check_iosched apply_iosched rollback_iosched

    apply_item "P3" \
        "Disable unneeded services (bluetooth, ModemManager, avahi, cups)" \
        check_services apply_services rollback_services

    apply_item "P4" \
        "Install/verify open-vm-tools — essential VMware integration" \
        check_vmtools apply_vmtools rollback_vmtools

    apply_item "P5" \
        "Network sysctl tuning — larger TCP buffers for VS Code + SSH" \
        check_net_tuning apply_net_tuning rollback_net_tuning

    apply_item "P6" \
        "CPU governor → performance — max clock speed in VM" \
        check_cpugov apply_cpugov rollback_cpugov

    apply_item "P7" \
        "Install preload — preloads frequently-used apps into RAM" \
        check_preload apply_preload rollback_preload

    apply_item "P8" \
        "Mount /tmp as tmpfs — faster temp file I/O (1 GB RAM-backed)" \
        check_tmpfs apply_tmpfs rollback_tmpfs

    apply_item "P9" \
        "GNOME desktop optimization — disable animations, screen lock, hot corners, event sounds" \
        check_gnome_opt apply_gnome_opt rollback_gnome_opt

    apply_item "P10" \
        "Cap journald log storage at 200 MB — prevent disk bloat" \
        check_journald apply_journald rollback_journald

    apply_item "P11" \
        "Enable fstrim timer — periodic TRIM for NVMe virtual disk" \
        check_fstrim apply_fstrim rollback_fstrim

    apply_item "P12" \
        "Apt cache cleanup — free disk space from orphan packages" \
        check_apt_clean apply_apt_clean rollback_apt_clean

    apply_item "P13" \
        "Disable suspend/hibernate — VM should not sleep independently of host" \
        check_suspend_disabled apply_suspend_disabled rollback_suspend_disabled

    # ===================================================================
    #  GROUP 3: SECURITY HARDENING
    # ===================================================================
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  SECURITY HARDENING                                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"

    apply_item "S1" \
        "Enable UFW firewall — default deny incoming, allow SSH" \
        check_ufw apply_ufw rollback_ufw

    apply_item "S2" \
        "SSH server install + hardening — secure config, keep password auth" \
        check_ssh apply_ssh rollback_ssh

    apply_item "S3" \
        "Fail2ban for SSH — ban IPs after 3 failed login attempts" \
        check_fail2ban apply_fail2ban rollback_fail2ban

    apply_item "S4" \
        "Automatic security updates — unattended-upgrades" \
        check_unattended apply_unattended rollback_unattended

    apply_item "S5" \
        "Sysctl security hardening — disable redirects, enable SYN cookies" \
        check_sysctl_sec apply_sysctl_sec rollback_sysctl_sec

    apply_item "S6" \
        "AppArmor verification — ensure mandatory access control is active" \
        check_apparmor apply_apparmor rollback_apparmor

    apply_item "S7" \
        "Disable IPv6 (optional) — reduce attack surface on NAT VM" \
        check_ipv6_disabled apply_ipv6_disable rollback_ipv6_disable

    apply_item "S8" \
        "Install rkhunter — weekly rootkit scanning" \
        check_rkhunter apply_rkhunter rollback_rkhunter

    apply_item "S9" \
        "Audit SUID/SGID binaries — report for manual review (no changes)" \
        check_suid_audit apply_suid_audit rollback_suid_audit

    # ===================================================================
    #  WRAP UP
    # ===================================================================
    write_restore_script
    write_handoff
    write_log_summary

    # --- Bundle all artifacts into a single zip ----------------------------
    local zip_file="$BASE_DIR/${SCRIPT_NAME}_${TIMESTAMP}.zip"
    if command -v zip &>/dev/null || apt-get install -y -qq zip 2>/dev/null; then
        (
            cd "$REAL_HOME"
            zip -qr "$zip_file" \
                "scripts/backups/${SCRIPT_NAME}_${TIMESTAMP}/" \
                "scripts/logs/${SCRIPT_NAME}_${TIMESTAMP}.log" \
                "scripts/HANDOFF.md" \
                2>/dev/null
        )
        # Fix ownership so the non-root user can SFTP it
        chown "$REAL_USER:$REAL_USER" "$zip_file"
        log INFO "Results archived: $zip_file"
    else
        log WARN "zip not available — skipping archive creation."
    fi

    log INFO "Script finished — $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    echo "Recommended next steps:"
    echo "  1. Review the log:     less $LOG_FILE"
    echo "  2. Review the HANDOFF: less $HANDOFF_FILE"
    if [[ -f "$zip_file" ]]; then
        echo "  3. Grab the zip:       sftp> get $zip_file"
        echo "  4. Consider rebooting: sudo reboot"
    else
        echo "  3. Consider rebooting: sudo reboot"
    fi
    echo ""
    echo "VMware host-side recommendations:"
    echo "  See VMware_Fusion_Host-Side_Setup_Manual.md and HANDOFF.md for details."
    echo ""
}

main "$@"
