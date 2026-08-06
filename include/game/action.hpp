#pragma once

#include <array>
#include <cstddef>
#include <string_view>

namespace game {

enum class Action : std::size_t {
    Attack = 0,
    HeavyAttack,
    Defend,
    Dodge,
    Parry,
    Retreat,
    Approach,
    Heal,
    Dash,
    Jump,
    Wait,
    Count
};

constexpr std::size_t action_count() {
    return static_cast<std::size_t>(Action::Count);
}

std::string_view to_string(Action action);
Action action_from_index(std::size_t index);

} // namespace game