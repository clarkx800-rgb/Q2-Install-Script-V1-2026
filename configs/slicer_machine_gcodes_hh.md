<p align="center">
  <h1 align="center"> Q2 Happy Hare Standalone Slicer Machine G-Codes</h1>
</p>

# MACHINE START G-CODE

Possible to modify - the general idea is:
```
*****CONCEPTUAL - DO NOT COPY WITHOUT MODIFICATION*****

MMU_START_SETUP INITIAL_TOOL={initial_tool} TOTAL_TOOLCHANGES=!total_toolchanges! REFERENCED_TOOLS=!referenced_tools! TOOL_COLORS=!colors! TOOL_TEMPS=!temperatures! TOOL_MATERIALS=!materials! FILAMENT_NAMES=!filament_names! PURGE_VOLUMES=!purge_volumes!
MMU_START_CHECK

; your homing, preheating, leveling, etc goes here
; nothing that requires filament in the extruder though!

MMU_START_LOAD_INITIAL_TOOL

; your purging logic goes here

SET_PRINT_STATS_INFO CURRENT_LAYER=1
SET_PRINT_STATS_INFO TOTAL_LAYER={total_layer_count}
```

The gcode below is a Qidi start g-code modified with Happy Hare (and thus can be copied into your slicer):
```
;===== 1. HAPPY HARE INITIALIZATION =====
MMU_START_SETUP INITIAL_TOOL=[initial_tool] TOTAL_TOOLCHANGES=[total_toolchanges] TOOL_COLORS="[filament_colour]" TOOL_TEMPS="[nozzle_temperature_initial_layer]" TOOL_MATERIALS="[filament_type]" FILAMENT_NAMES="[filament_settings_id]"

; Checks if spools are loaded BEFORE heating
MMU_START_CHECK

;===== 2. MASTER PRINT START =====
PRINT_START BED=[bed_temperature_initial_layer_single] HOTEND=[nozzle_temperature_initial_layer[initial_tool]] NEXT_HIGH_TEMP=[nozzle_temperature_range_high[initial_tool]] CHAMBER=[chamber_temperature[initial_tool]] EXTRUDER=[initial_tool] FILAMENT_TYPE="[filament_type[initial_tool]]" FILAMENT="[filament_settings_id[initial_tool]]"

;===== 3. LOAD INITIAL TOOL VIA HAPPY HARE =====
MMU_START_LOAD_INITIAL_TOOL

;===== 4. VOLUMETRIC BED PURGE LINE =====
G90
G21
PRIME_LINE INITIAL_LAYER_HEIGHT=[initial_layer_print_height] VOLUMETRIC_SPEED=15.0832

;===== QIDI PURGE SEQUENCE =====
G1 X108.000 Y1 F30000
G0 Z[initial_layer_print_height] F600
;G1 E3 F1800
G90
M83
G0 X128 E8  F{outer_wall_volumetric_speed/(24/20)    * 60}
G0 X133 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}
G0 X138 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}
G0 X143 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}
G0 X148 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}
G0 X153 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}
G91
G1 X1 Z-0.300
G1 X4
G1 Z1 F1200
G90
M400
G1 X108.000 Y2.5 F30000
G0 Z[initial_layer_print_height] F600
M83
G0 X128 E10  F{outer_wall_volumetric_speed/(24/20)    * 60}
G0 X133 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}
G0 X138 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}
G0 X143 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}
G0 X148 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}
G0 X153 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}
G91
G1 X1 Z-0.300
G1 X4
G1 Z1 F1200
G90
M400
G1 Z1 F600

```

# MACHINE END G-CODE
```
; Recommended (Master Teardown Macro with automatic blade cut, wiper polish & cooldown):
PRINT_END MAX_LAYER_Z=[max_layer_z] CUR_EXTRUDER=[current_extruder] FILAMENT_TYPE="[filament_type]" FILAMENT_NAME="[filament_preset_name]"

; Alternative (Raw manual sequence):
; MMU_END
; DISABLE_BOX_HEATER
; M141 S0
; M140 S0
; DISABLE_ALL_SENSOR
; G1 E-3 F1800
; G0 Z{max_layer_z + 3} F600
; UNLOAD_FILAMENT T=[current_extruder]
; G0 Y270 F12000
; G0 X90 Y270 F12000
; {if max_layer_z < max_print_height / 2}G1 Z{max_print_height / 2 + 10} F600{else}G1 Z{min(max_print_height, max_layer_z + 3)}{endif}
; M104 S0
```
# BEFORE LAYER CHANGE G-CODE
```

```

# LAYER CHANGE G-CODE
```
{if timelapse_type == 1} ; timelapse with wipe tower
G92 E0
G1 E-[retraction_length] F1800
G2 Z{layer_z + 0.4} I0.86 J0.86 P1 F20000 ; spiral lift a little
G1 Y235 F20000
G1 X97 F20000
{if layer_z <=25}
G1 Z25
{endif}
G1 Y254 F2000
G92 E0
M400
TIMELAPSE_TAKE_FRAME
G1 E[retraction_length] F300
G1 X85 F2000
G1 X97 F2000
G1 Y220 F2000
{if layer_z <=25}
G1 Z[layer_z]
{endif}
{elsif timelapse_type == 0} ; timelapse without wipe tower
TIMELAPSE_TAKE_FRAME
{endif}
_MMU_UPDATE_HEIGHT HEIGHT={layer_num + 1} 
G92 E0
SET_PRINT_STATS_INFO CURRENT_LAYER={layer_num + 1}
```

# TIME LAPSE G-CODE
```
TIMELAPSE_TAKE_FRAME
```

# CHANGE FILAMENT G-CODE
```
T[next_extruder]
```

# CHANGE EXTRUSION ROLE G-CODE
```

```

# PAUSE G-CODE
```
M0
```

# TEMPLATE CUSTOM G-CODE
```

```