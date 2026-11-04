# Qidi Q2 CoreXY — Slicer G-Code Master Guide (AP Board Mint Suite)

This guide provides the exact copy-paste Custom G-code blocks for **OrcaSlicer**, **PrusaSlicer**, and **QidiStudio** calibrated for the Qidi Q2 AP Board Mint System Suite.

---

## 🎨 SETUP 1: WITH QIDI BOX (1-Extruder SEMM Multi-Material)

Use this setup if you selected **Yes** during installation to enable the Qidi Box.

### 1. OrcaSlicer "Basic Information" Tab
* **Extruders:** Set to `1`
* **Single Extruder Multi Material:** Check the box `[X]`

---

### 2. Custom G-Code Blocks (Copy & Paste)

#### A. Machine Start G-Code
```gcode
M73 P0 R168

;===== 1. HAPPY HARE INITIALIZATION =====
MMU_START_SETUP INITIAL_TOOL=[initial_tool] TOTAL_TOOLCHANGES=[total_toolchanges] TOOL_COLORS="[filament_colour]" TOOL_TEMPS="[nozzle_temperature_initial_layer]" TOOL_MATERIALS="[filament_type]" FILAMENT_NAMES="[filament_settings_id]"

; Pre-flight check: verifies required spools are loaded before heating
MMU_START_CHECK

;===== 2. MASTER PRINT START (Autonomous Thermal & Bed Leveling) =====
PRINT_START BED=[bed_temperature_initial_layer_single] HOTEND=[nozzle_temperature_initial_layer[initial_tool]] NEXT_HIGH_TEMP=[nozzle_temperature_range_high[initial_tool]] CHAMBER=[chamber_temperature[initial_tool]] EXTRUDER=[initial_tool] FILAMENT_TYPE="[filament_type[initial_tool]]" FILAMENT="[filament_settings_id[initial_tool]]"

;===== 3. LOAD INITIAL TOOL VIA HAPPY HARE =====
MMU_START_LOAD_INITIAL_TOOL

;===== 4. VOLUMETRIC BED PURGE LINE =====
PRIME_LINE INITIAL_LAYER_HEIGHT=[initial_layer_print_height] VOLUMETRIC_SPEED=15.0832
G90
G21
```

#### B. Machine End G-Code
```gcode
; Master Teardown: automatic blade cut, toolhead park, wiper polish & cooldown
PRINT_END MAX_LAYER_Z=[max_layer_z] CUR_EXTRUDER=[current_extruder] FILAMENT_TYPE="[filament_type]" FILAMENT_NAME="[filament_preset_name]"
```

#### C. Change Filament G-Code
```gcode
T[next_extruder]
```

#### D. Before Layer Change G-Code
```gcode
;BEFORE_LAYER_CHANGE
;[layer_z]
G92 E0
```

#### E. Layer Change G-Code
```gcode
;AFTER_LAYER_CHANGE
;[layer_z]
;===== HAPPY HARE & KLIPPER LAYER TRACKING =====
SET_GCODE_VARIABLE MACRO=TIMELAPSE_TAKE_FRAME VARIABLE=takingframe VALUE=False
_MMU_UPDATE_HEIGHT HEIGHT=[layer_num]
SET_PRINT_STATS_INFO CURRENT_LAYER=[layer_num]
G92 E0
M83
```

---

## 🖨️ SETUP 2: STANDALONE SINGLE EXTRUDER (No Qidi Box)

Use this setup if you run the Q2 as a standalone single-extruder printer without the MMU.

### Custom G-Code Blocks (Copy & Paste)

#### A. Machine Start G-Code
```gcode
; Master Print Start (Single Extruder Standalone)
PRINT_START BED=[bed_temperature_initial_layer_single] HOTEND=[nozzle_temperature_initial_layer] CHAMBER=[chamber_temperature] FILAMENT_TYPE="[filament_type]" FILAMENT="[filament_settings_id]"
PRIME_LINE INITIAL_LAYER_HEIGHT=[initial_layer_print_height] VOLUMETRIC_SPEED=15.0832
G90
G21
```

#### B. Machine End G-Code
```gcode
PRINT_END MAX_LAYER_Z=[max_layer_z]
```

#### C. Layer Change G-Code
```gcode
;AFTER_LAYER_CHANGE
;[layer_z]
SET_PRINT_STATS_INFO CURRENT_LAYER=[layer_num]
G92 E0
M83
```

---

## 💡 Notes on What the Macro Does Behind the Scenes
1. **Dynamic Anti-Ooze Parking:** Hotend parks at Z=1 mm over the silicone wiper during heat-up to prevent filament oozing onto the print bed.
2. **Autonomous Thermal Memory:** Remembers what plastic was previously in the nozzle (e.g. PC-ABS or PETG) and performs high-temperature flushes when switching to lower-temp materials (like PLA) so the nozzle never clogs.
3. **Nozzle Load Cell Bed Leveling:** Automatically tares and validates the nozzle strain gauge before taking the adaptive mesh.
