#include "game/player_profile.hpp"

namespace game {

void PlayerProfile::record_action(Action action) {
    const auto index = static_cast<std::size_t>(action);
    ++action_counts_[index];

    if (previous_action_.has_value()) {
        const auto previous_index = static_cast<std::size_t>(*previous_action_);
        ++transition_counts_[previous_index][index];
    }

    previous_action_ = action;
}

std::size_t PlayerProfile::total_actions() const {
    std::size_t total = 0;
    for (const auto count : action_counts_) {
        total += count;
    }

    return total;
}

std::array<double, action_count()> PlayerProfile::action_probability() const {
    std::array<double, action_count()> probabilities{};
    const auto total = total_actions();

    if (total == 0) {
        return probabilities;
    }

    for (std::size_t index = 0; index < action_count(); ++index) {
        probabilities[index] = static_cast<double>(action_counts_[index]) /
            static_cast<double>(total);
    }

    return probabilities;
}

std::optional<Action> PlayerProfile::most_likely_next(Action previous) const {
    const auto previous_index = static_cast<std::size_t>(previous);
    const auto& row = transition_counts_[previous_index];

    std::size_t best_index = action_count();
    std::size_t best_count = 0;

    for (std::size_t index = 0; index < action_count(); ++index) {
        if (row[index] > best_count) {
            best_count = row[index];
            best_index = index;
        }
    }

    if (best_count == 0 || best_index >= action_count()) {
        return std::nullopt;
    }

    return action_from_index(best_index);
}

const std::array<std::size_t, action_count()>& PlayerProfile::action_counts() const {
    return action_counts_;
}

const std::array<std::array<std::size_t, action_count()>, action_count()>& PlayerProfile::transition_counts() const {
    return transition_counts_;
}

void PlayerProfile::restore(
    const std::array<std::size_t, action_count()>& action_counts,
    const std::array<std::array<std::size_t, action_count()>, action_count()>& transition_counts) {
    action_counts_ = action_counts;
    transition_counts_ = transition_counts;
    previous_action_.reset();
}

} // namespace game