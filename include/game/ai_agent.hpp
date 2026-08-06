#pragma once

#include "game/action.hpp"
#include "game/battle_state.hpp"
#include "game/pattern_model.hpp"

#include <array>
#include <cstddef>
#include <optional>
#include <string>
#include <unordered_map>

namespace game {

struct AIAnalytics {
    std::size_t decisions_made{0};
    std::size_t predictions_made{0};
    std::size_t correct_predictions{0};
};

class AIAgent {
public:
    void observe_player_action(Action action);
    void reset();
    void restore_analytics(std::size_t decisions_made, std::size_t predictions_made, std::size_t correct_predictions);
    void record_transition(const BattleState& previous_state, Action action, const BattleState& next_state, double reward);
    [[nodiscard]] Action choose_action(const BattleState& state);
    [[nodiscard]] const PatternModel& pattern_model() const;
    [[nodiscard]] AIAnalytics analytics() const;
    [[nodiscard]] double prediction_accuracy() const;
    [[nodiscard]] std::size_t learning_updates() const;
    [[nodiscard]] const std::unordered_map<std::string, std::array<double, action_count()>>& q_table() const;
    void restore_learning(std::size_t learning_updates, std::unordered_map<std::string, std::array<double, action_count()>> q_table);

private:
    void note_prediction(std::optional<Action> predicted_action) const;
    [[nodiscard]] static std::string encode_state(const BattleState& state);
    [[nodiscard]] std::array<double, action_count()> values_for_state(const BattleState& state) const;
    [[nodiscard]] Action choose_exploratory_action(const BattleState& state, const std::array<double, action_count()>& values) const;
    void apply_q_update(const std::string& state_key, Action action, double reward, const std::string& next_state_key, bool terminal);

    PatternModel pattern_model_;
    mutable std::optional<Action> last_predicted_player_action_{};
    mutable AIAnalytics analytics_{};
    mutable std::size_t learning_updates_{0};
    std::unordered_map<std::string, std::array<double, action_count()>> q_table_{};
};

} // namespace game