#!/usr/bin/env zsh
#
# ============================================================================
#  vmware-fusion-setup.sh — VMware Fusion Host-Side Setup for Zorin OS VM (macOS)
# ============================================================================
#
#  QUICK START
#  -----------
#    chmod +x vmware-fusion-setup.sh
#    ./vmware-fusion-setup.sh                  # Interactive guided setup
#    ./vmware-fusion-setup.sh --ip-only        # Just show the VM's current IP
#    ./vmware-fusion-setup.sh --status         # Show current config state
#    ./vmware-fusion-setup.sh --clean          # Remove all changes from previous run
#
#  DESCRIPTION
#  -----------
#    Automates the one-time VMware Fusion host-side setup for a Zorin OS VM:
#
#    1. Discover the VM's MAC address and current IP.
#    2. Upgrade the network adapter from e1000 to vmxnet3 (VM must be off).
#    3. Add a DHCP reservation (static IP via MAC binding).
#    4. Add SSH/SFTP port forwarding (localhost:2222 → VM:22).
#    5. Restart VMware networking.
#    6. Optionally add an SSH config shortcut.
#
#    Prompts Y/N for each step. Backs up every file it modifies.
#    See VMware_Fusion_Host-Side_Setup_Manual.md for the manual version of these steps.
#
#  USAGE
#  -----
#    ./vmware-fusion-setup.sh [OPTIONS] [VMX_PATH]
#
#    Arguments:
#      VMX_PATH             Path to .vmx file. If omitted, auto-detected.
#
#    Options:
#      --ip-only            Print the VM's current IP and exit.
#      --status             Show current config state and exit.
#      --clean              Remove DHCP reservation, port forwarding, and SSH
#                           config entries added by a previous run, then restart
#                           VMware networking. Does NOT revert vmxnet3.
#      --host-port PORT     SSH port on Mac side (default: 2222).
#      --guest-port PORT    SSH port on guest side (default: 22).
#      -h, --help           Show this help message and exit.
#
#  REQUIREMENTS
#  ------------
#    - macOS with VMware Fusion installed
#    - VM must be running for IP discovery (--ip-only, --status)
#    - VM must be powered off for vmxnet3 upgrade
#
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="vmware-fusion-setup"
readonly FUSION_APP="/Applications/VMware Fusion.app"
readonly VMRUN="$FUSION_APP/Contents/Library/vmrun"
readonly VMNET_CLI="$FUSION_APP/Contents/Library/vmnet-cli"
readonly VMWARE_PREFS="/Library/Preferences/VMware Fusion"
readonly DHCPD_CONF="$VMWARE_PREFS/vmnet8/dhcpd.conf"
readonly NAT_CONF="$VMWARE_PREFS/vmnet8/nat.conf"
readonly SSH_CONFIG="$HOME/.ssh/config"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
readonly TIMESTAMP

# Defaults
HOST_PORT=2222
GUEST_PORT=22
IP_ONLY=false
STATUS_ONLY=false
CLEAN_MODE=false
VMX_PATH=""

readonly TAG="# vmware-fusion-setup"
readonly TAG_START="# vmware-fusion-setup:start"
readonly TAG_END="# vmware-fusion-setup:end"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "\033[0;32m[✓]\033[0m $*"; }
warn()  { echo "\033[0;33m[!]\033[0m $*"; }
error() { echo "\033[0;31m[✗]\033[0m $*"; }

prompt_yn() {
    local question="$1"
    while true; do
        read -r "ans?$question [Y/n]: "
        case "${ans:l}" in
            y|yes|"") return 0 ;;
            n|no)     return 1 ;;
            *)        echo "Please answer y or n." ;;
        esac
    done
}

backup_file() {
    local src="$1"
    if [[ -f "$src" ]]; then
        local bak="${src}.bak_${TIMESTAMP}"
        sudo cp -a "$src" "$bak"
        info "Backed up: $src → $bak"
    fi
}

