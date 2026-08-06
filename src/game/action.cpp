#include "game/action.hpp"

namespace game {

std::string_view to_string(Action action) {
    static constexpr std::array<std::string_view, action_count()> names = {
        "Attack",
        "HeavyAttack",
        "Defend",
        "Dodge",
        "Parry",
        "Retreat",
        "Approach",
        "Heal",
        "Dash",
        "Jump",
        "Wait"
    };

    const auto index = static_cast<std::size_t>(action);
    if (index >= names.size()) {
        return "Unknown";
    }

    return names[index];
}

Action action_from_index(std::size_t index) {
    if (index >= action_count()) {
        return Action::Wait;
    }

    return static_cast<Action>(index);
}

} // namespace game