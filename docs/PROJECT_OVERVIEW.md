# Project Overview

## Summary

This repository contains a cross-platform C++20 real-time boxing TUI. The game keeps the combat loop running continuously, renders an arena in the terminal, and lets the enemy learn from player behavior over time.

## Current Progress

- Real-time ring combat is implemented.
- The game uses title, battle, and victory phases.
- The player can respawn between rounds.
- The enemy AI combines pattern tracking with Q-learning style updates.
- Save/load persists combat state, player profile data, and AI learning state.
- The UI has been rethemed into a boxing ring with boxer/opponent language.
- The ring size, punch reach, and defensive responses have been tuned toward boxing-style spacing.

## Runtime Flow

1. `src/main.cpp` creates `GameSession`.
2. `GameSession` owns the battle state, AI, save system, and input loop.
3. `InputReader` polls the keyboard in raw mode.
4. `GameSession` applies player or enemy actions, advances the world, and emits logs.
5. `GameRenderer` turns the current `GameView` into either ANSI output or FTXUI output.

## File Map

### Build and entry

- `CMakeLists.txt` configures the `game_core`, `game_tui`, and `game_tests` targets, plus optional FTXUI support.
- `src/main.cpp` is the executable entry point.

### Core gameplay

- `include/game/game_session.hpp` and `src/game/game_session.cpp` coordinate the entire match loop.
- `include/game/battle_state.hpp` describes the combat arena, fighter positions, HP, stamina, and round state.
- `include/game/character.hpp` and `src/game/character.cpp` define character motion, attack timing, knockback, invulnerability, and animation timing.
- `include/game/action.hpp` and `src/game/action.cpp` define the action set and string labels.

### UI and input

- `include/game/game_view.hpp` defines the render-ready snapshot passed to the UI.
- `include/game/game_renderer.hpp` and `src/game/game_renderer.cpp` render the ring, HUD, logs, and title/victory screens.
- `include/game/input_reader.hpp` and `src/game/input_reader.cpp` handle keyboard polling and raw terminal input.

### AI and progression

- `include/game/ai_agent.hpp` and `src/game/ai_agent.cpp` implement the enemy decision-making and learning state.
- `include/game/pattern_model.hpp` and `src/game/pattern_model.cpp` track player action patterns.
- `include/game/player_profile.hpp` and `src/game/player_profile.cpp` store player behavior statistics.

### Persistence and simulation

- `include/game/save_game.hpp` and `src/game/save_game.cpp` serialize and restore game state.
- `include/game/combat_engine.hpp` and `src/game/combat_engine.cpp` keep the lower-level combat logic available.
- `src/game/battle_state.cpp` provides the battle-state implementation details.

### Verification and tooling

- `tests/smoke_tests.cpp` contains the smoke tests.
- `scripts/open_game_terminal.sh` launches the game in a new macOS Terminal window.
- `.gitignore` excludes generated build artifacts and local workspace files.

## Notes

- FTXUI is optional and enabled through `GAME_USE_FTXUI=ON`.
- The ANSI renderer remains the fallback so the game works in plain terminals.
- The design goal is to keep the combat readable, fast, and clearly boxing-oriented.