#include "game/game_renderer.hpp"

#include <algorithm>
#include <array>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

#if defined(GAME_HAS_FTXUI)
#include <ftxui/dom/elements.hpp>
#include <ftxui/screen/screen.hpp>
#endif

namespace game {

namespace {

std::string format_probability(double value) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(0) << (value * 100.0) << '%';
    return out.str();
}

std::string build_hp_bar(int current_hp, int max_hp, bool flashing) {
    const auto width = 18;
    const auto safe_max = std::max(1, max_hp);
    const auto clamped_hp = std::clamp(current_hp, 0, safe_max);
    const auto filled = std::clamp((clamped_hp * width + safe_max / 2) / safe_max, 0, width);

    std::string bar;
    bar.reserve(static_cast<std::size_t>(width + 2));
    bar.push_back('[');
    for (int index = 0; index < width; ++index) {
        bar.push_back(index < filled ? (flashing ? '!' : '#') : '.');
    }
    bar.push_back(']');
    return bar;
}

int arena_shake_offset(const BattleState& state) {
    const auto intensity = std::max(state.player.hit_flash_ticks, state.enemy.hit_flash_ticks);
    if (intensity <= 0) {
        return 0;
    }

    return (state.elapsed_turns + intensity) % 3;
}

int animation_phase(const BattleState& state, const Character& character) {
    return (state.elapsed_turns + character.motion_ticks + character.x + character.y) % 4;
}

std::array<std::string, 3> character_sprite(const BattleState& state, const Character& character, bool facing_right) {
    const auto phase = animation_phase(state, character);
    const auto blink = phase % 2 == 0;
    const auto pulse = (state.elapsed_turns + character.motion_ticks) % 2 == 0;

    if (character.hp <= 0) {
        return {"  x  ", " /|\\ ", " / \\ "};
    }

    std::string head = blink ? "  O  " : "  o  ";
    std::string torso = blink ? " /|\\ " : " -|\\ ";
    std::string legs = blink ? " / \\ " : " /   ";

    if (character.hit_flash_ticks > 0) {
        head = blink ? "  !  " : "  *  ";
        torso = blink ? " /X\\ " : " -X\\ ";
        legs = blink ? " / \\ " : " / x ";
    } else if (character.jump_ticks > 0) {
        head = blink ? "  O  " : "  o  ";
        torso = blink ? " /|\\ " : " _|\\ ";
        legs = blink ? "  ^  " : " / \\ ";
    } else if (character.dash_ticks > 0) {
        head = blink ? (facing_right ? "  O> " : " <O  ") : (facing_right ? "  o> " : " <o  ");
        torso = facing_right ? (blink ? " /|> " : " /|= ") : (blink ? " <|\\ " : " =|\\ ");
        legs = blink ? (facing_right ? " / > " : " < > ") : (facing_right ? " / = " : " = = ");
    } else {
        switch (character.motion) {
        case MotionState::Attack:
            head = pulse ? (blink ? "  O  " : "  o  ") : (blink ? "  o  " : "  O  ");
            torso = facing_right ? (pulse ? " /|> " : " /|>>") : (pulse ? " <<|\\ " : " <|\\ ");
            legs = blink ? " / \\ " : " /_  ";
            break;
        case MotionState::Dash:
        case MotionState::Jump:
            break;
        case MotionState::HeavyAttack:
            head = pulse ? (blink ? "  O  " : "  o  ") : (blink ? "  o  " : "  O  ");
            torso = facing_right ? (pulse ? " /#> " : " _/#>") : (pulse ? " <#\\ " : " <#_ ");
            legs = blink ? " / \\ " : " /\\  ";
            break;
        case MotionState::Defend:
            head = blink ? "  O  " : "  o  ";
            torso = blink ? " /[ ]\\" : " /[G]\\";
            legs = blink ? " / \\ " : " / \\ ";
            break;
        case MotionState::Dodge:
            head = facing_right ? (blink ? " _o  " : " _O  ") : (blink ? "  o_ " : "  O_ ");
            torso = facing_right ? (blink ? " _/|\\" : " _/|\\") : (blink ? " /|_ " : " /|_ ");
            legs = blink ? " _/   " : " _/   ";
            break;
        case MotionState::Parry:
            torso = facing_right ? (blink ? " /|*>" : " /|+>") : (blink ? " <*|\\ " : " <+|\\ ");
            legs = blink ? " / \\ " : " / \\ ";
            break;
        case MotionState::Heal:
            torso = blink ? " /|+\\" : " /|\\+";
            legs = blink ? " / \\ " : " / \\ ";
            break;
        case MotionState::Move:
        case MotionState::Idle:
        case MotionState::Hit:
        case MotionState::KO:
            break;
        }
    }

    return {std::move(head), std::move(torso), std::move(legs)};
}

std::vector<std::string> build_arena_rows(const BattleState& state) {
    const auto width = std::max(5, state.board_width);
    const auto height = std::max(5, state.board_height);
    const auto shake = arena_shake_offset(state);
    const auto clamp_x = [width](int value) { return std::clamp(value, 0, width - 1); };
    const auto clamp_y = [height](int value) { return std::clamp(value, 0, height - 1); };

    auto rows = std::vector<std::string>(static_cast<std::size_t>(height), std::string(static_cast<std::size_t>(width), '.'));

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const auto corner = (y == 0 || y == height - 1) && (x == 0 || x == width - 1);
            const auto border = y == 0 || y == height - 1 || x == 0 || x == width - 1;
            const auto rope = y == 1 || y == height - 2;
            if (corner) {
                rows[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)] = '+';
            } else if (border) {
                rows[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)] = (y == 0 || y == height - 1) ? '=' : '|';
            } else if (rope) {
                rows[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)] = '-';
            }
        }
    }

    const auto draw_sprite = [&](const Character& character, int center_x, int center_y, bool facing_right) {
        const auto sprite = character_sprite(state, character, facing_right);
        const auto top = center_y - 1;
        for (std::size_t line = 0; line < sprite.size(); ++line) {
            const auto row_index = top + static_cast<int>(line);
            if (row_index < 0 || row_index >= static_cast<int>(rows.size())) {
                continue;
            }

            const auto& sprite_line = sprite[line];
            for (std::size_t column = 0; column < sprite_line.size(); ++column) {
                const auto x = center_x - static_cast<int>(sprite_line.size() / 2) + static_cast<int>(column);
                if (x < 0 || x >= static_cast<int>(rows[static_cast<std::size_t>(row_index)].size())) {
                    continue;
                }
                const auto glyph = sprite_line[column];
                if (glyph != ' ') {
                    rows[static_cast<std::size_t>(row_index)][static_cast<std::size_t>(x)] = glyph;
                }
            }
        }
    };

    const auto player_x = clamp_x(state.player.x);
    const auto enemy_x = clamp_x(state.enemy.x);
    const auto player_draw_y = clamp_y(state.player.y - (state.player.jump_ticks > 0 ? 1 : 0));
    const auto enemy_draw_y = clamp_y(state.enemy.y - (state.enemy.jump_ticks > 0 ? 1 : 0));
    const auto draw_trails = [](const Character& character) {
        return character.dash_ticks > 0 || character.jump_ticks > 0 || character.hit_flash_ticks > 0;
    };

    if (player_x == enemy_x && player_draw_y == enemy_draw_y) {
        rows[static_cast<std::size_t>(player_draw_y)][static_cast<std::size_t>(player_x)] = 'X';
    } else {
        draw_sprite(state.player, player_x, player_draw_y, state.player.x <= state.enemy.x);
        draw_sprite(state.enemy, enemy_x, enemy_draw_y, state.enemy.x < state.player.x);
    }

    const auto add_trail = [&](const Character& character, char trail_char) {
        if (!draw_trails(character) || character.prev_x == character.x) {
            return;
        }

        const auto trail_y = clamp_y(character.prev_y - (character.jump_ticks > 0 ? 1 : 0));
        const auto trail_x = clamp_x(character.prev_x);
        if (rows[static_cast<std::size_t>(trail_y)][static_cast<std::size_t>(trail_x)] == '.') {
            rows[static_cast<std::size_t>(trail_y)][static_cast<std::size_t>(trail_x)] = trail_char;
        }
    };

    add_trail(state.player, ':');
    add_trail(state.enemy, ';');

    for (auto& row : rows) {
        row.insert(0, static_cast<std::size_t>(shake), ' ');
        row.insert(0, "  ");
    }

    return rows;
}

