# VMware Fusion Host-Side Setup Manual — Static IP, vmxnet3, SSH/NAT Port Forwarding

Guide for configuring VMware Fusion on the Mac host to give the Zorin OS 18 VM
a static IP address, upgrade the network adapter, and enable SSH access from the
Mac via NAT port forwarding.

> **One-time setup.** These steps only need to be done once per VM instance.
> If you create or import a new Zorin OS VM, it will have a different MAC
> address and IP — repeat this guide with the new values.

> **Prefer the script.** `vmware-fusion-setup.sh` automates all of these steps
> and auto-detects the VM's MAC and IP. This manual is a reference for
> understanding what the script does, and for troubleshooting.

**VM:** jeff-zorin-os (Zorin OS 18 Core)
**Host:** macOS, VMware Fusion 25H2u1
**Date verified:** 2026-03-08

---

## Current Network Configuration

These values are **fixed by VMware Fusion** (they don't change between VMs):

| Item                  | Value                              |
|-----------------------|------------------------------------|
| VMware network        | vmnet8 (NAT)                       |
| Subnet                | 172.16.221.0/24                    |
| Gateway / DNS         | 172.16.221.2                       |
| Host IP on vmnet8     | 172.16.221.1                       |
| DHCP range            | 172.16.221.128 – 172.16.221.254    |

These values **change with each new VM** (check with `./vmware-fusion-setup.sh --status`):

| Item                  | Value                              |
|-----------------------|------------------------------------|
| VM MAC address        | *(auto-detected from .vmx)*        |
| VM current IP (DHCP)  | *(auto-detected from running VM)*  |
| VM network adapter    | vmxnet3 (after setup)              |
| VM network interface  | ens192                             |

## Prerequisites

- The VM has `open-vm-tools` installed (required for vmxnet3 driver support).
- **`zorin-tune.sh` must be run for real (not `--dry-run`) before SSH will
  work.** The script installs and configures OpenSSH server (item S2) and
  opens port 22 in UFW (item S1). Without a real run, sshd will have missing
  host keys and connections will fail with "Connection closed."

---

## Step 1: Power Off the VM

Shut down the VM cleanly from inside:

```bash
sudo shutdown -h now
```

Or use VMware Fusion menu: **Virtual Machine → Shut Down**.

Wait until VMware shows the VM as fully powered off (not suspended).

---

## Step 2: Upgrade Network Adapter to vmxnet3

If the `.vmx` file still uses `e1000` (emulated Intel adapter), upgrade it to
`vmxnet3` — VMware's paravirtualized adapter with significantly better
performance and lower CPU overhead. If it already says `vmxnet3`, skip this step.

**Edit the actual VM's .vmx file** (not the reference copy in this project):

```
~/Virtual Machines/jeff-zorin-os.vmwarevm/jeff-zorin-os.vmx
```

> **Note:** This project directory contains a reference copy at
> `reference/jeff-zorin-os.vmx` — that's for documentation only.
> Always edit the file inside the `.vmwarevm` bundle above.

Find this line:

```
ethernet0.virtualDev = "e1000"
```

Change it to:

```
ethernet0.virtualDev = "vmxnet3"
```

**Important:** The VM must be fully powered off (not suspended) when you edit
the .vmx file. VMware will reject changes to a running or suspended VM.

---

## Step 3: Add DHCP Reservation (Static IP via MAC Binding)

This tells VMware's DHCP server to always assign a specific IP to the VM's
MAC address, effectively giving it a static IP without configuring the guest OS.

> **Find your VM's MAC and IP first.** Run `./vmware-fusion-setup.sh --status`
> or check the .vmx file for `ethernet0.address` / `ethernet0.generatedAddress`.
> The IP is whatever the VM currently has (run `ip -4 addr show` inside the VM).

**Edit the DHCP config file** (requires sudo):

```bash
sudo nano /Library/Preferences/VMware\ Fusion/vmnet8/dhcpd.conf
```

**Add the following block at the very end of the file** (after the
`"End of DO NOT MODIFY SECTION"` comment), replacing `<MAC>` and `<IP>`
with your VM's actual values:

```
# Static IP reservation for Zorin OS 18 VM
host jeff-zorin-os {
    hardware ethernet <MAC>;
    fixed-address <IP>;
}
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).

### Why use the VM's current IP?

- It's within the DHCP range (`.128`–`.254`), which is required for VMware
  Fusion's DHCP server to serve it.
- Using the IP the VM already has means no disruption.
- The DHCP reservation guarantees this MAC always gets this IP, even after
  reboots or lease expiry.

---

## Step 4: Add SSH Port Forwarding (NAT)

This maps port `2222` on the Mac's localhost to port `22` (SSH) inside the VM,
allowing you to SSH from the Mac into the VM.

**Edit the NAT config file** (requires sudo):

```bash
sudo nano /Library/Preferences/VMware\ Fusion/vmnet8/nat.conf
```

**Find the `[incomingtcp]` section.** It currently looks like this:

```ini
[incomingtcp]

# Use these with care - anyone can enter into your VM through these...
# The format and example are as follows:
#<external port number> = <VM's IP address>:<VM's port number>
#8080 = 172.16.3.128:80
```

**Add this line** below the comments (replacing `<IP>` with your VM's IP):

```
2222 = <IP>:22
```

So the section becomes:

```ini
[incomingtcp]

# Use these with care - anyone can enter into your VM through these...
# The format and example are as follows:
#<external port number> = <VM's IP address>:<VM's port number>
#8080 = 172.16.3.128:80
2222 = <IP>:22
```

Save and exit.

### Why port 2222?

- Port 22 on the Mac may already be in use by the Mac's own SSH server.
- Using 2222 avoids conflicts and makes it clear you're connecting to the VM.

---

## Step 5: Restart VMware Networking

The DHCP and NAT config changes don't take effect until VMware's networking
services are restarted.

```bash
sudo /Applications/VMware\ Fusion.app/Contents/Library/vmnet-cli --stop
sudo /Applications/VMware\ Fusion.app/Contents/Library/vmnet-cli --start
```

You should see output indicating the services stopped and started successfully.

---

## Step 6: Boot the VM

Start the VM from VMware Fusion. After boot, verify the network came up
correctly — log in to the VM console and run:

```bash
ip -4 addr show ens192
```

You should see `inet <IP>/24`. The vmxnet3 adapter uses interface
name `ens192` (previously `ens33` with e1000). It also has an altname `enp11s0`.

---

## Step 7: Test SSH from the Mac

From a terminal on your Mac:

```bash
ssh -p 2222 jeff@127.0.0.1
```

You should get a password prompt for the `jeff` account on the VM.

### Test SFTP too:

```bash
sftp -P 2222 jeff@127.0.0.1
```

(Note: SFTP uses uppercase `-P` for port.)

---

## Step 8 (Optional): Add SSH Config Shortcut

To avoid typing the port every time, add this to `~/.ssh/config` on your Mac:

```
Host zorin
    HostName 127.0.0.1
    Port 2222
    User jeff
```

Then you can simply run:

```bash
ssh zorin
sftp zorin
```

---

## Troubleshooting

### VM doesn't get the expected IP

1. Check that the MAC in `dhcpd.conf` matches the VM's actual MAC
   (run `./vmware-fusion-setup.sh --status` to see it)
2. Confirm VMware networking was restarted (Step 5)
3. Inside the VM, release and renew: `sudo dhclient -r ens192 && sudo dhclient ens192`

### SSH connection refused

1. Verify SSH is running in the VM: `sudo systemctl status ssh`
2. Verify UFW allows SSH: `sudo ufw status` (should show `22/tcp ALLOW`)
3. Verify nat.conf has the `2222 = <IP>:22` line (with your VM's IP)
4. Verify VMware networking was restarted after editing nat.conf

### Network doesn't come up after vmxnet3 switch

1. Log in to the VM console (not SSH — network is down)
2. Run `ip link show` — the vmxnet3 interface is `ens192` (altname `enp11s0`)
3. If NetworkManager didn't auto-connect, try:
   `sudo nmcli device connect ens192`
4. If all else fails, revert the .vmx change back to `e1000` and reboot

### "Connection timed out" from Mac

1. Check if the VM is actually reachable: `ping <VM_IP>` (from Mac)
2. If ping fails, the DHCP reservation or VMware networking restart may not
   have worked — re-check Steps 3 and 5

### Locked out by fail2ban

If you get 3 wrong passwords within 10 minutes, fail2ban blocks the IP for
30 minutes. Since all Mac SSH traffic arrives from the NAT gateway
(`172.16.221.2`) or the vmnet8 host IP (`172.16.221.1`), a lockout blocks
all SSH from the Mac.

**To unban from the VM console** (not SSH — you're locked out):

```bash
sudo fail2ban-client status sshd          # shows banned IPs
sudo fail2ban-client set sshd unbanip 172.16.221.2
sudo fail2ban-client set sshd unbanip 172.16.221.1
```

The ban also lifts automatically after 30 minutes.

---

## How to Undo Everything

If you need to revert all changes:

1. **vmxnet3 → e1000:** Power off the VM, change `ethernet0.virtualDev` back
   to `"e1000"` in the .vmx file.
2. **Remove DHCP reservation:** Edit `dhcpd.conf`, delete the
   `host jeff-zorin-os { ... }` block.
3. **Remove port forwarding:** Edit `nat.conf`, delete the
   `2222 = <IP>:22` line.
4. **Restart VMware networking** (Step 5 commands).
5. **Boot the VM** — it will get a dynamic IP via DHCP again.

---

## File Locations Reference

| File | Path |
|------|------|
| VM config (.vmx) | `~/Virtual Machines/jeff-zorin-os.vmwarevm/jeff-zorin-os.vmx` |
| DHCP config | `/Library/Preferences/VMware Fusion/vmnet8/dhcpd.conf` |
| NAT config | `/Library/Preferences/VMware Fusion/vmnet8/nat.conf` |
| Mac SSH config | `~/.ssh/config` |
