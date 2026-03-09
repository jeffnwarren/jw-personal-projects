# VMware Fusion: Zorin OS 18 Core Power Optimization Guide

This guide covers how to prevent Zorin OS from freezing/locking and how to optimize performance on a 2019 MacBook Pro (Intel i9).

> **Note:** Most of the VM-side items in this guide are now automated by `zorin-tune.sh`
> (P9: screen lock/animations, P13: suspend/hibernate). The Mac-side App Nap item
> is handled by `vmware-fusion-setup.sh` (Step 6). Hardware Acceleration requires
> manual steps in VMware Fusion Settings.

---

## 1. Prevent "Frozen" Screen & Constant Login

The "frozen" state is usually caused by macOS "App Nap" or Zorin's internal Screen Lock.

### Fix A: Disable macOS App Nap (Mac-side — automated by vmware-fusion-setup.sh)

This prevents macOS from pausing VMware Fusion when it's in the background.

- **To Disable App Nap:**
  `defaults write com.vmware.fusion NSAppSleepDisabled -bool YES`
- **To Check Current State:**
  `defaults read com.vmware.fusion NSAppSleepDisabled` (1 = Disabled, 0 or error = Default/Enabled)
- **To Restore to Original:**
  `defaults delete com.vmware.fusion NSAppSleepDisabled`

### Fix B: Disable Zorin Screen Lock (automated by zorin-tune.sh P9)

Handled via gsettings in P9 (GNOME desktop optimization). To do manually in Zorin:

1. Go to **Settings** > **Privacy** > **Screen Lock**.
2. Set **Automatic Screen Lock** to **OFF**.
3. Set **Blank Screen Delay** to **Never**.

Or via terminal:
```bash
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
```

---

## 2. Power Management (VM-Specific)

Virtual machines should not handle their own power states; let the Mac handle it.

### Disable Suspend/Hibernate in Zorin (automated by zorin-tune.sh P13)

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Disable Suspend in Zorin Settings (manual)

1. Go to **Settings** > **Power**.
2. Set **Automatic Suspend** to **Off**.

---

## 3. Performance & Quality of Life

Optimizations specifically for the 2019 MacBook Pro (i9 / Radeon 5500M).

### Ensure Open VM Tools is Updated (automated by zorin-tune.sh P4)

```bash
sudo apt update && sudo apt install open-vm-tools-desktop -y
```

### Disable Desktop Animations (automated by zorin-tune.sh P9)

```bash
gsettings set org.gnome.desktop.interface enable-animations false
```

Or via **Zorin Appearance** > **Effects** > uncheck **Enable Animations**.

### Fix Time De-sync (manual, run after waking Mac)

If Zorin's clock is wrong after waking your Mac, force a sync:
```bash
sudo timedatectl set-ntp off && sudo timedatectl set-ntp on
```

### Hardware Acceleration (manual — VMware Fusion Settings)

In VMware Fusion (with the VM shut down):
1. Go to **Settings** > **Display**.
2. Check **Accelerate 3D Graphics**.
3. Set Shared Graphics Memory to **2GB** or **4GB** (the Radeon 5500M can handle this).

---

*Note: Closing the MacBook lid will still sleep the system normally. These settings only apply while the Mac is awake.*
