# Neon Infinity Duo

Two-player co-op platformer (Godot 4.3, GDScript) with ESP32 joystick controllers.
7 levels (2 easy, 2 medium, 2 hard, 1 alien-escape boss), 30-60 s timer per level, +10 points per second left. Dark-neon look, soft sounds (music + voices off by default).

**Start here:** `docs/Neon_Infinity_Duo_Build_Guide.pdf` (wiring, flashing, Godot, export, troubleshooting).

## Quick start (keyboard only)
1. Install Godot 4.3 (standard). Project Manager -> Import -> `project.godot` -> Play (F5).
2. P1: A/D + W/Space. P2: arrows. P/Esc pause, R restart level, hold Backspace = home.

## With the joysticks
1. Flash `esp32/esp32_controller.ino` to both boards (board 1: `PLAYER_ID 1`, `HAS_DISPLAY true`; board 2: `2`, `false`).
2. `pip install pyserial`, run `python tools/check_setup.py`, then `python tools/serial_bridge.py` (or double-click `tools/start_bridge.bat`).
3. Start the game. Stick = move, JUMP / STOP / PAUSE / START buttons.

## Folders
- `scripts/` game code (`main.gd` rules, `ui.gd` menus/HUD, `player.gd`, `levels.gd` data, autoloads `look/controllers/sfx`)
- `audio/` all sounds (overwrite a .wav to replace it); `audio/voice/` optional recorded voice lines
- `esp32/` firmware - `tools/` serial bridge, level + audio generators, test bots - `docs/` guide + diagrams
- `export_presets.cfg` Windows + Linux export presets (needs Godot export templates)

## Tests (optional)
```
godot --headless -s tools/bot_test.gd -- all invincible     # bots play all 10 levels
xvfb-run godot --rendering-driver opengl3 -s tools/shots.gd -- /tmp/shots   # screenshots
```
