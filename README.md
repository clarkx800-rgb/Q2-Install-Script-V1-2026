# 🚀 Qidi Q2 AP Board — "Mint System" Community Installer & Rescue Suite

Welcome! This all-in-one, beginner-friendly suite brings **Pucci's pre-migration AP Board firmware, macros, and "Timer Too Close" refinements** to any Qidi Q2 running the stock **OEM Rockchip RK3308 AP Board**.

### 🛡️ Built for Total Peace of Mind (Zero Linux/Python Skills Required)
* **Pick & Choose Menu:** You don't have to install everything at once! Choose only the parts you want from a simple numbered menu.
* **Custom Named Backups Every Time:** Every time you select an action to perform, the script asks you to **name a backup restore point** first and saves a 100% restorable snapshot in `~/q2_ap_backups/`.
* **Keep Your Macros or Try Pucci's (Yes / No):** Choose **YES** to install Pucci's full automated macro suite OR **NO** to keep your own existing macros. Don't like Pucci's macros after trying them? Select **Option 4** right below it to restore your old macros in 5 seconds!
* **Works on Super-Stock Printers:** Includes all Katapult bootloaders (`mcu-deployer.bin`, `thr-deployer.bin`, `mmu-deployer.bin`) and precompiled firmware binaries (`mcu.bin`, `thr.bin`, `mmu.bin`).

---

## ⚡ Quick Start (Copy & Paste into Your Printer's SSH Terminal)

Log into your Qidi Q2 via SSH (`ssh mks@<YOUR_PRINTER_IP>`, default password is `makerbase`) and copy-paste these commands:

```bash
cd ~
git clone https://github.com/clarkx800-rgb/Q2-Install-Script-V1-2026.git
cd Q2-Install-Script-V1-2026
sudo bash install.sh
```

*(Want to pull future updates later? Just run `cd ~/Q2-Install-Script-V1-2026 && git pull`!)*

---

## 📋 What's Inside the Interactive Menu (`install.sh`)?

```text
========================================================================
   🛠️  QIDI Q2 AP BOARD — COMMUNITY INSTALLER & RESCUE CONTROL CENTER
========================================================================
  --- FIRMWARE & MACROS ---
  [1] 🖨️  Install Printer Firmware (Motion Mainboard MCU + Toolhead MCU)
  [2] 🎨 Install / Configure Qidi Box MMU Firmware (Optional / Separate)
  [3] 🧩 Macro Setup: Install Pucci's Macros OR Keep Your Own Macros
  [4] ⏪ Restore Your Previous Macros (If you don't like Pucci's macros)

  --- AP BOARD REFINEMENTS (EACH SEPARATE & RESTORABLE) ---
  [5] 📡 Network Adapter Refinement (Apply or Restore Wi-Fi Sleep Fix)
  [6] ⚡ AP Board 'Timer Too Close' Refinement (Apply or Restore CPU/Disk Fix)
  [7] 🐧 N3oney's Modern 5.10 Linux Kernel (Install or Restore q2_boot.img)

  --- BACKUP, RESTORE & HELP ---
  [8] 🔄 Universal Restore Center (Restore 100% from any named backup)
  [9] 📖 Tips, Instructions, Firmware Anatomy & Troubleshooting
  [0] 🚪 Exit Installer
========================================================================
```

---

## 📚 Inspect the Included Guides Directly on GitHub
* **[`FIRMWARE_ANATOMY.md`](FIRMWARE_ANATOMY.md)** — Plain-English visual guide showing how the 4 boards inside your Qidi Q2 work together and how the firmware is constructed.
* **[`SLICER_GUIDE.md`](SLICER_GUIDE.md)** — Exact copy-paste Start G-Code, End G-Code, and Filament Change G-Code for OrcaSlicer / QidiStudio (both **With Qidi Box** and **Without Qidi Box**).
* **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** — Copy-paste terminal commands for checking USB connections, reading logs, fixing errors, and restoring backups.