void append_line(std::vector<std::string>& frame, std::string line) {
    frame.push_back(std::move(line));
}

std::string build_status_line(const std::string& label, int current_hp, int max_hp, bool flashing) {
    return label + " HP " + build_hp_bar(current_hp, max_hp, flashing) + " " + std::to_string(std::max(0, current_hp)) + "/" + std::to_string(std::max(1, max_hp));
}

std::vector<std::string> build_title_frame(const GameView& view) {
    std::vector<std::string> frame;
    frame.reserve(24);
    append_line(frame, "=== BOXING ===");
    append_line(frame, "");
    append_line(frame, "Round-based boxing game");
    append_line(frame, "");
    append_line(frame, "Press any key to enter the ring");
    append_line(frame, "");
    append_line(frame, "Controls:");
    append_line(frame, "  Arrow keys or i/j/k/l = Footwork");
    append_line(frame, "  a = Jab   s = Cross   d = Guard");
    append_line(frame, "  space = Slip   f = Block");
    append_line(frame, "  z = Step Back   o = Step In   x = Duck");
    append_line(frame, "  h = Recover   v = Save   b = Load");
    append_line(frame, "");
    append_line(frame, "Read your opponent and chase the knockout.");
    append_line(frame, "");
    append_line(frame, view.overlay_message.empty() ? "Ready." : view.overlay_message);
    return frame;
}

