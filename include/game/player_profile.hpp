#pragma once

#include "game/action.hpp"

#include <array>
#include <cstddef>
#include <optional>

namespace game {

class PlayerProfile {
public:
    void record_action(Action action);
    [[nodiscard]] std::size_t total_actions() const;
    [[nodiscard]] std::array<double, action_count()> action_probability() const;
    [[nodiscard]] std::optional<Action> most_likely_next(Action previous) const;
    [[nodiscard]] const std::array<std::size_t, action_count()>& action_counts() const;
    [[nodiscard]] const std::array<std::array<std::size_t, action_count()>, action_count()>& transition_counts() const;
    void restore(
        const std::array<std::size_t, action_count()>& action_counts,
        const std::array<std::array<std::size_t, action_count()>, action_count()>& transition_counts);

private:
    std::array<std::size_t, action_count()> action_counts_{};
    std::array<std::array<std::size_t, action_count()>, action_count()> transition_counts_{};
    std::optional<Action> previous_action_{};
};

} // namespace game