#pragma once

#include "game/action.hpp"

#include <string>

namespace game {

enum class MotionState {
    Idle,
    Move,
    Dash,
    Jump,
    Attack,
    HeavyAttack,
    Defend,
    Dodge,
    Parry,
    Heal,
    Hit,
    KO
};

std::string_view to_string(MotionState state);

struct Character {
    std::string name{"Fighter"};
    int max_hp{100};
    int hp{100};
    int max_stamina{100};
    int stamina{100};
    int x{0};
    int y{0};
    int prev_x{0};
    int prev_y{0};
    MotionState motion{MotionState::Idle};
    Action last_action{Action::Wait};
    int motion_ticks{0};
    int action_lock_ticks{0};
    int attack_delay_ticks{-1};
    int recovery_ticks{0};
    int dash_ticks{0};
    int jump_ticks{0};
    int invulnerable_ticks{0};
    int hit_flash_ticks{0};
    int ground_y{0};

    void set_motion(MotionState next_motion, int ticks = 1);
    void tick_motion();
    void tick_status();
    void start_attack(MotionState attack_motion, int windup_ticks, int recovery);
    void start_dash(int duration = 2);
    void start_jump(int duration = 3);
    void mark_hit(int duration = 2);
    void reset_motion();
    void clamp_to_bounds(int width, int height);
};

} // namespace game
