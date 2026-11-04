# 🚀 Qidi Q2 AP Board — "Mint System" Community Installer & Rescue Suite

[![Kalico](https://img.shields.io/badge/Firmware-Kalico%20(Danger--Klipper)-red.svg)](https://github.com/KalicoCrew/kalico)
[![Base Config](https://img.shields.io/badge/Base%20Foundation-n3oney%2Fqidi--q2--klipper-purple.svg)](https://github.com/n3oney/qidi-q2-klipper)
[![Katapult](https://img.shields.io/badge/Bootloader-Arksine%2FKatapult-yellow.svg)](https://github.com/Arksine/katapult)
[![Happy-Hare](https://img.shields.io/badge/MMU-Happy%20Hare%20v4-blue.svg)](https://github.com/moggieuk/Happy-Hare)
[![HelixScreen](https://img.shields.io/badge/UI-HelixScreen%20Touch%20UI-orange.svg)](https://github.com/prestonbrown/helixscreen)

---

> [!CAUTION]
> ## 🚨 CRITICAL PUBLIC WARNING — UNTESTED INSTALL SCRIPT, ZERO LIABILITY & NO SUPPORT 🚨
>
> **READ THIS CAREFULLY BEFORE DOWNLOADING OR RUNNING ANYTHING IN THIS REPOSITORY:**
>
> 1. **⚠️ THIS INSTALL SCRIPT HAS NEVER BEEN TESTED:**
>    * While the underlying firmware binaries, configurations, and AP board refinements inside this repository were extracted from a working pre-migration Qidi Q2 AP board backup, **the automated installer script (`install.sh`, `restore.sh`, and the `scripts/` automation wrapper) was built after migrating off the AP board and HAS NEVER BEEN TESTED ON A LIVE PRINTER.**
>    * By running this script, you acknowledge that you are acting as a tester at your own sole risk.
> 2. **🛑 ZERO LIABILITY FOR DAMAGES OR INJURIES:**
>    * **I (`clarkx800-rgb` / Pucci) am NOT responsible or liable for ANY damages, bricked boards, corrupted eMMC storage, broken printers, electrical/thermal fires, property damage, personal injuries, or anything else whatsoever** resulting directly or indirectly from using, flashing, or modifying files from this repository.
>    * 3D printers involve high-voltage mains power and high-temperature heating elements (hotend, heated bed, and PTC chamber/box heaters). You are 100% responsible for verifying your own hardware safety and supervising your machine at all times.
> 3. **🔕 NO SUPPORT PROVIDED:**
>    * **There will be NO official support, warranty, or personal troubleshooting provided for this repository.** It is shared publicly strictly **"AS-IS"** for community experimentation and educational inspection. If something breaks, you are on your own.

---

## 🤝 Credits, Original Authors & Upstream Repositories

This suite stands on the shoulders of the open-source 3D printing community. All credit for the underlying firmware engines, kernel builds, bootloaders, and add-ons belongs to their original authors:

| Project / Component | Original Author(s) | Description | Upstream GitHub Repository |
| :--- | :--- | :--- | :--- |
| **qidi-q2-klipper & 5.10 Kernel** | **n3oney** | Foundational Qidi Q2 Klipper porting work, RK3308 Linux `5.10.160` kernel (`q2_boot.img`), and Katapult deployers | [github.com/n3oney/qidi-q2-klipper](https://github.com/n3oney/qidi-q2-klipper) |
| **Kalico (Danger-Klipper)** | **Kalico Crew** | High-performance, low-latency Klipper fork with `[danger_options]`, load-cell probing, and nonlinear PA | [github.com/KalicoCrew/kalico](https://github.com/KalicoCrew/kalico) |
| **Klipper** | **Kevin O'Connor & Klipper3d** | Core 3D printer microcontroller and host motion control firmware | [github.com/Klipper3d/klipper](https://github.com/Klipper3d/klipper) |
| **Katapult (formerly CanBoot)** | **Arksine (Eric Callahan)** | Bootloader and `flashtool.py` serial/USB firmware deployer for STM32 / GD32 MCUs | [github.com/Arksine/katapult](https://github.com/Arksine/katapult) |
| **Moonraker** | **Arksine (Eric Callahan)** | Web API server and Klipper communication daemon | [github.com/Arksine/moonraker](https://github.com/Arksine/moonraker) |
| **Happy Hare v4** | **moggieuk** | Multi-Material Unit (MMU) driver and filament management ecosystem for the Qidi Box | [github.com/moggieuk/Happy-Hare](https://github.com/moggieuk/Happy-Hare) |
| **HelixScreen** | **Preston Brown** | Native C++20 / LVGL touchscreen interface for Klipper | [github.com/prestonbrown/helixscreen](https://github.com/prestonbrown/helixscreen) |
| **Klipper TMC Autotune** | **Andrew McGregor (`andrewmcgr`)** | Automatic TMC stepper driver current and register tuning | [github.com/andrewmcgr/klipper_tmc_autotune](https://github.com/andrewmcgr/klipper_tmc_autotune) |
| **Klippain Shake&Tune** | **Frix-x** | Input shaper and belt/vibration analysis graphs for Klipper | [github.com/Frix-x/klippain-shaketune](https://github.com/Frix-x/klippain-shaketune) |
| **Blobifier** | **Dendrowen & Hernsl** | Automated MMU purge blobbing and nozzle scrubber macro system | [github.com/Dendrowen/Blobifier](https://github.com/Dendrowen/Blobifier) |
| **ERCF Filament Cutter** | **kevinakasam** | Toolhead filament tip-cutting macro foundation | [github.com/kevinakasam/ERCF_Filament_Cutter](https://github.com/kevinakasam/ERCF_Filament_Cutter) |
| **CS1237 Load-Cell Driver** | **Anycubic / Community** | C & Python driver (`sensor_cs1237.c` / `cs1237.py`) for 24-bit ADC load-cell nozzle probing | [github.com/ANYCUBIC-3D/K3-klipper-mcu](https://github.com/ANYCUBIC-3D/K3-klipper-mcu) |
| **Spoolman** | **Donkie** | Filament spool inventory and weight tracking service | [github.com/Donkie/Spoolman](https://github.com/Donkie/Spoolman) |
| **Mainsail & Crowsnest** | **Mainsail Crew** | Web interface for Klipper and webcam streaming service | [github.com/mainsail-crew/mainsail](https://github.com/mainsail-crew/mainsail) / [crowsnest](https://github.com/mainsail-crew/crowsnest) |
| **Klipper-Backup** | **Staubgeborener** | Git-based configuration backup utility | [github.com/Staubgeborener/Klipper-Backup](https://github.com/Staubgeborener/Klipper-Backup) |

---

## 📦 What Is Included in This Suite?

This repository packages my pre-migration **Qidi Q2 OEM AP Board (Rockchip RK3308)** build, configurations, macros, and system refinements into a segmented menu:

* **Pick & Choose Menu:** Choose individual options one at a time.
* **Custom Named Backups:** Prompts you to **name a backup restore point** before running an option and saves a snapshot in `~/q2_ap_backups/`.
* **Keep Your Macros or Try Mine (Yes / No):** Choose **YES** to install my automated macro suite OR **NO** to keep your own existing macros. Option 4 right below it lets you restore your previous macros.
* **Separate Printer Firmware vs. Optional Qidi Box Firmware:** Flash the Motion Mainboard (`mcu.bin`) + Toolhead (`thr.bin`) together in Option 1, and optionally flash/enable or disable the Qidi Box (`mmu.bin`) in Option 2.
* **Separate AP Board Refinements:** Individual Apply + Restore options for the RTL8821CS Wi-Fi sleep killer (Option 5), the RK3308 `1.1 GHz performance` + `/etc/fstab` "Timer Too Close" fix (Option 6), and N3oney's `5.10.160` Linux kernel (Option 7).

---

## ⚡ Quick Start (At Your Own Risk)

Log into your Qidi Q2 via SSH (`ssh mks@<YOUR_PRINTER_IP>`, default password is `makerbase`) and copy-paste:

```bash
cd ~
git clone https://github.com/clarkx800-rgb/Q2-Install-Script-V1-2026.git
cd Q2-Install-Script-V1-2026
sudo bash install.sh
```

---

## 📋 Interactive Menu Layout (`install.sh`)

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
* **[`SLICER_GUIDE.md`](SLICER_GUIDE.md)** — Copy-paste Start G-Code, End G-Code, and Filament Change G-Code for OrcaSlicer / QidiStudio (both **With Qidi Box** and **Without Qidi Box**).
* **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** — Copy-paste terminal commands for checking USB connections, reading logs, fixing errors, and restoring backups.
