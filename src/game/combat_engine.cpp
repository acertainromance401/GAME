#include "game/combat_engine.hpp"

#include <algorithm>
#include <cstdlib>
#include <utility>

namespace game {

int CombatEngine::base_damage_for(Action action) const {
    switch (action) {
    case Action::Attack:
        return 10;
    case Action::HeavyAttack:
        return 18;
    case Action::Parry:
        return 4;
    case Action::Heal:
        return -12;
    default:
        return 0;
    }
}

namespace {

int clamp_value(int value, int minimum, int maximum) {
    return std::max(minimum, std::min(maximum, value));
}

int stamina_cost(Action action) {
    switch (action) {
    case Action::Attack:
        return 10;
    case Action::HeavyAttack:
        return 18;
    case Action::Defend:
        return 6;
    case Action::Dodge:
        return 12;
    case Action::Parry:
        return 8;
    case Action::Retreat:
    case Action::Approach:
        return 5;
    case Action::Dash:
        return 10;
    case Action::Jump:
        return 6;
    case Action::Heal:
        return 0;
    case Action::Wait:
    case Action::Count:
        return 0;
    }

    return 0;
}

bool is_close_range(const BattleState& state) {
    return state.distance <= 1;
}

bool is_mid_range(const BattleState& state) {
    return state.distance <= 2;
}

bool is_far_range(const BattleState& state) {
    return state.distance >= 3;
}

int manhattan_distance(const BattleState& state) {
    return std::abs(state.player.x - state.enemy.x) + std::abs(state.player.y - state.enemy.y);
}
void sync_distance(BattleState& state) {
    state.distance = manhattan_distance(state);
}

void apply_movement(BattleState& state, Character& character, int dx, int dy) {
    character.x = clamp_value(character.x + dx, 0, state.board_width - 1);
    character.y = clamp_value(character.y + dy, 0, state.board_height - 1);
    character.set_motion(MotionState::Move, 1);
}

std::pair<int, int> enemy_step_toward(const BattleState& state) {
    const auto x_delta = state.player.x - state.enemy.x;
    const auto y_delta = state.player.y - state.enemy.y;

    if (std::abs(x_delta) >= std::abs(y_delta)) {
        return {x_delta == 0 ? 0 : (x_delta > 0 ? 1 : -1), 0};
    }

    return {0, y_delta == 0 ? 0 : (y_delta > 0 ? 1 : -1)};
}

std::pair<int, int> enemy_step_away(const BattleState& state) {
    const auto x_delta = state.player.x - state.enemy.x;
    const auto y_delta = state.player.y - state.enemy.y;

    if (std::abs(x_delta) >= std::abs(y_delta)) {
        return {x_delta == 0 ? 1 : (x_delta > 0 ? -1 : 1), 0};
    }

    return {0, y_delta == 0 ? 1 : (y_delta > 0 ? -1 : 1)};
}

std::pair<int, int> enemy_step_strafe(const BattleState& state) {
    if (state.player.x < state.enemy.x) {
        return {0, state.enemy.y > 0 ? -1 : 1};
    }

    return {0, state.enemy.y < state.board_height - 1 ? 1 : -1};
}

} // namespace

CombatResult CombatEngine::resolve_turn(BattleState& state, AIAgent& ai, Action player_action, int player_dx, int player_dy) {
    CombatResult result{};
    result.player_action = player_action;
    result.player_dx = player_dx;
    result.player_dy = player_dy;

    if (player_action == Action::Dodge) {
        player_dx += (state.player.x < state.enemy.x) ? -1 : 1;
        player_dy += (state.player.y < state.enemy.y) ? -1 : 1;
    }

    apply_movement(state, state.player, player_dx, player_dy);
    state.player.last_action = player_action;

    if (player_action == Action::Attack) {
        state.player.set_motion(MotionState::Attack, 1);
    } else if (player_action == Action::HeavyAttack) {
        state.player.set_motion(MotionState::HeavyAttack, 2);
    } else if (player_action == Action::Defend) {
        state.player.set_motion(MotionState::Defend, 1);
    } else if (player_action == Action::Dodge) {
        state.player.set_motion(MotionState::Dodge, 1);
    } else if (player_action == Action::Parry) {
        state.player.set_motion(MotionState::Parry, 1);
    } else if (player_action == Action::Heal) {
        state.player.set_motion(MotionState::Heal, 1);
    }

    sync_distance(state);

    const auto enemy_action = ai.choose_action(state);
    result.enemy_action = enemy_action;

    auto enemy_move = std::pair<int, int>{0, 0};
    if (enemy_action == Action::Approach) {
        enemy_move = enemy_step_toward(state);
    } else if (enemy_action == Action::Retreat) {
        enemy_move = enemy_step_away(state);
    } else if (enemy_action == Action::Dodge) {
        enemy_move = enemy_step_strafe(state);
    }

    result.enemy_dx = enemy_move.first;
    result.enemy_dy = enemy_move.second;

    apply_movement(state, state.enemy, result.enemy_dx, result.enemy_dy);
    state.enemy.last_action = enemy_action;

    if (enemy_action == Action::Attack) {
        state.enemy.set_motion(MotionState::Attack, 1);
    } else if (enemy_action == Action::HeavyAttack) {
        state.enemy.set_motion(MotionState::HeavyAttack, 2);
    } else if (enemy_action == Action::Defend) {
        state.enemy.set_motion(MotionState::Defend, 1);
    } else if (enemy_action == Action::Dodge) {
        state.enemy.set_motion(MotionState::Dodge, 1);
    } else if (enemy_action == Action::Parry) {
        state.enemy.set_motion(MotionState::Parry, 1);
    } else if (enemy_action == Action::Heal) {
        state.enemy.set_motion(MotionState::Heal, 1);
    }

    sync_distance(state);

    state.player.stamina = std::max(0, state.player.stamina - stamina_cost(player_action));
    state.enemy.stamina = std::max(0, state.enemy.stamina - stamina_cost(enemy_action));

    if (player_action == Action::Wait) {
        state.player.stamina = std::min(state.max_stamina, state.player.stamina + 6);
    }
    if (enemy_action == Action::Wait) {
        state.enemy.stamina = std::min(state.max_stamina, state.enemy.stamina + 6);
    }

    if (player_action == Action::Heal) {
        state.player.hp = std::min(state.max_hp, state.player.hp + 12);
    }
    if (enemy_action == Action::Heal) {
        state.enemy.hp = std::min(state.max_hp, state.enemy.hp + 12);
    }

    const auto player_base = base_damage_for(player_action);
    const auto enemy_base = base_damage_for(enemy_action);

    if (player_action == Action::Attack || player_action == Action::HeavyAttack) {
        if (is_close_range(state) && enemy_action != Action::Defend && enemy_action != Action::Dodge && enemy_action != Action::Parry) {
            result.enemy_damage = player_base;
        } else if (enemy_action == Action::Parry && is_close_range(state)) {
            result.player_damage += 4;
        } else if (player_action == Action::HeavyAttack && is_far_range(state)) {
            result.enemy_damage = 0;
        }
    }

    if (enemy_action == Action::Attack || enemy_action == Action::HeavyAttack) {
        if (is_close_range(state) && player_action != Action::Defend && player_action != Action::Dodge && player_action != Action::Parry) {
            result.player_damage = enemy_base;
        } else if (player_action == Action::Parry && is_close_range(state)) {
            result.enemy_damage += 4;
        } else if (enemy_action == Action::HeavyAttack && is_far_range(state)) {
            result.player_damage = 0;
        }
    }

    if (player_action == Action::HeavyAttack && enemy_action == Action::Dodge && is_mid_range(state)) {
        result.enemy_damage = 0;
    }
    if (enemy_action == Action::HeavyAttack && player_action == Action::Dodge && is_mid_range(state)) {
        result.player_damage = 0;
    }

    if (player_action == Action::Defend) {
        result.player_damage = std::max(0, result.player_damage - 4);
    }
    if (enemy_action == Action::Defend) {
        result.enemy_damage = std::max(0, result.enemy_damage - 4);
    }

    if (player_action == Action::Dodge && result.player_damage == 0) {
        state.distance = std::min(4, state.distance + 1);
    }
    if (enemy_action == Action::Dodge && result.enemy_damage == 0) {
        state.distance = std::max(0, state.distance - 1);
    }

    state.enemy.hp = std::max(0, state.enemy.hp - result.enemy_damage);
    state.player.hp = std::max(0, state.player.hp - result.player_damage);

    if (result.player_damage > 0) {
        state.player.set_motion(MotionState::Hit, 1);
    }
    if (result.enemy_damage > 0) {
        state.enemy.set_motion(MotionState::Hit, 1);
    }

    if (state.player.hp <= 0) {
        state.player.set_motion(MotionState::KO, 0);
    }
    if (state.enemy.hp <= 0) {
        state.enemy.set_motion(MotionState::KO, 0);
    }

    if (result.enemy_damage > 0 || result.player_damage > 0) {
        state.combo_count += 1;
    } else {
        state.combo_count = 0;
    }

    state.elapsed_turns += 1;
    state.cooldown_turns = std::max(0, state.cooldown_turns - 1);

    state.player.tick_motion();
    state.enemy.tick_motion();

    ai.observe_player_action(player_action);
    return result;
}

} // namespace game