std::vector<std::string> build_game_over_frame(const GameView& view) {
    std::vector<std::string> frame;
    frame.reserve(24);
    append_line(frame, "=== KNOCKOUT ===");
    append_line(frame, "");
    append_line(frame, view.overlay_message.empty() ? "You scored a knockout." : view.overlay_message);
    append_line(frame, "");
    append_line(frame, "Press n to start a new fight");
    append_line(frame, "Press q to quit");
    append_line(frame, "");
    append_line(frame, "Final Score:");
    append_line(frame, "  Rounds  : " + std::to_string(std::max(0, view.state.current_round)) + "/" + std::to_string(std::max(1, view.state.max_rounds)));
    append_line(frame, "  Respawns: " + std::to_string(std::max(0, view.state.player_respawns)));
    append_line(frame, "  Boxer   : " + std::to_string(std::max(0, view.state.player.hp)));
    append_line(frame, "  Oppnt   : " + std::to_string(std::max(0, view.state.enemy.hp)));
    return frame;
}

} // namespace

GameRenderer::GameRenderer() {
    std::cout << "\033[?25l";
}

GameRenderer::~GameRenderer() {
    std::cout << "\033[?25h\033[0m\n";
}

std::vector<std::string> GameRenderer::build_frame(const GameView& view) const {
    if (view.phase == GamePhase::Title) {
        return build_title_frame(view);
    }
    if (view.phase == GamePhase::Victory) {
        return build_game_over_frame(view);
    }

    std::vector<std::string> frame;
    frame.reserve(80);
    append_line(frame, "=== BOXING | Adaptive Ring TUI ===");
    append_line(frame, "");
    append_line(frame, "Ring (You=Boxer, E=Opponent, X=Clinch)");
    for (const auto& row : build_arena_rows(view.state)) {
        append_line(frame, row);
    }
    append_line(frame, "");
    append_line(frame, build_status_line("Boxer", animated_player_hp_, view.state.player.max_hp, view.state.player.hit_flash_ticks > 0));
    append_line(frame, build_status_line("Oppnt", animated_enemy_hp_, view.state.enemy.max_hp, view.state.enemy.hit_flash_ticks > 0));
    append_line(frame, "Boxer Energy: " + std::to_string(view.state.player.stamina));
    append_line(frame, "Oppnt Energy: " + std::to_string(view.state.enemy.stamina));
    append_line(frame, "Round      : " + std::to_string(view.state.current_round) + "/" + std::to_string(view.state.max_rounds));
    append_line(frame, "Knockdowns : " + std::to_string(view.state.player_respawns));
    append_line(frame, "Boxer Pos  : (" + std::to_string(view.state.player.x) + ", " + std::to_string(view.state.player.y) + ")");
    append_line(frame, "Oppnt Pos  : (" + std::to_string(view.state.enemy.x) + ", " + std::to_string(view.state.enemy.y) + ")");
    append_line(frame, "Boxer Motion: " + std::string(to_string(view.state.player.motion)));
    append_line(frame, "Oppnt Motion : " + std::string(to_string(view.state.enemy.motion)));
    append_line(frame, "Distance    : " + std::to_string(view.state.distance));
    append_line(frame, "Turns       : " + std::to_string(view.state.elapsed_turns));
    append_line(frame, "Combo       : " + std::to_string(view.state.combo_count));
    append_line(frame, "");
    append_line(frame, "Last Boxer  : " + std::string(to_string(view.last_player_action)));
    append_line(frame, "Last Oppnt  : " + std::string(to_string(view.last_enemy_action)));
    append_line(frame, "");
    append_line(frame, "Opponent Read");

    for (std::size_t index = 0; index < action_count(); ++index) {
        frame.push_back("  " + std::string(to_string(action_from_index(index))) + " : " + format_probability(view.player_action_probabilities[index]));
    }

    append_line(frame, "");
    append_line(frame, "Corner Log");
    if (view.log_entries.empty()) {
        append_line(frame, "  (none)");
    } else {
        for (const auto& entry : view.log_entries) {
            append_line(frame, "  - " + entry);
        }
    }

    append_line(frame, "");
    append_line(frame, "Commands");
    append_line(frame, "  a=Jab  s=Cross  d=Guard  space=Slip  f=Block");
    append_line(frame, "  arrow keys=i/j/k/l=Footwork  z=Step Back  o=Step In  x=Duck");
    append_line(frame, "  h=Recover  v=Save  b=Load  n=New Fight  t=Stats  q=Quit");
    append_line(frame, "");
    append_line(frame, "> " + view.prompt);
    return frame;
}

