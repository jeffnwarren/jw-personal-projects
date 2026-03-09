# Create the markdown file content
readme_content = """# VMware Fusion: Zorin OS 18 Core Power Optimization Guide

This guide covers how to prevent Zorin OS from freezing/locking and how to optimize performance on a 2019 MacBook Pro (Intel i9).

---

## 1. Prevent "Frozen" Screen & Constant Login
The "frozen" state is usually caused by macOS "App Nap" or Zorin's internal Screen Lock.

### Fix A: Disable macOS App Nap (Run on Mac Terminal)
This prevents macOS from pausing VMware Fusion when it's in the background.
* **To Disable App Nap:**
  `defaults write com.vmware.fusion NSAppSleepDisabled -bool YES`
* **To Check Current State:**
  `defaults read com.vmware.fusion NSAppSleepDisabled` (1 = Disabled, 0 or error = Default/Enabled)
* **To Restore to Original:**
  `defaults delete com.vmware.fusion NSAppSleepDisabled`

### Fix B: Disable Zorin Screen Lock (In Zorin Settings)
1. Go to **Settings** > **Privacy** > **Screen Lock**.
2. Set **Automatic Screen Lock** to **OFF**.
3. Set **Blank Screen Delay** to **Never**.

---

## 2. Power Management (VM-Specific)
Virtual machines should not handle their own power states; let the Mac handle it.

### Disable Suspend in Zorin
1. Go to **Settings** > **Power**.
2. Set **Automatic Suspend** to **Off**.

### Disable Hibernation via Terminal (In Zorin)
Run this to prevent the VM from trying to enter deep sleep:
`sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`

---

## 3. Performance & Quality of Life
Optimizations specifically for the 2019 MacBook Pro (i9 / Radeon 5500M).

### Ensure Open VM Tools is Updated
Run this in Zorin Terminal for better mouse/display integration:
`sudo apt update && sudo apt install open-vm-tools-desktop -y`

### Fix Time De-sync
If Zorin's clock is wrong after waking your Mac, run this to force a sync:
`sudo timedatectl set-ntp off && sudo timedatectl set-ntp on`

### Hardware Acceleration
In VMware Fusion (with the VM shut down):
1. Go to **Settings** > **Display**.
2. Check **Accelerate 3D Graphics**.
3. Set Shared Graphics Memory to **2GB** or **4GB** (The Radeon 5500M can easily handle this).

---
*Note: Closing the MacBook lid will still sleep the system normally. These settings only apply while the Mac is awake.*
"""

# Save the file to the accessible path
with open("/mnt/data/VMware_Zorin_Optimization_Guide.md", "w") as f:
    f.write(readme_content)