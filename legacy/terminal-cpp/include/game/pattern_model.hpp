#pragma once

#include "game/action.hpp"

#include <array>
#include <cstddef>
#include <optional>
#include <vector>

namespace game {

class PatternModel {
public:
    void observe(Action action);
    [[nodiscard]] std::size_t size() const;
    [[nodiscard]] std::optional<Action> predict_next() const;
    [[nodiscard]] const std::vector<Action>& history() const;

private:
    std::vector<Action> history_;
    std::array<std::size_t, action_count()> frequency_{};
    std::array<std::array<std::size_t, action_count()>, action_count()> transitions_{};
};

} // namespace game