# ---------------------------------------------------------------------------
# VMware Fusion checks
# ---------------------------------------------------------------------------
check_fusion() {
    if [[ ! -d "$FUSION_APP" ]]; then
        error "VMware Fusion not found at: $FUSION_APP"
        exit 1
    fi
    if [[ ! -x "$VMRUN" ]]; then
        error "vmrun not found at: $VMRUN"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Find VMX file
# ---------------------------------------------------------------------------
find_vmx() {
    if [[ -n "$VMX_PATH" ]]; then
        if [[ ! -f "$VMX_PATH" ]]; then
            error "VMX file not found: $VMX_PATH"
            exit 1
        fi
        return
    fi

    # Auto-detect: look in common locations
    local -a candidates=()
    local vm_dir="$HOME/Virtual Machines.localized"
    [[ -d "$HOME/Virtual Machines" ]] && vm_dir="$HOME/Virtual Machines"

    if [[ -d "$vm_dir" ]]; then
        while IFS= read -r f; do
            candidates+=("$f")
        done < <(find "$vm_dir" -name "*.vmx" -type f 2>/dev/null)
    fi

    if [[ ${#candidates[@]} -eq 0 ]]; then
        error "No .vmx files found in $vm_dir"
        echo "  Specify the path manually: $SCRIPT_NAME /path/to/vm.vmx"
        exit 1
    elif [[ ${#candidates[@]} -eq 1 ]]; then
        VMX_PATH="${candidates[1]}"
        info "Found VM: $VMX_PATH"
    else
        echo ""
        echo "Multiple VMs found:"
        local i=1
        for f in "${candidates[@]}"; do
            echo "  $i) $f"
            ((i++))
        done
        echo ""
        read -r "choice?Select VM [1-${#candidates[@]}]: "
        if [[ "$choice" -ge 1 && "$choice" -le ${#candidates[@]} ]]; then
            VMX_PATH="${candidates[$choice]}"
        else
            error "Invalid selection."
            exit 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# Read values from VMX
# ---------------------------------------------------------------------------
get_vmx_value() {
    local key="$1"
    grep -i "^${key} " "$VMX_PATH" 2>/dev/null | head -1 | sed 's/.*= *"//' | sed 's/".*//' || true
}

get_vm_mac() {
    # Try static address first, then generated
    local mac
    mac="$(get_vmx_value 'ethernet0.address')"
    if [[ -z "$mac" ]]; then
        mac="$(get_vmx_value 'ethernet0.generatedAddress')"
    fi
    echo "$mac"
}

get_vm_display_name() {
    get_vmx_value 'displayName'
}

get_vm_nic_type() {
    get_vmx_value 'ethernet0.virtualDev'
}

# ---------------------------------------------------------------------------
# VM state and IP discovery
# ---------------------------------------------------------------------------
is_vm_running() {
    "$VMRUN" list 2>/dev/null | grep -qF "$VMX_PATH" 2>/dev/null || return 1
}

get_vm_ip() {
    if ! is_vm_running; then
        return 1
    fi
    "$VMRUN" getGuestIPAddress "$VMX_PATH" -wait 2>/dev/null
}

# ---------------------------------------------------------------------------
# Read current NAT subnet info
# ---------------------------------------------------------------------------
get_nat_subnet() {
    if [[ -f "$NAT_CONF" ]]; then
        grep '^ip ' "$NAT_CONF" 2>/dev/null | head -1 | awk '{print $3}'
    fi
}

get_nat_netmask() {
    if [[ -f "$NAT_CONF" ]]; then
        grep '^netmask ' "$NAT_CONF" 2>/dev/null | head -1 | awk '{print $3}'
    fi
}

# ---------------------------------------------------------------------------
# Status report
# ---------------------------------------------------------------------------
show_status() {
    local vm_name mac nic_type running ip

    vm_name="$(get_vm_display_name)"
    mac="$(get_vm_mac)"
    nic_type="$(get_vm_nic_type)"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  VMware Host-Side Configuration Status                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  VM:           $vm_name"
    echo "  VMX:          $VMX_PATH"
    echo "  MAC:          ${mac:-unknown}"
    echo "  NIC type:     ${nic_type:-unknown}"

    if is_vm_running; then
        ip="$(get_vm_ip || echo 'unavailable')"
        echo "  Status:       RUNNING"
        echo "  IP:           $ip"
    else
        echo "  Status:       POWERED OFF"
        echo "  IP:           (VM must be running)"
    fi

    # DHCP reservation
    if sudo grep -q "$TAG" "$DHCPD_CONF" 2>/dev/null; then
        local reserved_ip
        reserved_ip="$(sudo grep "fixed-address.*$TAG" "$DHCPD_CONF" 2>/dev/null \
            | awk '{print $2}' | tr -d ';')"
        echo "  DHCP reservation: $reserved_ip (configured)"
    else
        echo "  DHCP reservation: NOT configured"
    fi

    # Port forwarding
    if sudo grep -qE "^${HOST_PORT}\s*=" "$NAT_CONF" 2>/dev/null; then
        local fwd_line
        fwd_line="$(sudo grep -E "^${HOST_PORT}\s*=" "$NAT_CONF" 2>/dev/null | head -1)"
        echo "  Port forward: $fwd_line"
    else
        echo "  Port forward: NOT configured"
    fi

    # SSH config
    if [[ -f "$SSH_CONFIG" ]] && grep -q "$TAG_START" "$SSH_CONFIG" 2>/dev/null; then
        echo "  SSH shortcut: configured in ~/.ssh/config"
    else
        echo "  SSH shortcut: NOT configured"
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Step 1: Upgrade to vmxnet3
# ---------------------------------------------------------------------------
do_vmxnet3_upgrade() {
    local nic_type
    nic_type="$(get_vm_nic_type)"

    if [[ "${nic_type:l}" == "vmxnet3" ]]; then
        info "Network adapter is already vmxnet3 — skipping."
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Upgrade network adapter: ${nic_type:-e1000} → vmxnet3"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  vmxnet3 is VMware's paravirtualized adapter — better performance"
    echo "  and lower CPU overhead than e1000."
    echo ""
    warn "The VM must be powered off for this change."

    if is_vm_running; then
        error "VM is currently running. Shut it down first, then re-run this script."
        return 1
    fi

    if ! prompt_yn "  Upgrade to vmxnet3?"; then
        warn "Skipped vmxnet3 upgrade."
        return 0
    fi

    # Back up VMX
    cp -a "$VMX_PATH" "${VMX_PATH}.bak_${TIMESTAMP}"
    info "Backed up VMX file."

    # Replace the adapter type
    if grep -q 'ethernet0.virtualDev' "$VMX_PATH"; then
        sed -i '' 's/ethernet0.virtualDev = ".*"/ethernet0.virtualDev = "vmxnet3"/' "$VMX_PATH"
    else
        echo 'ethernet0.virtualDev = "vmxnet3"' >> "$VMX_PATH"
    fi

    info "Network adapter changed to vmxnet3."
    echo "  Note: After boot, the interface name will be ens192 (altname enp11s0)."
}

# ---------------------------------------------------------------------------
# Step 2: DHCP reservation
# ---------------------------------------------------------------------------
do_dhcp_reservation() {
    local mac vm_name ip

    mac="$(get_vm_mac)"
    vm_name="$(get_vm_display_name)"

    if [[ -z "$mac" ]]; then
        error "Could not determine VM MAC address from VMX file."
        return 1
    fi

    # Check if already configured
    if sudo grep -q "$TAG" "$DHCPD_CONF" 2>/dev/null; then
        info "DHCP reservation already exists (tagged) — skipping."
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Add DHCP reservation (static IP)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Try to get current IP
    if is_vm_running; then
        ip="$(get_vm_ip || echo '')"
    fi

    if [[ -z "$ip" ]]; then
        echo ""
        echo "  Could not auto-detect the VM's IP."
        echo "  (VM must be running with open-vm-tools for auto-detection.)"
        echo ""
        read -r "ip?  Enter the VM's current IP address: "
        if [[ -z "$ip" ]]; then
            error "No IP provided. Skipping DHCP reservation."
            return 1
        fi
    else
        info "Detected VM IP: $ip"
    fi

    echo ""
    echo "  VM:     $vm_name"
    echo "  MAC:    $mac"
    echo "  IP:     $ip"
    echo ""
    echo "  This will add a DHCP reservation so the VM always gets $ip."

    if ! prompt_yn "  Add DHCP reservation?"; then
        warn "Skipped DHCP reservation."
        return 0
    fi

    backup_file "$DHCPD_CONF"

    # Sanitize vm_name for use as DHCP host identifier (alphanumeric + hyphens)
    local host_id="${vm_name//[^a-zA-Z0-9-]/-}"

    # Append reservation (every line tagged for --clean removal)
    printf '\n%s\n%s\n%s\n%s\n%s\n' \
        "# Static IP reservation for ${vm_name} ${TAG}" \
        "host ${host_id} { ${TAG}" \
        "    hardware ethernet ${mac:l}; ${TAG}" \
        "    fixed-address ${ip}; ${TAG}" \
        "} ${TAG}" \
        | sudo tee -a "$DHCPD_CONF" > /dev/null

    info "DHCP reservation added: $mac → $ip"
}

# ---------------------------------------------------------------------------
# Step 3: NAT port forwarding
# ---------------------------------------------------------------------------
do_port_forwarding() {
    local ip mac

    mac="$(get_vm_mac)"

    # Get the IP from DHCP reservation (just set), or auto-detect
    ip="$(sudo awk "/hardware ethernet ${mac:l}/,/}/" "$DHCPD_CONF" 2>/dev/null \
        | grep 'fixed-address' | awk '{print $2}' | tr -d ';')"

    if [[ -z "$ip" ]] && is_vm_running; then
        ip="$(get_vm_ip || echo '')"
    fi

    if [[ -z "$ip" ]]; then
        error "Could not determine VM IP for port forwarding."
        echo "  Run the DHCP reservation step first, or provide the IP manually."
        return 1
    fi

    # Check if already configured
    if sudo grep -qE "^${HOST_PORT}\s*=" "$NAT_CONF" 2>/dev/null; then
        local existing
        existing="$(sudo grep -E "^${HOST_PORT}\s*=" "$NAT_CONF" | head -1)"
        info "Port forwarding already configured: $existing — skipping."
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Add SSH port forwarding (NAT)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Mac localhost:${HOST_PORT}  →  VM ${ip}:${GUEST_PORT}"
    echo ""
    echo "  This lets you SSH/SFTP to the VM via:"
    echo "    ssh -p ${HOST_PORT} jeff@127.0.0.1"
    echo "    sftp -P ${HOST_PORT} jeff@127.0.0.1"

    if ! prompt_yn "  Add port forwarding?"; then
        warn "Skipped port forwarding."
        return 0
    fi

    backup_file "$NAT_CONF"

    # Insert the forwarding rule under [incomingtcp] with block markers
    local rule="${HOST_PORT} = ${ip}:${GUEST_PORT}"
    if sudo grep -q '^\[incomingtcp\]' "$NAT_CONF" 2>/dev/null; then
        # Add after the [incomingtcp] section header
        sudo sed -i '' "/^\[incomingtcp\]/a\\
${TAG_START}\\
${rule}\\
${TAG_END}
" "$NAT_CONF"
    else
        # No [incomingtcp] section found — append one
        printf '\n[incomingtcp]\n%s\n%s\n%s\n' "$TAG_START" "$rule" "$TAG_END" \
            | sudo tee -a "$NAT_CONF" > /dev/null
    fi

    info "Port forwarding added: localhost:${HOST_PORT} → ${ip}:${GUEST_PORT}"
}

# ---------------------------------------------------------------------------
# Step 4: Restart VMware networking
# ---------------------------------------------------------------------------
do_restart_networking() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Restart VMware networking"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warn "This briefly drops network for ALL running VMs."

    if ! prompt_yn "  Restart VMware networking now?"; then
        warn "Skipped networking restart."
        echo "  Run manually later:"
        echo "    sudo '$VMNET_CLI' --stop && sudo '$VMNET_CLI' --start"
        return 0
    fi

    info "Stopping VMware networking..."
    sudo "$VMNET_CLI" --stop 2>/dev/null || true
    info "Starting VMware networking..."
    sudo "$VMNET_CLI" --start 2>/dev/null || true
    info "VMware networking restarted."
}

# ---------------------------------------------------------------------------
# Step 5: SSH config shortcut
# ---------------------------------------------------------------------------
do_ssh_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Add SSH config shortcut"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Adds a 'zorin' shortcut to ~/.ssh/config so you can just run:"
    echo "    ssh zorin"
    echo "    sftp zorin"

    # Check if already configured
    if [[ -f "$SSH_CONFIG" ]] && grep -q "$TAG_START" "$SSH_CONFIG" 2>/dev/null; then
        info "SSH config shortcut 'zorin' already exists — skipping."
        return 0
    fi

    if ! prompt_yn "  Add SSH config shortcut?"; then
        warn "Skipped SSH config shortcut."
        return 0
    fi

    mkdir -p "$HOME/.ssh"
    if [[ -f "$SSH_CONFIG" ]]; then
        cp -a "$SSH_CONFIG" "${SSH_CONFIG}.bak_${TIMESTAMP}"
    fi

    cat >> "$SSH_CONFIG" <<SSH_BLOCK

${TAG_START}
Host zorin
    HostName 127.0.0.1
    Port ${HOST_PORT}
    User jeff
${TAG_END}
SSH_BLOCK

    chmod 600 "$SSH_CONFIG"
    info "SSH shortcut added. Use: ssh zorin"
}

# ---------------------------------------------------------------------------
# Step 6: Disable macOS App Nap for VMware Fusion
# ---------------------------------------------------------------------------
do_app_nap() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Disable macOS App Nap for VMware Fusion"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  App Nap causes macOS to throttle VMware Fusion when it is in"
    echo "  the background, leading to VM freezes and poor performance."
    echo ""

    local current
    current="$(defaults read com.vmware.fusion NSAppSleepDisabled 2>/dev/null || echo '0')"
    if [[ "$current" == "1" ]]; then
        info "App Nap already disabled for VMware Fusion — skipping."
        return 0
    fi

    if ! prompt_yn "  Disable App Nap for VMware Fusion?"; then
        warn "Skipped App Nap disable."
        echo "  To disable manually: defaults write com.vmware.fusion NSAppSleepDisabled -bool YES"
        return 0
    fi

    defaults write com.vmware.fusion NSAppSleepDisabled -bool YES
    info "App Nap disabled. VMware Fusion will not be throttled in the background."
    echo "  To re-enable: defaults delete com.vmware.fusion NSAppSleepDisabled"
}

# ---------------------------------------------------------------------------
# Clean mode — remove all tagged entries from previous run
# ---------------------------------------------------------------------------
do_clean() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Clean: Remove vmware-fusion-setup entries                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    local changed=false

    # Clean dhcpd.conf
    if sudo grep -q "$TAG" "$DHCPD_CONF" 2>/dev/null; then
        backup_file "$DHCPD_CONF"
        sudo sed -i '' "/${TAG//\//\\/}/d" "$DHCPD_CONF"
        # Remove any blank lines left at end of file
        sudo sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$DHCPD_CONF" 2>/dev/null || true
        info "Removed DHCP reservation from dhcpd.conf"
        changed=true
    else
        info "No tagged entries in dhcpd.conf — nothing to remove."
    fi

    # Clean nat.conf
    if sudo grep -q "$TAG_START" "$NAT_CONF" 2>/dev/null; then
        backup_file "$NAT_CONF"
        sudo sed -i '' "/${TAG_START}/,/${TAG_END}/d" "$NAT_CONF"
        info "Removed port forwarding from nat.conf"
        changed=true
    else
        info "No tagged entries in nat.conf — nothing to remove."
    fi

    # Clean SSH config
    if [[ -f "$SSH_CONFIG" ]] && grep -q "$TAG_START" "$SSH_CONFIG" 2>/dev/null; then
        cp -a "$SSH_CONFIG" "${SSH_CONFIG}.bak_${TIMESTAMP}"
        sed -i '' "/${TAG_START}/,/${TAG_END}/d" "$SSH_CONFIG"
        # Remove trailing blank lines
        sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$SSH_CONFIG" 2>/dev/null || true
        info "Removed SSH config shortcut from ~/.ssh/config"
        changed=true
    else
        info "No tagged entries in ~/.ssh/config — nothing to remove."
    fi

    # Clean known_hosts entries for the forwarded port
    local real_home="${HOME}"
    local kh="${real_home}/.ssh/known_hosts"
    if [[ -f "$kh" ]] && grep -q "\[127.0.0.1\]:${HOST_PORT}" "$kh" 2>/dev/null; then
        ssh-keygen -R "[127.0.0.1]:${HOST_PORT}" 2>/dev/null || true
        rm -f "${kh}.old"
        info "Removed [127.0.0.1]:${HOST_PORT} from known_hosts"
        changed=true
    else
        info "No known_hosts entries for [127.0.0.1]:${HOST_PORT} — nothing to remove."
    fi

    # Restart networking if we changed anything
    if $changed; then
        echo ""
        if prompt_yn "  Restart VMware networking to apply changes?"; then
            info "Stopping VMware networking..."
            sudo "$VMNET_CLI" --stop 2>/dev/null || true
            info "Starting VMware networking..."
            sudo "$VMNET_CLI" --start 2>/dev/null || true
            info "VMware networking restarted."
        else
            warn "Skipped networking restart. Run manually:"
            echo "    sudo '$VMNET_CLI' --stop && sudo '$VMNET_CLI' --start"
        fi
    fi

    echo ""
    info "Clean complete. Note: vmxnet3 adapter change is NOT reverted."
    echo "  To revert vmxnet3, see VMware_Fusion_Host-Side_Setup_Manual.md."
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Parse arguments
    local -a positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ip-only)       IP_ONLY=true; shift ;;
            --status)        STATUS_ONLY=true; shift ;;
            --clean)         CLEAN_MODE=true; shift ;;
            --host-port)     HOST_PORT="$2"; shift 2 ;;
            --guest-port)    GUEST_PORT="$2"; shift 2 ;;
            -h|--help)       sed -n '/^#  QUICK START/,/^# ====/p' "$0" | sed 's/^#//' | sed 's/^ //'; exit 0 ;;
            -*)              echo "Unknown option: $1"; exit 1 ;;
            *)               positional+=("$1"); shift ;;
        esac
    done

    # Positional arg = VMX path
    if [[ ${#positional[@]} -gt 0 ]]; then
        VMX_PATH="${positional[1]}"
    fi

    check_fusion
    find_vmx

    # --- IP only mode ---
    if $IP_ONLY; then
        if ! is_vm_running; then
            error "VM is not running. Start it first."
            exit 1
        fi
        local ip
        ip="$(get_vm_ip)"
        if [[ -n "$ip" ]]; then
            echo "$ip"
        else
            error "Could not determine VM IP."
            exit 1
        fi
        exit 0
    fi

    # --- Status mode ---
    if $STATUS_ONLY; then
        show_status
        exit 0
    fi

    # --- Clean mode ---
    if $CLEAN_MODE; then
        do_clean
        exit 0
    fi

    # --- Full interactive setup ---
    local vm_name
    vm_name="$(get_vm_display_name)"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  VMware Fusion Host-Side Setup                             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  VM:   $vm_name"
    echo "  VMX:  $VMX_PATH"
    echo "  MAC:  $(get_vm_mac)"
    echo "  NIC:  $(get_vm_nic_type)"
    if is_vm_running; then
        echo "  IP:   $(get_vm_ip || echo 'detecting...')"
    else
        echo "  IP:   (VM is powered off)"
    fi
    echo ""

    # Step 1: vmxnet3
    do_vmxnet3_upgrade

    # Step 2: DHCP reservation
    do_dhcp_reservation

    # Step 3: Port forwarding
    do_port_forwarding

    # Step 4: Restart networking
    do_restart_networking

    # Step 5: SSH config
    do_ssh_config

    # Step 6: App Nap
    do_app_nap

    # Done
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Setup Complete                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Next steps:"
    echo "    1. Boot the VM (if powered off for vmxnet3 change)."
    echo "    2. Run zorin-tune.sh inside the VM (installs SSH server)."
    echo "    3. Test SSH: ssh -p ${HOST_PORT} jeff@127.0.0.1"
    if [[ -f "$SSH_CONFIG" ]] && grep -q 'Host zorin' "$SSH_CONFIG" 2>/dev/null; then
        echo "       Or just: ssh zorin"
    fi
    echo ""
    echo "  See VMware_Fusion_Host-Side_Setup_Manual.md for troubleshooting."
    echo ""
}

main "$@"
