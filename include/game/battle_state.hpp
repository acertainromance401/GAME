#pragma once

#include "game/character.hpp"

namespace game {

struct BattleState {
    int max_hp{100};
    int max_stamina{100};
    int board_width{31};
    int board_height{11};
    int current_round{1};
    int max_rounds{10};
    int player_respawns{0};
    Character player{"Player", 100, 100, 100, 100, 6, 5, 6, 5, MotionState::Idle, Action::Wait, 0};
    Character enemy{"Enemy", 100, 100, 100, 100, 24, 5, 24, 5, MotionState::Idle, Action::Wait, 0};
    int distance{1};
    int combo_count{0};
    int elapsed_turns{0};
    int cooldown_turns{0};
};

} // namespace game