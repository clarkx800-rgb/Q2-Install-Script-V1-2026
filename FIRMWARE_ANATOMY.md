# 🧬 Qidi Q2 Firmware & Printer Anatomy (Plain-English Guide)

If you are new to Linux, Python, or Klipper, **don't worry!** This guide explains how your Qidi Q2 is built on the inside, what each board does, and how this firmware suite fixes the infamous **"Timer too close"** crashes on the stock Qidi AP Board.

---

## 🧠 1. The 4 "Brains" Inside Your Qidi Q2

Think of your 3D printer like a human body. Instead of having just one computer chip doing everything, your Qidi Q2 splits the job across **4 separate circuit boards**:

```text
+-------------------------------------------------------------------------+
|  1. THE MASTER BRAIN: Qidi OEM "AP Board" (Rockchip RK3308)             |
|     • Runs Linux, Kalico/Klipper Host, Moonraker, and Mainsail/Fluidd   |
|     • Reads your G-code file and calculates every tiny motor step       |
+-------------------------------------------------------------------------+
         |                                  |                        |
         | (Internal Wire: /dev/ttyS4)      | (USB Cable)            | (USB Cable)
         v                                  v                        v
+------------------------+     +-------------------------+   +-----------------------+
| 2. TOOLHEAD BOARD (THR)|     | 3. MOTION MAINBOARD(mcu)|   | 4. QIDI BOX (MMU)     |
|    Chip: GD32F303      |     |    Chip: GD32F425       |   |    Chip: STM32F401    |
| • Heats the nozzle     |     | • Moves X, Y, Z motors  |   | • Feeds 4 filament    |
| • Spins extruder gears |     | • Heats the print bed   |   |   slots into printer  |
| • Reads CS1237 Loadcell|     | • Controls chamber fans |   | • Runs Happy Hare MMU |
+------------------------+     +-------------------------+   +-----------------------+
```

### Why does this matter?
* **The AP Board (Master Brain)** does all the heavy math in Python and Linux.
* **The 3 Microcontrollers (Motion MCU, Toolhead THR, and Qidi Box)** don't think for themselves—they just follow timed instructions sent by the AP Board every fraction of a millisecond.
* **IMPORTANT RULE:** Whenever the Master Brain (Kalico/Klipper on the AP Board) is updated, the little microcontroller boards (`mcu.bin`, `thr.bin`, `mmu.bin`) must speak the **exact same version language**, or Klipper will complain about a `Protocol / Version mismatch`.

---

## 🚪 2. What is "Katapult" vs. "Klipper/Kalico Firmware"?

People on Discord often ask: *"What is Katapult, and why do I need it?"*

Think of each circuit board like a house:
1. **The Bootloader (Katapult) is the Front Door (`0x08000000`):**
   * From the factory, Qidi locked the front door on the Motion Mainboard so it only accepts firmware from a physical Micro-SD card.
   * **Katapult** replaces that locked door with an open "Smart Door" that stays on the chip permanently.
   * Once Katapult is installed, you **never** need to open the electronics bay or use an SD card again—you can update firmware anytime with one click over USB or serial!
2. **The Firmware (`mcu.bin`, `thr.bin`, `mmu.bin`) is the Furniture Inside:**
   * This is the actual Klipper/Kalico microcontroller code that Katapult loads right behind the front door (`32KiB` or `8KiB` offset).

---

## 🛠️ 3. How Each Firmware Binary Was Constructed (`menuconfig` Specs)

If you ever want to compile the firmware yourself using `make menuconfig`, here is the exact blueprint used to build the binaries in `firmwares/precompiled/`:

### A. Motion Mainboard (`firmwares/precompiled/mcu.bin`)
* **Microcontroller Architecture:** `STMicroelectronics STM32` (Compatible with `GD32F425`)
* **Processor Model:** `STM32F407` / `GD32F425` (168 MHz Clock Speed)
* **Bootloader Offset:** `32KiB bootloader (Katapult / Qidi stock offset)`
* **Clock Reference:** `8 MHz crystal`
* **Communication Interface:** `USB (on PA11/PA12)`
* **Special Feature:** Includes hardware PWM and pin support for coreXY stepper drivers and bed heating.

### B. Toolhead Board (`firmwares/precompiled/thr.bin`)
* **Microcontroller Architecture:** `STMicroelectronics STM32` (Compatible with `GD32F303`)
* **Processor Model:** `STM32F103` / `GD32F303` (120 MHz Clock Speed, `clone-stm32f103` optimization enabled)
* **Bootloader Offset:** `8KiB bootloader (Katapult)`
* **Clock Reference:** `8 MHz crystal`
* **Communication Interface:** `Serial (on USART1 PA10/PA9)` -> Connects to AP Board `/dev/ttyS4`
* **Baud Rate:** `500000` (500k high-speed internal serial)
* **Special Feature:** Compiled with the custom **CS1237 Load-Cell C Driver** (`sensor_cs1237.c`) so the nozzle itself acts as a high-precision Z-probe.

### C. Qidi Box MMU (`firmwares/precompiled/mmu.bin`)
* **Microcontroller Architecture:** `STMicroelectronics STM32`
* **Processor Model:** `STM32F401` (84 MHz Clock Speed)
* **Bootloader Offset:** `32KiB bootloader`
* **Clock Reference:** `8 MHz crystal`
* **Communication Interface:** `USB (on PA11/PA12)`

---

## ⚡ 4. Why "Timer Too Close" Happens on the Stock AP Board (And How We Fixed It)

The Qidi OEM AP Board has a tiny 4-core **Rockchip RK3308** processor with only **512 MB of RAM**.

When printing fast, the AP Board must send thousands of motor steps per second to the Mainboard and Toolhead. If the AP Board freezes for even **0.05 seconds (50 milliseconds)**, the toolhead runs out of instructions and emergency-stops with:
> `MCU 'THR' shutdown: Timer too close`

### Our 3 Segmented Refinements Fix Every Cause of That Freeze:

| Menu Option | What Was Broken on Stock Qidi | How Our Refinement Fixes It |
| :--- | :--- | :--- |
| **Option 5: Network Adapter Refinement** | The onboard Realtek `RTL8821CS` Wi-Fi chip constantly goes into "power-save sleep mode", causing huge lag spikes when uploading G-code or viewing Mainsail. | Installs `8821cs.conf` & udev rules to permanently disable Wi-Fi sleep mode, plus expands Linux TCP buffers to 2MB. |
| **Option 6: AP Board Refinement** | 1. Linux throttles the CPU speed up and down (`ondemand`) causing micro-stutters.<br>2. `/etc/fstab` uses `sync`, which freezes the whole CPU every time Klipper writes a single line to the log file.<br>3. Hidden Makerbase cloud services steal 25% of the CPU. | 1. Locks all 4 CPU cores to **1.1 GHz `performance` mode**.<br>2. Changes disk writes to `noatime,commit=30` (zero disk freeze).<br>3. Stops background Makerbase bloatware services. |
| **Option 7: N3oney's 5.10 Kernel** | Factory Qidi uses an ancient Linux kernel with buggy USB/serial interrupt scheduling. | Flashes N3oney's modern **Linux 5.10.160 kernel** (`q2_boot.img`) with rock-solid real-time USB and UART scheduling. |
