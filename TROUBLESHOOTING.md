# 🚑 Beginner Troubleshooting & Copy-Paste Terminal Commands

Don't know Linux or Python? **No problem!**
If anything ever acts weird, just **copy and paste** the exact commands below into your SSH terminal (like PuTTY, Windows Terminal, or Mac Terminal) and press **ENTER**.

---

## 🆘 1. "Help! I want to undo a change or restore my printer back to how it was!"

Every time you pick an option in our installer, it saves a **named backup** in `~/q2_ap_backups/`.
To open the interactive Restore Menu and put your printer back 100%, copy and paste:

```bash
cd ~/Q2-Install-Script-V1-2026 2>/dev/null || cd ~/qidi_q2_ap_board_mint_suite
sudo bash restore.sh
```

Want to restore **only your old macros** because you didn't like Pucci's macros? Copy and paste:

```bash
cd ~/Q2-Install-Script-V1-2026 2>/dev/null || cd ~/qidi_q2_ap_board_mint_suite
sudo bash scripts/manage_macros.sh --restore
```

---

## 🔌 2. Mainsail says: `mcu 'mcu': Unable to connect` (Mainboard USB Issue)

This usually means the USB ID in `printer.cfg` doesn't match your Mainboard's unique serial number, or the Mainboard is waiting in Katapult mode.

### Step A: Check what USB boards your AP Board can see
Copy and paste this command:
```bash
ls -l /dev/serial/by-id/
```

**What you should see:**
* A line containing `stm32f407xx` -> That is your **Motion Mainboard (`[mcu]`)**.
* A line containing `stm32f401xc` -> That is your **Qidi Box (`[mcu mmu]`)** (if plugged in).

### Step B: What if the name says `usb-katapult_stm32f407xx...` instead of `usb-Klipper_...`?
That just means the board is waiting in Katapult bootloader mode for its firmware! Re-run Option 1 of the installer to send `mcu.bin` to it:
```bash
cd ~/Q2-Install-Script-V1-2026 2>/dev/null || cd ~/qidi_q2_ap_board_mint_suite
sudo bash scripts/flash_firmware.sh --printer
```

---

## 🔥 3. Mainsail says: `mcu 'THR': Unable to connect` (Toolhead Issue)

On the AP Board, the Toolhead does **not** show up in `/dev/serial/by-id/` because it uses an internal wire called `/dev/ttyS4`.

### Step A: Check if `/dev/ttyS4` exists
Copy and paste:
```bash
ls -l /dev/ttyS4
```

### Step B: Re-flash the Toolhead over `/dev/ttyS4`
If the toolhead stopped responding after a flash, turn the printer's **physical power switch OFF for 10 seconds**, turn it back ON, wait 30 seconds, and copy-paste:
```bash
cd ~/Q2-Install-Script-V1-2026 2>/dev/null || cd ~/qidi_q2_ap_board_mint_suite
sudo systemctl stop klipper
python3 firmwares/flashtool.py -d /dev/ttyS4 -b 500000 -f firmwares/precompiled/thr.bin
sudo systemctl start klipper
```

---

## 📜 4. How to See the Exact Error in Klipper's Log File

When Klipper shows an orange error box in Mainsail, the real reason is always at the very bottom of `klippy.log`.
Copy and paste this command to see the last 50 lines of the log:

```bash
tail -n 50 ~/printer_data/logs/klippy.log
```

To search ONLY for error messages inside the log, copy and paste:
```bash
grep -iE "error|exception|unable|shutdown|timer too close" ~/printer_data/logs/klippy.log | tail -n 30
```

---

## 🔄 5. Handy Everyday Restart & Health Check Commands

### Restart Klipper and Moonraker (Safe anytime not printing)
```bash
sudo systemctl restart klipper moonraker
```

### Check if all 4 CPU Cores are locked to 1.1 GHz `performance` mode
```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```
*(All 4 lines should say `performance` after running Menu Option 6).*

### Check if Wi-Fi Power-Save Sleep Mode is OFF
```bash
sudo iw dev wlan0 get power_save
```
*(Should say `Power save: off` after running Menu Option 5).*

### Check Which Linux Kernel Version is Running
```bash
uname -r
```
*(Shows `5.10.160` after running Menu Option 7 and rebooting).*
