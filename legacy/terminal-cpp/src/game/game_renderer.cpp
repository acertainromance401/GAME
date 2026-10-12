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
    return (state.elapsed_turns / 3 + character.motion_ticks / 2 + character.x + character.y) % 4;
}

enum class FacingOctant {
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest
};

FacingOctant facing_octant_from_delta(int dx, int dy) {
    const auto abs_dx = std::abs(dx);
    const auto abs_dy = std::abs(dy);

    if (abs_dx == 0 && abs_dy == 0) {
        return FacingOctant::East;
    }

    if (abs_dx >= abs_dy * 2) {
        return dx >= 0 ? FacingOctant::East : FacingOctant::West;
    }

    if (abs_dy >= abs_dx * 2) {
        return dy >= 0 ? FacingOctant::South : FacingOctant::North;
    }

    if (dx >= 0 && dy < 0) {
        return FacingOctant::NorthEast;
    }
    if (dx >= 0 && dy >= 0) {
        return FacingOctant::SouthEast;
    }
    if (dx < 0 && dy >= 0) {
        return FacingOctant::SouthWest;
    }
    return FacingOctant::NorthWest;
}

std::array<std::string, 3> pose_for_octant(FacingOctant octant) {
    switch (octant) {
    case FacingOctant::North:
        return {"  O  ", " /|\\ ", " / \\ "};
    case FacingOctant::NorthEast:
        return {"  O> ", " /|> ", " / > "};
    case FacingOctant::East:
        return {"  O> ", " /|> ", "  >  "};
    case FacingOctant::SouthEast:
        return {"  O> ", " \\|> ", "  \\> "};
    case FacingOctant::South:
        return {"  O  ", " \\|/ ", " / \\ "};
    case FacingOctant::SouthWest:
        return {" <O  ", " <|\\ ", " < \\ "};
    case FacingOctant::West:
        return {" <O  ", " <|\\ ", "  <  "};
    case FacingOctant::NorthWest:
        return {" <O  ", " <|/ ", " < / "};
    }

    return {"  O  ", " /|\\ ", " / \\ "};
}

std::array<std::string, 3> attack_pose_for_octant(FacingOctant octant, int punch_frame) {
    switch (octant) {
    case FacingOctant::North:
        if (punch_frame == 1) return {"  O  ", " /|^ ", " / \\ "};
        return {"  O  ", " /|\\ ", " / \\ "};
    case FacingOctant::NorthEast:
        if (punch_frame == 1) return {"  O> ", " /=> ", " / > "};
        return {"  O> ", " /|> ", " / > "};
    case FacingOctant::East:
        if (punch_frame == 1) return {"  O> ", " /=> ", "  >  "};
        return {"  O> ", " /|> ", "  >  "};
    case FacingOctant::SouthEast:
        if (punch_frame == 1) return {"  O> ", " \\=>", "  \\> "};
        return {"  O> ", " \\|> ", "  \\> "};
    case FacingOctant::South:
        if (punch_frame == 1) return {"  O  ", " \\|v ", " / \\ "};
        return {"  O  ", " \\|/ ", " / \\ "};
    case FacingOctant::SouthWest:
        if (punch_frame == 1) return {" <O  ", " <== ", " < \\ "};
        return {" <O  ", " <|\\ ", " < \\ "};
    case FacingOctant::West:
        if (punch_frame == 1) return {" <O  ", " <== ", "  <  "};
        return {" <O  ", " <|\\ ", "  <  "};
    case FacingOctant::NorthWest:
        if (punch_frame == 1) return {" <O  ", " <== ", " < / "};
        return {" <O  ", " <|/ ", " < / "};
    }

    return {"  O  ", " /|\\ ", " / \\ "};
}

std::array<std::string, 3> defend_pose_for_octant(FacingOctant octant, bool blink) {
    switch (octant) {
    case FacingOctant::North:
    case FacingOctant::South:
        return {blink ? "  O  " : "  o  ", " /[|]\\", " / \\ "};
    case FacingOctant::NorthEast:
    case FacingOctant::East:
    case FacingOctant::SouthEast:
        return {blink ? "  O> " : "  o> ", " /[|]>", "  >  "};
    case FacingOctant::NorthWest:
    case FacingOctant::West:
    case FacingOctant::SouthWest:
        return {blink ? " <O  " : " <o  ", "<[|]\\ ", "  <  "};
    }

    return {blink ? "  O  " : "  o  ", " /[|]\\", " / \\ "};
}

