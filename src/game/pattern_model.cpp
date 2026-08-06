#include "game/pattern_model.hpp"

namespace game {

void PatternModel::observe(Action action) {
    if (!history_.empty()) {
        const auto previous = static_cast<std::size_t>(history_.back());
        const auto current = static_cast<std::size_t>(action);
        ++transitions_[previous][current];
    }

    history_.push_back(action);
    ++frequency_[static_cast<std::size_t>(action)];
}

std::size_t PatternModel::size() const {
    return history_.size();
}

std::optional<Action> PatternModel::predict_next() const {
    if (history_.empty()) {
        return std::nullopt;
    }

    const auto last = static_cast<std::size_t>(history_.back());
    const auto& row = transitions_[last];

    std::size_t best_index = action_count();
    std::size_t best_count = 0;

    for (std::size_t index = 0; index < action_count(); ++index) {
        if (row[index] > best_count) {
            best_count = row[index];
            best_index = index;
        }
    }

    if (best_count == 0 || best_index >= action_count()) {
        std::size_t fallback_index = 0;
        std::size_t fallback_count = 0;

        for (std::size_t index = 0; index < action_count(); ++index) {
            if (frequency_[index] > fallback_count) {
                fallback_count = frequency_[index];
                fallback_index = index;
            }
        }

        if (fallback_count == 0) {
            return std::nullopt;
        }

        return action_from_index(fallback_index);
    }

    return action_from_index(best_index);
}

const std::vector<Action>& PatternModel::history() const {
    return history_;
}

} // namespace game