void GameRenderer::present_frame(const std::vector<std::string>& frame) const {
    std::cout << "\033[H";

    const auto line_count = std::max(previous_frame_.size(), frame.size());
    for (std::size_t index = 0; index < line_count; ++index) {
        const auto has_current = index < frame.size();
        const auto has_previous = index < previous_frame_.size();
        if (has_current) {
            std::cout << frame[index];
        }
        if (has_previous && previous_frame_[index].size() > (has_current ? frame[index].size() : 0)) {
            std::cout << std::string(previous_frame_[index].size() - (has_current ? frame[index].size() : 0), ' ');
        }
        if (index + 1 < line_count) {
            std::cout << '\n';
        }
    }

    std::cout << "\033[J";

    previous_frame_ = frame;
    initialized_ = true;
    std::cout << std::flush;
}

void GameRenderer::render(const GameView& view) const {
    sync_animated_hp(view);
#if defined(GAME_HAS_FTXUI)
    using namespace ftxui;

    Elements arena_rows;
    for (const auto& row : build_arena_rows(view.state)) {
        arena_rows.push_back(text(row));
    }

    Elements log_lines;
    if (view.log_entries.empty()) {
        log_lines.push_back(text("  (none)"));
    } else {
        for (const auto& entry : view.log_entries) {
            log_lines.push_back(text("  - " + entry));
        }
    }

    Elements probability_rows;
    for (std::size_t index = 0; index < action_count(); ++index) {
        std::ostringstream line;
        line << "  " << to_string(action_from_index(index)) << " : " << format_probability(view.player_action_probabilities[index]);
        probability_rows.push_back(text(line.str()));
    }

    auto root = vbox({
        text("=== BOXING | Adaptive Ring TUI ===") | bold,
        separator(),
        text("Ring (You=Boxer, E=Opponent, X=Clinch)") | bold,
        vbox(std::move(arena_rows)) | center,
        separator(),
        text(build_status_line("Boxer", animated_player_hp_, view.state.player.max_hp, view.state.player.hit_flash_ticks > 0)),
        text(build_status_line("Oppnt", animated_enemy_hp_, view.state.enemy.max_hp, view.state.enemy.hit_flash_ticks > 0)),
        hbox({
            text("Boxer Energy: " + std::to_string(view.state.player.stamina)),
            text("  Oppnt Energy: " + std::to_string(view.state.enemy.stamina)),
        }),
        hbox({
            text("Round      : " + std::to_string(view.state.current_round) + "/" + std::to_string(view.state.max_rounds)),
            text("  Turns       : " + std::to_string(view.state.elapsed_turns)),
            text("  Combo       : " + std::to_string(view.state.combo_count)),
        }),
        separator(),
        hbox({
            text(std::string("Boxer Motion: ") + std::string(to_string(view.state.player.motion))),
            text(std::string("  Oppnt Motion : ") + std::string(to_string(view.state.enemy.motion))),
        }),
        hbox({
            text(std::string("Boxer Pos   : (") + std::to_string(view.state.player.x) + ", " + std::to_string(view.state.player.y) + ")"),
            text(std::string("  Oppnt Pos   : (") + std::to_string(view.state.enemy.x) + ", " + std::to_string(view.state.enemy.y) + ")"),
        }),
        separator(),
        text("Last Boxer  : " + std::string(to_string(view.last_player_action))),
        text("Last Oppnt  : " + std::string(to_string(view.last_enemy_action))),
        separator(),
        text("Opponent Read") | bold,
        vbox(std::move(probability_rows)),
        separator(),
        text("Corner Log") | bold,
        vbox(std::move(log_lines)),
        separator(),
        text("Commands") | bold,
        text("a=Jab  s=Cross  d=Guard  space=Slip  f=Block"),
        text("arrow keys=i/j/k/l=Footwork  z=Step Back  o=Step In  x=Duck  h=Recover  v=Save  b=Load  n=New Fight  t=Stats  q=Quit"),
        separator(),
        text("> " + view.prompt),
    }) | border;

    if (view.phase == GamePhase::Title) {
        root = vbox({
            text("=== BOXING ===") | bold,
            separator(),
            text("Press any key to enter the ring") | bold,
            text("Footwork is instant. Punches, guard, slip, and duck are all live."),
            text("Read the opponent and chase the knockout."),
        }) | border;
    } else if (view.phase == GamePhase::Victory) {
        root = vbox({
            text("=== KNOCKOUT ===") | bold,
            separator(),
            text(view.overlay_message.empty() ? "You scored a knockout." : view.overlay_message) | bold,
            text("Press n for a new fight or q to quit."),
        }) | border;
    }

    auto screen = Screen::Create(Dimension::Fit(root), Dimension::Fit(root));
    Render(screen, root);
    std::cout << screen.ToString() << std::flush;
#else
    present_frame(build_frame(view));
#endif
}

void GameRenderer::sync_animated_hp(const GameView& view) const {
    const auto animate_step = [](int& current, int target) {
        if (current < target) {
            current = std::min(current + 2, target);
        } else if (current > target) {
            current = std::max(current - 2, target);
        }
    };

    animate_step(animated_player_hp_, view.state.player.hp);
    animate_step(animated_enemy_hp_, view.state.enemy.hp);
}

} // namespace game
