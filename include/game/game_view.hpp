#pragma once

#include "game/action.hpp"
#include "game/battle_state.hpp"

#include <array>
#include <string>
#include <vector>

namespace game {

enum class GamePhase {
    Title,
    Battle,
    Victory
};

struct GameView {
    BattleState state{};
    GamePhase phase{GamePhase::Title};
    Action last_player_action{Action::Wait};
    Action last_enemy_action{Action::Wait};
    std::array<double, action_count()> player_action_probabilities{};
    std::vector<std::string> log_entries{};
    std::string prompt{};
    std::string overlay_message{};
};

} // namespace game
