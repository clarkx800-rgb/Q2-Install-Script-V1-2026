# Qidi Q2 CoreXY + Happy Hare v4 + Qidi Box v2 (BEv2) + HelixScreen

[![Kalico](https://img.shields.io/badge/Firmware-Kalico%20(Danger--Klipper)-red.svg)](https://github.com/Kalico/kalico)
[![Happy-Hare](https://img.shields.io/badge/MMU-Happy%20Hare%20v4-blue.svg)](https://github.com/moggieuk/Happy-Hare)
[![HelixScreen](https://img.shields.io/badge/UI-HelixScreen%20Touch%20UI-orange.svg)](https://github.com/prestonbrown/helixscreen)
[![Base Config](https://img.shields.io/badge/Base%20Config-n3oney%2Fqidi--q2--klipper-purple.svg)](https://github.com/n3oney/qidi-q2-klipper)
[![Moonraker](https://img.shields.io/badge/API-Moonraker-green.svg)](https://github.com/Arksine/moonraker)

---

> [!CAUTION]
> ### ⚠️ STRICT DISCLAIMER & LIABILITY NOTICE
> **USE ENTIRELY AT YOUR OWN RISK.**
> 
> * **Zero Liability**: The author and maintainers of this repository accept **absolutely NO responsibility or liability** for any damage to your 3D printer, equipment, property, computers, electronics, wiring, or physical injury resulting directly or indirectly from the use, flashing, modifying, or partial copying of these configuration files, macros, or scripts.
> * **Not Professionally Tested**: **This build has NOT been thoroughly tested, certified, or validated by professionals.** It is an experimental hobbyist project developed specifically on custom hardware for a modified printer.
> * **Thermal Safety**: This setup controls high-current PTC heating elements, high-voltage heated beds, and high-temp hotends. You are solely responsible for verifying your own wiring, ensuring thermal watchdogs and emergency stop systems are functioning, and supervising your printer at all times.
> * **Backup Your Stock System**: Always make a complete image backup of your original firmware, configs, and storage before deploying any community configuration.

---

## 📖 Overview

This repository contains the complete configuration, g-code macro suite, and UI layouts for a **Qidi Q2 CoreXY 3D printer** upgraded with a **Qidi Box v2 MMU** (BEv2 / Box Turtle / VirtualSelector architecture), running a clean, open-source firmware stack powered by **Kalico**, **Happy Hare v4**, and **HelixScreen**.

This project originates from and heavily builds upon the foundational groundwork established by [n3oney/qidi-q2-klipper](https://github.com/n3oney/qidi-q2-klipper). It replaces proprietary Qidi firmware components and obsolete "bunnybox" logic with a modernized, high-performance, open-source multi-material setup.

---

## ⚡ What This Build Does

### 1. Happy Hare v4 Multi-Material System (Qidi Box v2)
* **4-Gate Automated Feeding**: Direct control over the Qidi Box v2 multi-gear feeder mechanism driven by an onboard STM32F401 MCU (`mcu mmu`).
* **Custom Q2 Toolhead Tip Cutting (`_MMU_CUT_TIP`)**: Physical tip cutting sequence engineered specifically for the Qidi Q2 toolhead cutter pin, including temperature-aware retraction, stepper current boosting, and cutter pin safety clearances.
* **Phase 6–8 Dynamic Purge & Wiper Routing (`_CUSTOM_POST_LOAD_ACTION`)**: Automated post-load thermal ramp, shift purge into the trash chute, active cooldown assist with 100% fan assist, and precision silicone wiper cleaning.
* **Endless Spool Failover**: Automatic lane failover on filament runout with Spoolman inventory tracking.

### 2. Active Drybox Thermal & Ambient Humidity Management
* **Dual-Thermistor PTC Core Heater (`box1_heater`)**: Actively drives the PTC heater element in the MMU drybox with a mean combination filter and a strict 20°C differential safety watchdog.
* **Closed-Loop Ambient Spool Regulation (`box_dryer_monitor`)**: Dynamically boosts core temperature to safely warm ambient chamber air to the user's target setpoint (capped at a 68°C core ceiling), throttling back as ambient temperature stabilizes.
* **Real-time Ambient Humidity Telemetry**: Backed by an onboard AHT20/21 sensor (`box1_chamber_humidity`) reporting live humidity percentage and ambient temperature.
* **Automatic Air Circulation**: Forced air circulation blowers (`box1_heater_fan_a/b`) automatically activate whenever the heating core exceeds 30°C, ensuring uniform heat distribution and moisture exhaust.

### 3. HelixScreen Touch UI Customizations
* **Native C++20 / LVGL Interface**: Fast, responsive 60 FPS touch interface replacing legacy touchscreens.
* **Live Drybox Humidity Widget**: Home Dashboard teardrop icon displaying real-time enclosure humidity percentage.
* **Dedicated Box Temperature Input Tile**: Positioned on the Home Dashboard (Row 3, Col 3—directly below humidity). Tapping it launches an on-screen numeric keypad modal prompting for target temperature (`BOX_TEMPERATURE TEMP=<degrees>`), with `0` instantly stopping the heater.
* **AMS Environment & Dryer Overlay**: Seamless integration with HelixScreen's native AMS panel, supporting filament material drying presets, duration countdown timers, and live temperature progress graphs.

### 4. Advanced Kinematics, Autotuning & Calibration
* **TMC Stepper Driver Autotuning**: Configured with `klipper_tmc_autotune` for quiet, cool, and precise CoreXY stepper performance.
* **Dual Z-Tilt Tramming (`Z_TILT_ADJUST`)**: Independent dual-stepper bed tilt alignment.
* **Resonance Sweeps & Input Shaping**: Tuned shaper profiles (`smooth_mzv`) calibrated using the onboard toolhead accelerometer (`lis2dw`).

---

## 🛠️ Components & Upstream Projects Used

This build relies on and integrates the following open-source projects:

| Project | Description | Official Repository |
| :--- | :--- | :--- |
| **Qidi Q2 Klipper** | Original foundational base configuration for Qidi Q2 & Happy Hare | [n3oney/qidi-q2-klipper](https://github.com/n3oney/qidi-q2-klipper) |
| **Kalico** | High-performance, low-latency Danger-Klipper fork | [Kalico/kalico](https://github.com/Kalico/kalico) |
| **Happy Hare v4** | Multi-Material Management (MMU) ecosystem for Klipper | [moggieuk/Happy-Hare](https://github.com/moggieuk/Happy-Hare) |
| **HelixScreen** | Native C++20 / LVGL touchscreen UI for Klipper | [prestonbrown/helixscreen](https://github.com/prestonbrown/helixscreen) |
| **Moonraker** | Web API Server and Klipper companion daemon | [Arksine/moonraker](https://github.com/Arksine/moonraker) |
| **Spoolman** | Filament spool tracking and multi-material inventory manager | [Donkie/Spoolman](https://github.com/Donkie/Spoolman) |
| **Klipper-Backup** | Automatic and manual Git-based configuration backup script | [Staubgeborener/Klipper-Backup](https://github.com/Staubgeborener/Klipper-Backup) |
| **Klipper TMC Autotune** | Automatic motor current and tuning calculation for TMC drivers | [andrewmcgr/klipper_tmc_autotune](https://github.com/andrewmcgr/klipper_tmc_autotune) |
| **Crowsnest** | High-performance webcam streaming daemon | [mainsail-crew/crowsnest](https://github.com/mainsail-crew/crowsnest) |
| **Blobifier** | Automated purge bucket and nozzle scrub system | [Dendrowen/Blobifier](https://github.com/Dendrowen/Blobifier) |

---

## 💻 Hardware Architecture

* **Printer**: Qidi Q2 CoreXY (Motherboard MCU: STM32F402 / Host: Linaro Debian aarch64)
* **MMU Hardware**: Qidi Box v2 (4-gate multi-gear selectorless feeder)
  * MMU MCU: `stm32f401xc` over USB serial (`/dev/serial/by-id/usb-Klipper_stm32f401xc_...`)
  * Drybox PTC Heater: Pin `mmu:PA3` (`box1_heater`)
  * Chamber Thermistors: Pins `mmu:PC1` & `mmu:PC2` (dual NTC 100K 3950)
  * Chamber Environment: Pin `mmu:PA1` (I2C AHT20 sensor)
  * Dual Circulation Fans: Pins `mmu:PA4` & `mmu:PA5`
  * MMU Mainboard Fan: Pin `mmu:PA6`
* **Toolhead**: Qidi Q2 toolhead with filament cutter arm, silicone wiper brush, and `lis2dw` resonance accelerometer.

---

## 🚀 Installation & Deployment

> [!NOTE]
> **Installation Guide Coming Soon**: A comprehensive, step-by-step installation procedure and setup injection guide are currently in development and will be added in a future update.
> 
> At this time, this repository is intended as a configuration reference and backup for advanced users familiar with Klipper, Happy Hare, and Linux environments.

---

## 🤝 Acknowledgments & Credits

Special thanks to:
* **n3oney** for the foundational [n3oney/qidi-q2-klipper](https://github.com/n3oney/qidi-q2-klipper) repository that made mainline Klipper and Happy Hare possible on the Qidi Q2.
* **Moggieuk** for the incredible work on [Happy Hare v4](https://github.com/moggieuk/Happy-Hare).
* **Preston Brown** for [HelixScreen](https://github.com/prestonbrown/helixscreen).
* The **Kalico / Danger-Klipper** team for high-speed firmware enhancements.
* The open-source 3D printing community for ongoing support and innovation.
