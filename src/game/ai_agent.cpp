#include "game/ai_agent.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <random>
#include <utility>
#include <sstream>

namespace game {

namespace {

constexpr double kLearningRate = 0.18;
constexpr double kDiscountFactor = 0.82;
constexpr double kExplorationRate = 0.14;

std::size_t hp_bucket(const Character& character) {
    const auto safe_max = std::max(1, character.max_hp);
    const auto percent = (std::clamp(character.hp, 0, safe_max) * 100) / safe_max;
    return static_cast<std::size_t>(std::clamp(percent / 20, 0, 5));
}

std::size_t distance_bucket(const BattleState& state) {
    return static_cast<std::size_t>(std::clamp(state.distance, 0, 5));
}

std::size_t round_bucket(const BattleState& state) {
    if (state.current_round <= 3) {
        return 0;
    }
    if (state.current_round <= 6) {
        return 1;
    }
    return 2;
}

Action best_action_from_values(const std::array<double, action_count()>& values) {
    auto best_index = std::size_t{0};
    auto best_value = values[0];
    for (std::size_t index = 1; index < action_count(); ++index) {
        if (values[index] > best_value) {
            best_value = values[index];
            best_index = index;
        }
    }

    return action_from_index(best_index);
}

double max_q_value(const std::array<double, action_count()>& values) {
    return *std::max_element(values.begin(), values.end());
}

bool has_learning_signal(const std::array<double, action_count()>& values) {
    return std::any_of(values.begin(), values.end(), [](double value) {
        return std::abs(value) > 1e-6;
    });
}

} // namespace

void AIAgent::observe_player_action(Action action) {
    pattern_model_.observe(action);

    if (last_predicted_player_action_.has_value()) {
        ++analytics_.predictions_made;
        if (*last_predicted_player_action_ == action) {
            ++analytics_.correct_predictions;
        }
        last_predicted_player_action_.reset();
    }
}

void AIAgent::reset() {
    pattern_model_ = PatternModel{};
    last_predicted_player_action_.reset();
    analytics_ = AIAnalytics{};
    q_table_.clear();
    learning_updates_ = 0;
}

void AIAgent::restore_analytics(std::size_t decisions_made, std::size_t predictions_made, std::size_t correct_predictions) {
    analytics_.decisions_made = decisions_made;
    analytics_.predictions_made = predictions_made;
    analytics_.correct_predictions = correct_predictions;
    last_predicted_player_action_.reset();
}

void AIAgent::restore_learning(std::size_t learning_updates, std::unordered_map<std::string, std::array<double, action_count()>> q_table) {
    learning_updates_ = learning_updates;
    q_table_ = std::move(q_table);
}

std::size_t AIAgent::learning_updates() const {
    return learning_updates_;
}

const std::unordered_map<std::string, std::array<double, action_count()>>& AIAgent::q_table() const {
    return q_table_;
}

std::string AIAgent::encode_state(const BattleState& state) {
    std::ostringstream out;
    out << distance_bucket(state) << ':'
        << hp_bucket(state.player) << ':'
        << hp_bucket(state.enemy) << ':'
        << round_bucket(state);
    return out.str();
}

std::array<double, action_count()> AIAgent::values_for_state(const BattleState& state) const {
    const auto key = encode_state(state);
    const auto found = q_table_.find(key);
    if (found != q_table_.end()) {
        return found->second;
    }

    std::array<double, action_count()> values{};
    values.fill(0.0);
    return values;
}

Action AIAgent::choose_exploratory_action(const BattleState& state, const std::array<double, action_count()>& values) const {
    static thread_local std::mt19937 generator{std::random_device{}()};
    std::uniform_real_distribution<double> probability(0.0, 1.0);

    const auto predicted = pattern_model_.predict_next();
    const auto round = std::max(1, state.current_round);

    if (probability(generator) < kExplorationRate) {
        if (state.distance > 2) {
            return Action::Approach;
        }
        return best_action_from_values(values);
    }

    if (has_learning_signal(values)) {
        return best_action_from_values(values);
    }

    if (predicted.has_value()) {
        switch (*predicted) {
        case Action::Attack:
            return round >= 5 ? Action::Dodge : Action::Defend;
        case Action::HeavyAttack:
            return round >= 6 ? Action::Parry : Action::Defend;
        case Action::Dash:
            return round >= 5 ? Action::Attack : Action::Jump;
        case Action::Jump:
            return round >= 6 ? Action::Attack : Action::Dash;
        case Action::Defend:
            return Action::Retreat;
        case Action::Dodge:
            return round >= 8 ? Action::HeavyAttack : Action::Attack;
        case Action::Heal:
            return Action::Attack;
        case Action::Parry:
            return round >= 5 ? Action::Dash : Action::Wait;
        case Action::Retreat:
            return Action::Approach;
        case Action::Approach:
            return round >= 6 ? Action::HeavyAttack : Action::Attack;
        case Action::Wait:
            return round >= 3 ? Action::Dash : Action::Approach;
        case Action::Count:
            break;
        }
    }

    return state.distance > 2 ? Action::Approach : best_action_from_values(values);
}

Action AIAgent::choose_action(const BattleState& state) {
    const auto values = values_for_state(state);
    const auto action = choose_exploratory_action(state, values);
    ++analytics_.decisions_made;
    note_prediction(pattern_model_.predict_next());
    return action;
}

void AIAgent::apply_q_update(const std::string& state_key, Action action, double reward, const std::string& next_state_key, bool terminal) {
    auto& current_row = q_table_[state_key];
    auto& next_row = q_table_[next_state_key];

    const auto action_index = static_cast<std::size_t>(action);
    const auto current_value = current_row[action_index];
    const auto next_value = terminal ? 0.0 : max_q_value(next_row);
    const auto target = reward + kDiscountFactor * next_value;

    current_row[action_index] = current_value + kLearningRate * (target - current_value);
    ++learning_updates_;
}

void AIAgent::record_transition(const BattleState& previous_state, Action action, const BattleState& next_state, double reward) {
    const auto previous_key = encode_state(previous_state);
    const auto next_key = encode_state(next_state);
    const auto terminal = next_state.enemy.hp <= 0 || next_state.player.hp <= 0;
    apply_q_update(previous_key, action, reward, next_key, terminal);
}

void AIAgent::note_prediction(std::optional<Action> predicted_action) const {
    last_predicted_player_action_ = predicted_action;
}

const PatternModel& AIAgent::pattern_model() const {
    return pattern_model_;
}

AIAnalytics AIAgent::analytics() const {
    return analytics_;
}

double AIAgent::prediction_accuracy() const {
    if (analytics_.predictions_made == 0) {
        return 0.0;
    }

    return static_cast<double>(analytics_.correct_predictions) /
        static_cast<double>(analytics_.predictions_made);
}

} // namespace game
