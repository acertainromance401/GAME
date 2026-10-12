#pragma once

#include "game/action.hpp"
#include "game/ai_agent.hpp"
#include "game/battle_state.hpp"

namespace game {

struct CombatResult {
    Action player_action{Action::Wait};
    Action enemy_action{Action::Wait};
    int player_damage{0};
    int enemy_damage{0};
    int player_dx{0};
    int player_dy{0};
    int enemy_dx{0};
    int enemy_dy{0};
};

class CombatEngine {
public:
    CombatResult resolve_turn(BattleState& state, AIAgent& ai, Action player_action, int player_dx = 0, int player_dy = 0);

private:
    int base_damage_for(Action action) const;
};

} // namespace game
