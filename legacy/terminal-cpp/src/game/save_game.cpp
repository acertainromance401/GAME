#include "game/save_game.hpp"

#include <array>
#include <cctype>
#include <fstream>
#include <sstream>
#include <unordered_map>
#include <utility>

namespace game {

namespace {

void write_state(std::ostream& out, const BattleState& state) {
    out << state.player.max_hp << ' '
        << state.player.hp << ' '
        << state.player.max_stamina << ' '
        << state.player.stamina << ' '
        << state.enemy.max_hp << ' '
        << state.enemy.hp << ' '
        << state.enemy.max_stamina << ' '
        << state.enemy.stamina << ' '
        << state.board_width << ' '
        << state.board_height << ' '
        << state.current_round << ' '
        << state.max_rounds << ' '
        << state.player_respawns << ' '
        << state.distance << ' '
        << static_cast<std::size_t>(state.player.motion) << ' '
        << static_cast<std::size_t>(state.player.last_action) << ' '
        << state.player.x << ' '
        << state.player.y << ' '
        << state.player.motion_ticks << ' '
        << state.player.action_lock_ticks << ' '
        << state.player.attack_delay_ticks << ' '
        << state.player.recovery_ticks << ' '
        << state.player.dash_ticks << ' '
        << state.player.jump_ticks << ' '
        << state.player.invulnerable_ticks << ' '
        << state.player.hit_flash_ticks << ' '
        << state.player.ground_y << ' '
        << static_cast<std::size_t>(state.enemy.motion) << ' '
        << static_cast<std::size_t>(state.enemy.last_action) << ' '
        << state.enemy.x << ' '
        << state.enemy.y << ' '
        << state.enemy.motion_ticks << ' '
        << state.enemy.action_lock_ticks << ' '
        << state.enemy.attack_delay_ticks << ' '
        << state.enemy.recovery_ticks << ' '
        << state.enemy.dash_ticks << ' '
        << state.enemy.jump_ticks << ' '
        << state.enemy.invulnerable_ticks << ' '
        << state.enemy.hit_flash_ticks << ' '
        << state.enemy.ground_y << ' '
        << state.combo_count << ' '
        << state.elapsed_turns << ' '
        << state.cooldown_turns << '\n';
}

bool read_state(std::istream& in, BattleState& state) {
    std::size_t player_motion = 0;
    std::size_t player_last_action = 0;
    std::size_t enemy_motion = 0;
    std::size_t enemy_last_action = 0;
    state.current_round = 1;
    state.max_rounds = 10;
    state.player_respawns = 0;

    if (!(in >> state.player.max_hp >> state.player.hp >> state.player.max_stamina >> state.player.stamina
        >> state.enemy.max_hp >> state.enemy.hp >> state.enemy.max_stamina >> state.enemy.stamina
        >> state.board_width >> state.board_height)) {
        return false;
    }

    if (!(in >> state.current_round >> state.max_rounds >> state.player_respawns)) {
        return false;
    }

    return static_cast<bool>(in >> state.distance >> player_motion >> player_last_action
        >> state.player.x >> state.player.y >> state.player.motion_ticks
        >> state.player.action_lock_ticks >> state.player.attack_delay_ticks >> state.player.recovery_ticks
        >> state.player.dash_ticks >> state.player.jump_ticks >> state.player.invulnerable_ticks >> state.player.hit_flash_ticks
        >> state.player.ground_y
        >> enemy_motion >> enemy_last_action >> state.enemy.x >> state.enemy.y >> state.enemy.motion_ticks
        >> state.enemy.action_lock_ticks >> state.enemy.attack_delay_ticks >> state.enemy.recovery_ticks
        >> state.enemy.dash_ticks >> state.enemy.jump_ticks >> state.enemy.invulnerable_ticks >> state.enemy.hit_flash_ticks
        >> state.enemy.ground_y
        >> state.combo_count >> state.elapsed_turns >> state.cooldown_turns)
        && (state.player.motion = static_cast<MotionState>(player_motion), true)
        && (state.player.last_action = action_from_index(player_last_action), true)
        && (state.enemy.motion = static_cast<MotionState>(enemy_motion), true)
        && (state.enemy.last_action = action_from_index(enemy_last_action), true);
}

template <typename ArrayType>
void write_flat_array(std::ostream& out, const ArrayType& values) {
    for (const auto& value : values) {
        out << value << ' ';
    }
    out << '\n';
}

template <typename ArrayType>
bool read_flat_array(std::istream& in, ArrayType& values) {
    for (auto& value : values) {
        if (!(in >> value)) {
            return false;
        }
    }

    return true;
}

void write_q_table(std::ostream& out, const AIAgent& ai_agent) {
    const auto& q_table = ai_agent.q_table();
    out << "AI_RL\n";
    out << ai_agent.learning_updates() << ' ' << q_table.size() << '\n';
    for (const auto& [key, values] : q_table) {
        out << key;
        for (const auto value : values) {
            out << ' ' << value;
        }
        out << '\n';
    }
}

bool read_q_table(std::istream& in, AIAgent& ai_agent) {
    std::size_t learning_updates = 0;
    std::size_t entry_count = 0;
    if (!(in >> learning_updates >> entry_count)) {
        return false;
    }

    std::unordered_map<std::string, std::array<double, action_count()>> q_table;
    for (std::size_t index = 0; index < entry_count; ++index) {
        std::string key;
        if (!(in >> key)) {
            return false;
        }

        std::array<double, action_count()> values{};
        for (auto& value : values) {
            if (!(in >> value)) {
                return false;
            }
        }

        q_table.emplace(std::move(key), values);
    }

    ai_agent.restore_learning(learning_updates, std::move(q_table));
    return true;
}

} // namespace

std::string SaveGame::serialize(const SaveData& data) {
    std::ostringstream out;
    out << "STATE\n";
    write_state(out, data.state);
    out << "PLAYER_PROFILE\n";
    write_flat_array(out, data.player_profile.action_counts());
    for (const auto& row : data.player_profile.transition_counts()) {
        write_flat_array(out, row);
    }
    out << '\n';
    out << "AI_HISTORY\n";
    out << data.ai_agent.pattern_model().size() << '\n';
    for (const auto action : data.ai_agent.pattern_model().history()) {
        out << static_cast<std::size_t>(action) << ' ';
    }
    out << '\n';
    const auto analytics = data.ai_agent.analytics();
    out << "AI_ANALYTICS\n"
        << analytics.decisions_made << ' '
        << analytics.predictions_made << ' '
        << analytics.correct_predictions << '\n';
    write_q_table(out, data.ai_agent);
    return out.str();
}

bool SaveGame::deserialize(const std::string& text, SaveData& data) {
    std::istringstream in(text);
    std::string section;

    if (!(in >> section) || section != "STATE") {
        return false;
    }
    if (!read_state(in, data.state)) {
        return false;
    }

    if (!(in >> section) || section != "PLAYER_PROFILE") {
        return false;
    }

    std::array<std::size_t, action_count()> action_counts{};
    if (!read_flat_array(in, action_counts)) {
        return false;
    }

    std::array<std::array<std::size_t, action_count()>, action_count()> transition_counts{};
    for (auto& row : transition_counts) {
        if (!read_flat_array(in, row)) {
            return false;
        }
    }

    data.player_profile.restore(action_counts, transition_counts);

    if (!(in >> section) || section != "AI_HISTORY") {
        return false;
    }

    std::size_t history_size = 0;
    if (!(in >> history_size)) {
        return false;
    }

    for (std::size_t index = 0; index < history_size; ++index) {
        std::size_t raw_action = 0;
        if (!(in >> raw_action)) {
            return false;
        }
        data.ai_agent.observe_player_action(action_from_index(raw_action));
    }

    if (!(in >> section) || section != "AI_ANALYTICS") {
        return false;
    }

    std::size_t decisions_made = 0;
    std::size_t predictions_made = 0;
    std::size_t correct_predictions = 0;
    if (!(in >> decisions_made >> predictions_made >> correct_predictions)) {
        return false;
    }

    data.ai_agent.restore_analytics(decisions_made, predictions_made, correct_predictions);

    if (!(in >> section)) {
        return true;
    }

    if (section != "AI_RL") {
        return false;
    }

    if (!read_q_table(in, data.ai_agent)) {
        return false;
    }

    return true;
}

bool SaveGame::save(const std::filesystem::path& path, const SaveData& data) const {
    std::ofstream file(path, std::ios::trunc);
    if (!file) {
        return false;
    }

    file << serialize(data);
    return static_cast<bool>(file);
}

bool SaveGame::load(const std::filesystem::path& path, SaveData& data) const {
    std::ifstream file(path);
    if (!file) {
        return false;
    }

    std::ostringstream buffer;
    buffer << file.rdbuf();
    return deserialize(buffer.str(), data);
}

} // namespace game