std::array<std::string, 3> dodge_pose_for_octant(FacingOctant octant, bool blink) {
    switch (octant) {
    case FacingOctant::North:
        return {blink ? "  o  " : " _o  ", " _/|\\", " _/  "};
    case FacingOctant::NorthEast:
        return {blink ? "  o> " : " _o> ", " _/|> ", " _/ > "};
    case FacingOctant::East:
        return {blink ? "  o> " : " _o> ", " _/|> ", "  >  "};
    case FacingOctant::SouthEast:
        return {blink ? "  o> " : "  o> ", " /|>_", "  _> "};
    case FacingOctant::South:
        return {blink ? "  o  " : "  o  ", " \\|/ ", " _/  "};
    case FacingOctant::SouthWest:
        return {blink ? " <o  " : " <o_ ", " <|\\_", " <_/ "};
    case FacingOctant::West:
        return {blink ? " <o  " : " <o_ ", " <|\\_", "  <  "};
    case FacingOctant::NorthWest:
        return {blink ? " <o  " : " <o  ", " <|/ ", " < / "};
    }

    return {blink ? "  o  " : " _o  ", " _/|\\", " _/  "};
}

std::array<std::string, 3> character_sprite(const BattleState& state, const Character& character, int target_x, int target_y) {
    const auto phase = animation_phase(state, character);
    const auto blink = phase % 2 == 0;
    const auto punch_frame = (state.elapsed_turns + character.motion_ticks) % 3;
    const auto facing = facing_octant_from_delta(target_x - character.x, target_y - character.y);

    if (character.hp <= 0) {
        return {"  x  ", " /|\\ ", " / \\ "};
    }

    if (character.hit_flash_ticks > 0) {
        return {blink ? "  !  " : "  *  ", blink ? " /X\\ " : " -X\\ ", blink ? " / \\ " : " / x "};
    } else if (character.jump_ticks > 0) {
        return {blink ? "  O  " : "  o  ", blink ? " /|\\ " : " _|\\ ", blink ? "  ^  " : " / \\ "};
    } else if (character.dash_ticks > 0) {
        auto sprite = pose_for_octant(facing);
        sprite[1] = facing == FacingOctant::North || facing == FacingOctant::South ? (blink ? " /|\\ " : " _|\\ ") : sprite[1];
        return sprite;
    } else {
        const auto is_punch = character.last_action == Action::Jab || character.last_action == Action::Cross || character.last_action == Action::LeftBody || character.last_action == Action::RightBody || character.last_action == Action::LeftHook || character.last_action == Action::RightHook || character.last_action == Action::LeftUppercut || character.last_action == Action::RightUppercut;
        const auto is_duck = character.last_action == Action::DuckLeft || character.last_action == Action::DuckRight;

        switch (character.motion) {
        case MotionState::Attack:
        case MotionState::Dash:
        case MotionState::Jump:
        case MotionState::HeavyAttack:
            if (character.motion == MotionState::Attack) {
                return attack_pose_for_octant(facing, punch_frame);
            }
            if (character.motion == MotionState::HeavyAttack) {
                auto sprite = attack_pose_for_octant(facing, punch_frame);
                sprite[1][2] = '#';
                return sprite;
            }
            return pose_for_octant(facing);
        case MotionState::Defend:
        case MotionState::Dodge:
            if (character.motion == MotionState::Defend) {
                return defend_pose_for_octant(facing, blink);
            }
            return dodge_pose_for_octant(facing, blink);
        case MotionState::Parry:
            return defend_pose_for_octant(facing, blink);
        case MotionState::Heal:
            return pose_for_octant(facing);
        case MotionState::Move:
            if (is_punch) {
                return attack_pose_for_octant(facing, punch_frame);
            }
            if (is_duck) {
                return dodge_pose_for_octant(facing, blink);
            }
            return pose_for_octant(facing);
        case MotionState::Idle:
            return pose_for_octant(facing);
        case MotionState::Hit:
            return {blink ? "  !  " : "  *  ", blink ? " /X\\ " : " -X\\ ", blink ? " / \\ " : " / x "};
        case MotionState::KO:
            return {"  x  ", " /|\\ ", " / \\ "};
        }
    }

    return pose_for_octant(facing);
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

    const auto draw_sprite = [&](const Character& character, int center_x, int center_y, int target_x, int target_y) {
        const auto sprite = character_sprite(state, character, target_x, target_y);
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
        draw_sprite(state.player, player_x, player_draw_y, state.enemy.x, state.enemy.y);
        draw_sprite(state.enemy, enemy_x, enemy_draw_y, state.player.x, state.player.y);
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
    frame.reserve(16);
    append_line(frame, "=== BOXING ===");
    append_line(frame, "");
    append_line(frame, "Press any key to enter the ring");
    append_line(frame, "");
    append_line(frame, "Controls: arrows/i-j-k-l orbit | up/in = away | down/retreat = in");
    append_line(frame, "          a jab | d cross | w guard | q/e duck | q/e/w+a/d combos | Esc quit");
    append_line(frame, "");
    append_line(frame, "Read your opponent and chase the knockout.");
    append_line(frame, "");
    append_line(frame, view.overlay_message.empty() ? "Ready." : view.overlay_message);
    return frame;
}

std::vector<std::string> build_game_over_frame(const GameView& view) {
    std::vector<std::string> frame;
    frame.reserve(16);
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
    frame.reserve(40);
    append_line(frame, "=== BOXING | Adaptive Ring TUI ===");
    append_line(frame, "");
    append_line(frame, "Ring (You=Boxer, E=Opponent, X=Clinch)");
    for (const auto& row : build_arena_rows(view.state)) {
        append_line(frame, row);
    }
    append_line(frame, "");
    append_line(frame, build_status_line("Boxer", animated_player_hp_, view.state.player.max_hp, view.state.player.hit_flash_ticks > 0) + "  |  Energy " + std::to_string(view.state.player.stamina));
    append_line(frame, build_status_line("Oppnt", animated_enemy_hp_, view.state.enemy.max_hp, view.state.enemy.hit_flash_ticks > 0) + "  |  Energy " + std::to_string(view.state.enemy.stamina));
    append_line(frame, "Round " + std::to_string(view.state.current_round) + "/" + std::to_string(view.state.max_rounds) + "  |  Turns " + std::to_string(view.state.elapsed_turns) + "  |  Combo " + std::to_string(view.state.combo_count));
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
    append_line(frame, "Controls: arrows orbit | up/i away | down/k in | left/j circle | right/l circle");
    append_line(frame, "          a jab | d cross | w guard | q/e duck | v save | b load | t stats | Esc quit");
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
            log_lines.push_back(text("  - " + entry) | color(Color::YellowLight));
        }
    }

    auto boxer_status = text(build_status_line("Boxer", animated_player_hp_, view.state.player.max_hp, view.state.player.hit_flash_ticks > 0) +
                             "  |  Energy " + std::to_string(view.state.player.stamina)) |
                         color(Color::CyanLight);
    auto enemy_status = text(build_status_line("Oppnt", animated_enemy_hp_, view.state.enemy.max_hp, view.state.enemy.hit_flash_ticks > 0) +
                             "  |  Energy " + std::to_string(view.state.enemy.stamina)) |
                        color(Color::RedLight);
    auto round_status = text("Round " + std::to_string(view.state.current_round) + "/" + std::to_string(view.state.max_rounds) +
                             "  |  Turns " + std::to_string(view.state.elapsed_turns) +
                             "  |  Combo " + std::to_string(view.state.combo_count)) |
                        bold | color(Color::GreenLight);

    auto root = vbox({
        text("=== BOXING | Adaptive Ring TUI ===") | bold | color(Color::CyanLight),
        separator(),
        text("Ring (You=Boxer, E=Opponent, X=Clinch)") | bold | color(Color::MagentaLight),
        vbox(std::move(arena_rows)) | center,
        separator(),
        boxer_status,
        enemy_status,
        round_status,
        separator(),
        text("Corner Log") | bold | color(Color::YellowLight),
        vbox(std::move(log_lines)),
        separator(),
        text("Controls: arrows orbit | up/i away | down/k in | left/j circle | right/l circle") | color(Color::BlueLight),
        text("          a jab | d cross | w guard | q/e duck | v save | b load | t stats | Esc quit") | color(Color::BlueLight),
        separator(),
        text("> " + view.prompt),
    }) | border;

    if (view.phase == GamePhase::Title) {
        root = vbox({
            text("=== BOXING ===") | bold | color(Color::CyanLight),
            separator(),
            text("Press any key to enter the ring") | bold | color(Color::YellowLight),
            text("Move, jab, cross, guard, duck.") | color(Color::White),
            text("Read the opponent and chase the knockout."),
        }) | border;
    } else if (view.phase == GamePhase::Victory) {
        root = vbox({
            text("=== KNOCKOUT ===") | bold | color(Color::GreenLight),
            separator(),
            text(view.overlay_message.empty() ? "You scored a knockout." : view.overlay_message) | bold | color(Color::GreenLight),
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
