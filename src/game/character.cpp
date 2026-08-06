#include "game/character.hpp"

#include <algorithm>

namespace game {

std::string_view to_string(MotionState state) {
    switch (state) {
    case MotionState::Idle:
        return "Idle";
    case MotionState::Move:
        return "Move";
    case MotionState::Dash:
        return "Dash";
    case MotionState::Jump:
        return "Jump";
    case MotionState::Attack:
        return "Attack";
    case MotionState::HeavyAttack:
        return "HeavyAttack";
    case MotionState::Defend:
        return "Defend";
    case MotionState::Dodge:
        return "Dodge";
    case MotionState::Parry:
        return "Parry";
    case MotionState::Heal:
        return "Heal";
    case MotionState::Hit:
        return "Hit";
    case MotionState::KO:
        return "KO";
    }

    return "Unknown";
}

void Character::set_motion(MotionState next_motion, int ticks) {
    motion = next_motion;
    motion_ticks = std::max(0, ticks);
}

void Character::tick_motion() {
    if (motion_ticks > 0) {
        --motion_ticks;
        if (motion_ticks == 0 && motion != MotionState::KO) {
            motion = MotionState::Idle;
        }
    }
}

void Character::tick_status() {
    if (action_lock_ticks > 0) {
        --action_lock_ticks;
    }

    if (attack_delay_ticks > 0) {
        --attack_delay_ticks;
    }

    if (recovery_ticks > 0) {
        --recovery_ticks;
    }

    if (dash_ticks > 0) {
        --dash_ticks;
    }

    if (jump_ticks > 0) {
        --jump_ticks;
        if (jump_ticks == 0 && y != ground_y) {
            y = ground_y;
        }
    }

    if (invulnerable_ticks > 0) {
        --invulnerable_ticks;
    }

    if (hit_flash_ticks > 0) {
        --hit_flash_ticks;
    }
}

void Character::start_attack(MotionState attack_motion, int windup_ticks, int recovery) {
    motion = attack_motion;
    motion_ticks = std::max(1, windup_ticks + recovery);
    action_lock_ticks = std::max(1, windup_ticks + recovery);
    attack_delay_ticks = std::max(0, windup_ticks);
    recovery_ticks = std::max(0, recovery);
}

void Character::start_dash(int duration) {
    motion = MotionState::Dash;
    motion_ticks = std::max(1, duration);
    action_lock_ticks = std::max(1, duration);
    dash_ticks = std::max(1, duration);
    invulnerable_ticks = std::max(1, duration);
}

void Character::start_jump(int duration) {
    if (jump_ticks == 0) {
        ground_y = y;
        y = std::max(0, y - 1);
    }

    motion = MotionState::Jump;
    motion_ticks = std::max(1, duration);
    action_lock_ticks = std::max(1, duration);
    jump_ticks = std::max(1, duration);
    invulnerable_ticks = std::max(invulnerable_ticks, duration - 1);
}

void Character::mark_hit(int duration) {
    hit_flash_ticks = std::max(hit_flash_ticks, duration);
}

void Character::reset_motion() {
    motion = MotionState::Idle;
    motion_ticks = 0;
    prev_x = x;
    prev_y = y;
    action_lock_ticks = 0;
    attack_delay_ticks = -1;
    recovery_ticks = 0;
    dash_ticks = 0;
    jump_ticks = 0;
    invulnerable_ticks = 0;
    hit_flash_ticks = 0;
}

void Character::clamp_to_bounds(int width, int height) {
    x = std::clamp(x, 0, std::max(0, width - 1));
    y = std::clamp(y, 0, std::max(0, height - 1));
}

} // namespace game
