# zorin-os-script

Performance tuning, security hardening, and package management for a Zorin OS 18 VM on VMware Fusion. Designed for a single-user dev workstation running VS Code + Claude Pro.

## Workflow

0. Set up VMware networking first: `./vmware-fusion-setup.sh` (or see `VMware_Fusion_Host-Side_Setup_Manual.md` for manual steps).
1. Edit `zorin-tune.sh` on your Mac (this repo).
2. SFTP it to the Zorin VM: `sftp -P 2222 jeff@127.0.0.1` → `put zorin-tune.sh`.
3. Run it: `sudo ./zorin-tune.sh`
4. Pull the results zip back: `get ~/scripts/zorin-tune_*.zip`

> **Note:** Step 2 only works after SSH is installed (item S2 in zorin-tune.sh).
> On a **fresh VM** where zorin-tune.sh has never run, you must copy the script
> to the VM another way first (paste into nano, shared folder, USB, etc.).
> After the first run installs SSH, SFTP works for future updates.

## Quick Reference (Cheat Sheet)

### First-time setup (fresh OVA import)

```bash
# 1. Make the setup script executable (one time)
chmod +x vmware-fusion-setup.sh zorin-tune.sh

# 2. Run the Mac-side setup (DO NOT use sudo — it uses sudo internally)
./vmware-fusion-setup.sh              # follow the prompts

# 3. Boot the VM, log in via the VMware console (not SSH yet)

# 4. Copy zorin-tune.sh to the VM (paste into nano, shared folder, etc.)
#    Then from the VM console:
chmod +x zorin-tune.sh
sudo ./zorin-tune.sh                  # follow the prompts

# 5. After the script finishes, SSH now works from your Mac:
ssh zorin                             # uses the SSH config shortcut
sftp zorin                            # grab the results zip
```

### Day-to-day commands (from Mac)

```bash
ssh zorin                             # SSH into the VM
sftp zorin                            # SFTP into the VM
sftp -P 2222 jeff@127.0.0.1          # same thing without the shortcut

./vmware-fusion-setup.sh --status     # check host-side config state
./vmware-fusion-setup.sh --ip-only    # print the VM's current IP
```

### Starting over (new OVA import)

```bash
# 1. Clean all host-side config from previous VM
./vmware-fusion-setup.sh --clean

# 2. Delete old VM in VMware Fusion

# 3. Import fresh OVA, boot it once (VMware assigns MAC), shut down

# 4. Run setup again — auto-detects the new MAC and IP
./vmware-fusion-setup.sh

# 5. Boot VM, copy zorin-tune.sh in, run it
```

### zorin-tune.sh flags

```bash
sudo ./zorin-tune.sh                  # interactive (prompts Y/N)
sudo ./zorin-tune.sh --dry-run        # preview only, no changes
sudo ./zorin-tune.sh -y               # unattended, apply everything
sudo ./zorin-tune.sh --restore        # restore from most recent backup
```

## Files

| File | Purpose |
|------|---------|
| `zorin-tune.sh` | The script. Runs on the Zorin VM. See its header for full usage and flags. |
| `vmware-fusion-setup.sh` | Mac-side script. Automates vmxnet3, DHCP reservation, NAT port forwarding, SSH config, App Nap disable. |
| `VMware_Fusion_Host-Side_Setup_Manual.md` | Manual version of what `vmware-fusion-setup.sh` does, plus troubleshooting. |
| `reference/jeff-zorin-os.vmx` | VM configuration for reference (5 vCPUs, 10 GB RAM, NVMe, EFI). |
| `reference/request_for_performance_and_security_script_v2.txt` | Requirements doc that produced this script. |
| `zz_old_stuff/` | Previous versions and first-run results. Kept for reference, not active. |

## What the Script Does

Runs 31 items across three groups, prompting Y/N for each:

- **Package Management** (K1–K9) — system update, Git, Python 3, Node.js LTS, VS Code, Sublime Text, GitHub CLI, Flatpak→apt replacement, bloat removal.
- **Performance** (P1–P13) — swappiness, I/O scheduler, services, open-vm-tools, network tuning, CPU governor, preload, tmpfs, GNOME optimization (animations, screen lock, hot corners), journald limits, fstrim, apt cleanup, disable suspend/hibernate.
- **Security** (S1–S9) — UFW firewall, SSH hardening, fail2ban, unattended upgrades, sysctl hardening, AppArmor, IPv6 disable, rkhunter, SUID/SGID audit.

Every change is backed up before modification. A restore script and HANDOFF.md are auto-generated. All artifacts are bundled into a single zip for easy retrieval.

## On the Zorin Side

After running, the script creates:

```
~/scripts/
├── backups/zorin-tune_<timestamp>/   ← config backups + restore script
├── logs/zorin-tune_<timestamp>.log   ← full run log
├── HANDOFF.md                        ← status for future AI sessions
└── zorin-tune_<timestamp>.zip        ← archive of everything above
```

## Troubleshooting

### "Permission denied" running a script

You need to make it executable first:
```bash
chmod +x vmware-fusion-setup.sh
./vmware-fusion-setup.sh
```

### "Connection refused" when trying to SSH/SFTP

SSH server isn't running on the VM yet. `zorin-tune.sh` installs it (item S2)
and opens the firewall (item S1). On a fresh VM, you must run zorin-tune.sh
from the VM console first — SSH/SFTP only works after that first run.

### "Connection timed out" or wrong IP

The VM's MAC address and IP change with every new OVA import. Run:
```bash
./vmware-fusion-setup.sh --status
```
If the DHCP reservation shows "NOT configured" or the IP doesn't match,
clean and re-run:
```bash
./vmware-fusion-setup.sh --clean
./vmware-fusion-setup.sh
```

### "REMOTE HOST IDENTIFICATION HAS CHANGED" warning

The new VM has different SSH host keys. The `--clean` flag removes old
`known_hosts` entries automatically. If you already ran setup without
cleaning first:
```bash
ssh-keygen -R '[127.0.0.1]:2222'
```

### vmware-fusion-setup.sh exits silently after VM selection

This was a bug in early versions (fixed in current). Make sure you're running
the latest version from this repo.

### Can't resolve "zorin" (ssh zorin fails)

The SSH config shortcut (`~/.ssh/config`) is created by `vmware-fusion-setup.sh`
during the SSH config step. If you skipped it or haven't run setup yet, use
the explicit command:
```bash
ssh -p 2222 jeff@127.0.0.1
```

### Locked out by fail2ban

3 wrong passwords within 10 minutes triggers a 30-minute ban. Since all Mac
SSH traffic arrives from the NAT gateway (`172.16.221.2`), a lockout blocks
all SSH from the Mac. Unban from the **VM console** (not SSH):
```bash
sudo fail2ban-client set sshd unbanip 172.16.221.2
sudo fail2ban-client set sshd unbanip 172.16.221.1
```
Or just wait 30 minutes.

### Should I use sudo with vmware-fusion-setup.sh?

**No.** Run it without sudo: `./vmware-fusion-setup.sh`. The script uses
per-command `sudo` internally for the system files that need it.

`zorin-tune.sh` is the opposite — run it with `sudo` (or it auto-elevates).
