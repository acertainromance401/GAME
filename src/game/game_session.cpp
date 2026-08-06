#include "game/game_session.hpp"

#include "game/action.hpp"

#include <chrono>
#include <algorithm>
#include <cctype>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <utility>
#include <sstream>

namespace game {

namespace {

Action parse_combo_action(const std::string& prefix, const std::string& suffix);

std::string boxing_action_label(Action action) {
    switch (action) {
    case Action::Jab:
        return "잽";
    case Action::Cross:
        return "스트레이트";
    case Action::LeftBody:
        return "레프트 바디";
    case Action::RightHook:
        return "라이트 훅";
    case Action::LeftHook:
        return "레프트 훅";
    case Action::RightBody:
        return "라이트 바디";
    case Action::LeftUppercut:
        return "레프트 어퍼컷";
    case Action::RightUppercut:
        return "라이트 어퍼컷";
    case Action::Guard:
        return "가드";
    case Action::DuckLeft:
        return "왼쪽 덕킹";
    case Action::DuckRight:
        return "오른쪽 덕킹";
    case Action::StepBack:
        return "스텝 아웃";
    case Action::StepForward:
        return "스텝 인";
    case Action::Wait:
    case Action::Count:
        return "대기";
    }

    return "대기";
}

Action parse_action(const std::string& command) {
    const auto plus = command.find('+');
    if (plus != std::string::npos) {
        const auto combo = parse_combo_action(command.substr(0, plus), command.substr(plus + 1));
        if (combo != Action::Wait) {
            return combo;
        }
    }

    if (command == "a") return Action::Jab;
    if (command == "d") return Action::Cross;
    if (command == "q+a") return Action::LeftBody;
    if (command == "q+d") return Action::RightHook;
    if (command == "e+a") return Action::LeftHook;
    if (command == "e+d") return Action::RightBody;
    if (command == "w+a") return Action::LeftUppercut;
    if (command == "w+d") return Action::RightUppercut;
    if (command == "w") return Action::Guard;
    if (command == "q") return Action::DuckLeft;
    if (command == "e") return Action::DuckRight;
    if (command == "u") return Action::StepBack;
    if (command == "o") return Action::StepForward;
    if (command == "space" || command == "wait") return Action::Wait;

    return Action::Wait;
}

bool is_combo_prefix(const std::string& key) {
    return key == "q" || key == "e" || key == "w";
}

bool is_combo_suffix(const std::string& key) {
    return key == "a" || key == "d";
}

Action parse_combo_action(const std::string& prefix, const std::string& suffix) {
    if (prefix == "q" && suffix == "a") return Action::LeftBody;
    if (prefix == "q" && suffix == "d") return Action::RightHook;
    if (prefix == "e" && suffix == "a") return Action::LeftHook;
    if (prefix == "e" && suffix == "d") return Action::RightBody;
    if (prefix == "w" && suffix == "a") return Action::LeftUppercut;
    if (prefix == "w" && suffix == "d") return Action::RightUppercut;
    return Action::Wait;
}

int clamp_position(int value, int width) {
    return std::clamp(value, 0, std::max(0, width - 1));
}

void sync_distance(BattleState& state);
bool can_take_damage(const Character& character);

int stamina_cost(Action action) {
    switch (action) {
    case Action::Jab:
        return 7;
    case Action::Cross:
        return 10;
    case Action::LeftBody:
    case Action::RightBody:
        return 10;
    case Action::LeftHook:
    case Action::RightHook:
        return 11;
    case Action::LeftUppercut:
    case Action::RightUppercut:
        return 13;
    case Action::Guard:
        return 6;
    case Action::DuckLeft:
    case Action::DuckRight:
        return 5;
    case Action::StepBack:
    case Action::StepForward:
        return 5;
    case Action::Wait:
    case Action::Count:
        return 0;
    }

    return 0;
}

int attack_reach(Action action) {
    switch (action) {
    case Action::Jab:
        return 4;
    case Action::Cross:
        return 3;
    case Action::LeftBody:
    case Action::RightBody:
        return 2;
    case Action::LeftHook:
    case Action::RightHook:
        return 2;
    case Action::LeftUppercut:
    case Action::RightUppercut:
        return 1;
    default:
        return 0;
    }
}

int attack_damage(Action action) {
    switch (action) {
    case Action::Jab:
        return 7;
    case Action::Cross:
        return 10;
    case Action::LeftBody:
    case Action::RightBody:
        return 11;
    case Action::LeftHook:
    case Action::RightHook:
        return 12;
    case Action::LeftUppercut:
    case Action::RightUppercut:
        return 15;
    default:
        return 0;
    }
}

int attack_knockback(Action action) {
    switch (action) {
    case Action::Jab:
        return 1;
    case Action::Cross:
    case Action::LeftBody:
    case Action::RightBody:
        return 2;
    case Action::LeftHook:
    case Action::RightHook:
    case Action::LeftUppercut:
    case Action::RightUppercut:
        return 3;
    default:
        return 0;
    }
}

bool is_pressure_range(const BattleState& state) {
    return state.distance <= 3;
}

double defense_multiplier(const Character& target, Action attack_action, int distance) {
    switch (target.last_action) {
    case Action::Guard:
        return attack_action == Action::LeftUppercut || attack_action == Action::RightUppercut ? 0.55 : 0.35;
    case Action::DuckLeft:
    case Action::DuckRight:
        if (distance <= 2) {
            return attack_action == Action::LeftBody || attack_action == Action::RightBody ? 0.15 : 0.0;
        }
        return 0.25;
    default:
        return 1.0;
    }
}

bool can_land_punch(const BattleState& state, Action action, const Character& target) {
    return attack_reach(action) > 0 && state.distance <= attack_reach(action) && can_take_damage(target);
}

void configure_round(BattleState& state, int round_number) {
    const auto round = std::max(1, round_number);
    const auto round_index = round - 1;

    state.current_round = round;
    state.max_rounds = std::max(1, state.max_rounds);
    state.player.max_hp = 100 + round_index * 6;
    state.player.max_stamina = 100 + round_index * 3;
    state.enemy.max_hp = 95 + round_index * 14;
    state.enemy.max_stamina = 95 + round_index * 6;
    state.player.hp = state.player.max_hp;
    state.player.stamina = state.player.max_stamina;
    state.enemy.hp = state.enemy.max_hp;
    state.enemy.stamina = state.enemy.max_stamina;
    state.player.x = 6;
    state.player.y = state.board_height / 2;
    state.enemy.x = std::max(10, state.board_width - 7);
    state.enemy.y = state.board_height / 2;
    state.player.reset_motion();
    state.enemy.reset_motion();
    state.player.ground_y = state.player.y;
    state.enemy.ground_y = state.enemy.y;
    state.player.prev_x = state.player.x;
    state.player.prev_y = state.player.y;
    state.enemy.prev_x = state.enemy.x;
    state.enemy.prev_y = state.enemy.y;
    state.distance = std::abs(state.player.x - state.enemy.x) + std::abs(state.player.y - state.enemy.y);
    state.combo_count = 0;
    state.cooldown_turns = 0;
}

void reset_player_for_round(BattleState& state) {
    state.player.hp = state.player.max_hp;
    state.player.stamina = state.player.max_stamina;
    state.player.x = 6;
    state.player.y = state.board_height / 2;
    state.player.reset_motion();
    state.player.ground_y = state.player.y;
    state.player.prev_x = state.player.x;
    state.player.prev_y = state.player.y;
    state.distance = std::abs(state.player.x - state.enemy.x) + std::abs(state.player.y - state.enemy.y);
}

std::string round_banner(const BattleState& state) {
    return "Round " + std::to_string(state.current_round) + "/" + std::to_string(state.max_rounds);
}

void apply_motion(Character& character, Action action) {
    switch (action) {
    case Action::Jab:
        character.set_motion(MotionState::Attack, 1);
        break;
    case Action::Cross:
    case Action::LeftUppercut:
    case Action::RightUppercut:
        character.set_motion(MotionState::HeavyAttack, 2);
        break;
    case Action::LeftBody:
    case Action::RightBody:
    case Action::LeftHook:
    case Action::RightHook:
        character.set_motion(MotionState::Attack, 1);
        break;
    case Action::Guard:
        character.set_motion(MotionState::Defend, 1);
        break;
    case Action::DuckLeft:
    case Action::DuckRight:
        character.set_motion(MotionState::Dodge, 1);
        break;
    case Action::StepBack:
    case Action::StepForward:
        character.set_motion(MotionState::Move, 2);
        break;
    default:
        character.set_motion(MotionState::Idle, 1);
        break;
    }
}

void begin_attack(Character& character, MotionState motion, int windup_ticks, int recovery_ticks) {
    character.start_attack(motion, windup_ticks, recovery_ticks);
}

bool can_take_damage(const Character& character) {
    return character.invulnerable_ticks == 0 && character.jump_ticks == 0;
}

void finish_attack(Character& character) {
    character.attack_delay_ticks = -1;
}

void apply_damage_with_flash(Character& target, int damage) {
    if (damage <= 0 || !can_take_damage(target)) {
        return;
    }

    target.hp = std::max(0, target.hp - damage);
    target.mark_hit(3);
    target.set_motion(MotionState::Hit, 2);
}

void apply_knockback(BattleState& state, Character& target, const Character& source, int force) {
    target.prev_x = target.x;
    target.prev_y = target.y;

    const auto dx = target.x - source.x;
    const auto dy = target.y - source.y;
    if (std::abs(dx) >= std::abs(dy)) {
        target.x = clamp_position(target.x + (dx >= 0 ? force : -force), state.board_width);
    } else {
        target.y = clamp_position(target.y + (dy >= 0 ? force : -force), state.board_height);
    }

    target.set_motion(MotionState::Hit, 2);
    target.mark_hit(4);
    sync_distance(state);
}

std::pair<int, int> normalize_offset(int dx, int dy) {
    if (dx == 0 && dy == 0) {
        return {1, 0};
    }

    return {dx == 0 ? 0 : (dx > 0 ? 1 : -1), dy == 0 ? 0 : (dy > 0 ? 1 : -1)};
}

void move_orbit_left(BattleState& state, Character& character, const Character& pivot) {
    character.prev_x = character.x;
    character.prev_y = character.y;

    const auto dx = character.x - pivot.x;
    const auto dy = character.y - pivot.y;
    const auto next_dx = -dy == 0 && dx == 0 ? 1 : -dy;
    const auto next_dy = dx;

    character.x = clamp_position(pivot.x + next_dx, state.board_width);
    character.y = clamp_position(pivot.y + next_dy, state.board_height);
    character.set_motion(MotionState::Move, 2);
    sync_distance(state);
}

void move_orbit_right(BattleState& state, Character& character, const Character& pivot) {
    character.prev_x = character.x;
    character.prev_y = character.y;

    const auto dx = character.x - pivot.x;
    const auto dy = character.y - pivot.y;
    const auto next_dx = dy == 0 && dx == 0 ? 1 : dy;
    const auto next_dy = -dx;

    character.x = clamp_position(pivot.x + next_dx, state.board_width);
    character.y = clamp_position(pivot.y + next_dy, state.board_height);
    character.set_motion(MotionState::Move, 2);
    sync_distance(state);
}

void move_away_from(BattleState& state, Character& character, const Character& pivot, int step = 1) {
    character.prev_x = character.x;
    character.prev_y = character.y;

    const auto dx = character.x - pivot.x;
    const auto dy = character.y - pivot.y;
    const auto [step_x, step_y] = normalize_offset(dx, dy);

    character.x = clamp_position(character.x + step_x * step, state.board_width);
    character.y = clamp_position(character.y + step_y * step, state.board_height);
    character.set_motion(MotionState::Move, 2);
    sync_distance(state);
}

void move_toward(BattleState& state, Character& character, const Character& pivot, int step = 1) {
    character.prev_x = character.x;
    character.prev_y = character.y;

    const auto dx = character.x - pivot.x;
    const auto dy = character.y - pivot.y;
    const auto [step_x, step_y] = normalize_offset(dx, dy);

    character.x = clamp_position(character.x - step_x * step, state.board_width);
    character.y = clamp_position(character.y - step_y * step, state.board_height);
    character.set_motion(MotionState::Move, 2);
    sync_distance(state);
}

void sync_distance(BattleState& state) {
    state.player.clamp_to_bounds(state.board_width, state.board_height);
    state.enemy.clamp_to_bounds(state.board_width, state.board_height);
    state.distance = std::abs(state.player.x - state.enemy.x) + std::abs(state.player.y - state.enemy.y);
}

void step_toward_player(BattleState& state) {
    move_toward(state, state.enemy, state.player, 1);
}

void enemy_step_circle(BattleState& state) {
    if ((state.elapsed_turns / 2) % 2 == 0) {
        move_orbit_left(state, state.enemy, state.player);
        return;
    }

    move_orbit_right(state, state.enemy, state.player);
}

} // namespace

GameSession::GameSession(std::filesystem::path save_path)
    : save_path_(std::move(save_path)) {
    new_game();
}

void GameSession::new_game() {
    state_ = BattleState{};
    configure_round(state_, 1);
    log_entries_.clear();
    last_prompt_.clear();
    last_player_action_ = Action::Wait;
    last_enemy_action_ = Action::Wait;
    world_ticks_ = 0;
    pending_enemy_learning_state_.reset();
    pending_enemy_learning_action_.reset();
    pending_enemy_learning_requires_resolution_ = false;
    phase_ = GamePhase::Title;
    running_ = true;
    push_log("링에 오신 것을 환영합니다.");
}

void GameSession::start_round(int round_number) {
    pending_enemy_learning_state_.reset();
    pending_enemy_learning_action_.reset();
    pending_enemy_learning_requires_resolution_ = false;
    configure_round(state_, round_number);
    phase_ = GamePhase::Battle;
    push_log(round_banner(state_) + " 시작");
}

void GameSession::respawn_player() {
    ++state_.player_respawns;
    reset_player_for_round(state_);
    state_.player.invulnerable_ticks = 3;
    state_.player.mark_hit(2);
    state_.player.set_motion(MotionState::Idle, 1);
    push_log("플레이어가 다시 일어섰습니다.");
}

void GameSession::advance_round() {
    if (state_.current_round >= state_.max_rounds) {
        phase_ = GamePhase::Victory;
        push_log("10라운드를 모두 돌파했습니다. KO 승리입니다.");
        return;
    }

    start_round(state_.current_round + 1);
    respawn_player();
}

void GameSession::push_log(std::string message) {
    log_entries_.push_back(std::move(message));
    if (log_entries_.size() > 4) {
        log_entries_.erase(log_entries_.begin());
    }
}

std::string GameSession::trim(std::string text) {
    const auto not_space = [](unsigned char ch) {
        return !std::isspace(ch);
    };

    text.erase(text.begin(), std::find_if(text.begin(), text.end(), not_space));
    text.erase(std::find_if(text.rbegin(), text.rend(), not_space).base(), text.end());
    return text;
}

GameView GameSession::build_view() const {
    GameView view{};
    view.state = state_;
    view.phase = phase_;
    view.last_player_action = last_player_action_;
    view.last_enemy_action = last_enemy_action_;
    view.player_action_probabilities = player_profile_.action_probability();
    view.log_entries = log_entries_;
    view.prompt = last_prompt_;
    if (phase_ == GamePhase::Title) {
        view.overlay_message = "Press any key to enter the ring.";
    } else if (phase_ == GamePhase::Victory) {
        view.overlay_message = "You scored a knockout in the final round.";
    } else {
        view.overlay_message = round_banner(state_);
    }
    return view;
}

void GameSession::move_player(int dx, int dy) {
    state_.player.prev_x = state_.player.x;
    state_.player.prev_y = state_.player.y;
    state_.player.x = clamp_position(state_.player.x + dx, state_.board_width);
    state_.player.y = clamp_position(state_.player.y + dy, state_.board_height);
    state_.player.set_motion(MotionState::Move, 2);
    sync_distance(state_);
}

void GameSession::apply_player_action(Action action) {
    if (action == Action::Wait) {
        return;
    }

    if (state_.player.action_lock_ticks > 0) {
        return;
    }

    last_player_action_ = action;
    state_.player.last_action = action;
    player_profile_.record_action(action);

    switch (action) {
    case Action::Jab:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::Attack, 1, 0);
        push_log("플레이어가 잽을 보냅니다.");
        break;
    case Action::Cross:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::HeavyAttack, 2, 1);
        push_log("플레이어가 스트레이트를 준비합니다.");
        break;
    case Action::LeftBody:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::Attack, 1, 1);
        push_log("플레이어가 레프트 바디를 파고듭니다.");
        break;
    case Action::RightHook:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::Attack, 1, 1);
        push_log("플레이어가 라이트 훅을 휘두릅니다.");
        break;
    case Action::LeftHook:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::Attack, 1, 1);
        push_log("플레이어가 레프트 훅을 휘두릅니다.");
        break;
    case Action::RightBody:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::Attack, 1, 1);
        push_log("플레이어가 라이트 바디를 찌릅니다.");
        break;
    case Action::LeftUppercut:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::HeavyAttack, 2, 2);
        push_log("플레이어가 레프트 어퍼컷으로 턱을 노립니다.");
        break;
    case Action::RightUppercut:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::HeavyAttack, 2, 2);
        push_log("플레이어가 라이트 어퍼컷으로 턱을 노립니다.");
        break;
    case Action::StepBack:
        apply_motion(state_.player, action);
        move_away_from(state_, state_.player, state_.enemy, 2);
        push_log("플레이어가 스텝 아웃합니다.");
        break;
    case Action::StepForward:
        apply_motion(state_.player, action);
        move_toward(state_, state_.player, state_.enemy, 2);
        push_log("플레이어가 스텝 인합니다.");
        break;
    case Action::Guard:
    case Action::DuckLeft:
    case Action::DuckRight:
        apply_motion(state_.player, action);
        state_.player.action_lock_ticks = 1;
        state_.player.stamina = std::max(0, state_.player.stamina - stamina_cost(action));
        push_log(std::string("플레이어가 ") + boxing_action_label(action) + " 상태입니다.");
        break;
    case Action::Wait:
    case Action::Count:
        break;
    }

    sync_distance(state_);
}

void GameSession::apply_enemy_action(Action action) {
    if (action == Action::Wait || state_.enemy.action_lock_ticks > 0 || state_.enemy.hp <= 0 || state_.player.hp <= 0) {
        return;
    }

    last_enemy_action_ = action;
    state_.enemy.last_action = action;
    pending_enemy_learning_state_ = state_;
    pending_enemy_learning_action_ = action;
    pending_enemy_learning_requires_resolution_ = attack_reach(action) > 0;

    switch (action) {
    case Action::Jab:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::Attack, 1, 0);
        break;
    case Action::Cross:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::HeavyAttack, 2, 1);
        break;
    case Action::LeftBody:
    case Action::RightBody:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::Attack, 1, 1);
        break;
    case Action::LeftHook:
    case Action::RightHook:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::Attack, 1, 1);
        break;
    case Action::LeftUppercut:
    case Action::RightUppercut:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::HeavyAttack, 2, 2);
        break;
    case Action::StepBack:
        apply_motion(state_.enemy, action);
        move_away_from(state_, state_.enemy, state_.player, 2);
        break;
    case Action::StepForward:
        apply_motion(state_.enemy, action);
        move_toward(state_, state_.enemy, state_.player, 2);
        break;
    case Action::Guard:
    case Action::DuckLeft:
    case Action::DuckRight:
        apply_motion(state_.enemy, action);
        state_.enemy.action_lock_ticks = 1;
        state_.enemy.stamina = std::max(0, state_.enemy.stamina - stamina_cost(action));
        break;
    case Action::Wait:
    case Action::Count:
        break;
    }

    sync_distance(state_);
}

double GameSession::compute_enemy_reward(const BattleState& before, const BattleState& after, Action action) const {
    const auto player_damage = std::max(0, before.player.hp - after.player.hp);
    const auto enemy_damage = std::max(0, before.enemy.hp - after.enemy.hp);
    const auto pressure_bonus = before.distance <= 2 ? 1.0 : (before.distance <= 4 ? 0.4 : -0.2);
    const auto stamina_penalty = static_cast<double>(stamina_cost(action)) * 0.05;
    auto reward = static_cast<double>(player_damage) * 2.5 - static_cast<double>(enemy_damage) * 2.2 + pressure_bonus - stamina_penalty;

    if (after.player.hp <= 0) {
        reward += 18.0;
    }
    if (after.enemy.hp <= 0) {
        reward -= 18.0;
    }

    return reward;
}

void GameSession::commit_enemy_learning_if_ready() {
    if (!pending_enemy_learning_state_.has_value() || !pending_enemy_learning_action_.has_value()) {
        return;
    }

    if (pending_enemy_learning_requires_resolution_ && state_.enemy.attack_delay_ticks > 0) {
        return;
    }

    const auto reward = compute_enemy_reward(*pending_enemy_learning_state_, state_, *pending_enemy_learning_action_);
    ai_agent_.record_transition(*pending_enemy_learning_state_, *pending_enemy_learning_action_, state_, reward);
    pending_enemy_learning_state_.reset();
    pending_enemy_learning_action_.reset();
    pending_enemy_learning_requires_resolution_ = false;
}

void GameSession::print_stats() {
    const auto& history = ai_agent_.pattern_model().history();
    if (history.empty()) {
        push_log("AI 학습 데이터가 아직 없습니다.");
        return;
    }

    const auto predicted = ai_agent_.pattern_model().predict_next();
    const auto analytics = ai_agent_.analytics();
    if (predicted.has_value()) {
        push_log(std::string("AI가 예측하는 다음 행동: ") + std::string(to_string(*predicted)));
    } else {
        push_log("AI가 예측하는 다음 행동: Unknown");
    }

    std::ostringstream accuracy;
    accuracy << std::fixed << std::setprecision(0)
             << (ai_agent_.prediction_accuracy() * 100.0) << '%';
    push_log(std::string("AI 예측 정확도: ") + accuracy.str());
    push_log("AI 결정 수: " + std::to_string(analytics.decisions_made));
    push_log("AI 학습 업데이트: " + std::to_string(ai_agent_.learning_updates()));
    push_log("AI 정책 상태 수: " + std::to_string(ai_agent_.q_table().size()));
}

void GameSession::tick_world() {
    if (phase_ != GamePhase::Battle) {
        return;
    }

    ++world_ticks_;
    ++state_.elapsed_turns;

    state_.player.tick_motion();
    state_.enemy.tick_motion();
    state_.player.tick_status();
    state_.enemy.tick_status();

    if (state_.enemy.hp <= 0) {
        commit_enemy_learning_if_ready();
        push_log("다운! 라운드를 가져옵니다.");
        advance_round();
        return;
    }

    if (state_.player.hp <= 0) {
        commit_enemy_learning_if_ready();
        respawn_player();
        return;
    }

    if (state_.cooldown_turns > 0) {
        --state_.cooldown_turns;
        commit_enemy_learning_if_ready();
        return;
    }

    if (state_.player.attack_delay_ticks == 0) {
        const auto action = state_.player.last_action;
        const auto base_damage = attack_damage(action);
        if (can_land_punch(state_, action, state_.enemy)) {
            const auto multiplier = defense_multiplier(state_.enemy, action, state_.distance);
            const auto damage = static_cast<int>(std::round(static_cast<double>(base_damage) * multiplier));
            if (damage > 0) {
                apply_damage_with_flash(state_.enemy, damage);
                state_.cooldown_turns = 2;
            }
            if (multiplier > 0.0 && action != Action::Jab) {
                apply_knockback(state_, state_.enemy, state_.player, attack_knockback(action));
            }
            if (multiplier == 0.0) {
                push_log("상대가 슬립으로 잽을 흘렸습니다.");
            } else if (multiplier < 1.0) {
                push_log("상대가 가드로 충격을 줄였습니다.");
            } else {
                push_log("플레이어 잽이 적중했습니다.");
            }
        }
        finish_attack(state_.player);
    }

    if (state_.enemy.attack_delay_ticks == 0) {
        const auto action = state_.enemy.last_action;
        const auto base_damage = attack_damage(action);
        if (can_land_punch(state_, action, state_.player)) {
            const auto multiplier = defense_multiplier(state_.player, action, state_.distance);
            const auto damage = static_cast<int>(std::round(static_cast<double>(base_damage) * multiplier));
            if (damage > 0) {
                apply_damage_with_flash(state_.player, damage);
                state_.cooldown_turns = 2;
            }
            if (multiplier > 0.0 && action != Action::Jab) {
                apply_knockback(state_, state_.player, state_.enemy, attack_knockback(action));
            }
            if (multiplier == 0.0) {
                push_log("플레이어가 슬립으로 펀치를 흘렸습니다.");
            } else if (multiplier < 1.0) {
                push_log("플레이어가 가드로 충격을 줄였습니다.");
            } else {
                push_log("상대의 펀치가 적중했습니다.");
            }
        }
        finish_attack(state_.enemy);
    }

    if (world_ticks_ % 4 == 0 && state_.enemy.action_lock_ticks == 0) {
        auto enemy_action = ai_agent_.choose_action(state_);

        if (state_.distance > 4 && enemy_action == Action::Wait) {
            enemy_action = Action::StepForward;
        } else if (is_pressure_range(state_) && enemy_action == Action::Wait) {
            enemy_action = Action::Jab;
        }

        if (enemy_action == Action::Wait) {
            enemy_step_circle(state_);
            state_.enemy.last_action = Action::Wait;
        } else {
            apply_enemy_action(enemy_action);
        }

        if (world_ticks_ % 8 == 0) {
            push_log(std::string("적 행동: ") + std::string(to_string(last_enemy_action_)));
        }
    } else if (world_ticks_ % 6 == 0 && state_.distance > 4) {
        step_toward_player(state_);
    }

    if (state_.distance <= 3 && state_.enemy.action_lock_ticks == 0 && world_ticks_ % 6 == 0) {
        apply_enemy_action(state_.distance <= 2 ? Action::Cross : Action::Jab);
    }

    if (state_.enemy.hp <= 0) {
        commit_enemy_learning_if_ready();
        push_log("다운! 라운드를 가져옵니다.");
        advance_round();
        return;
    }

    if (state_.player.hp <= 0) {
        commit_enemy_learning_if_ready();
        respawn_player();
    }

    commit_enemy_learning_if_ready();
}

void GameSession::save() {
    SaveData data{};
    data.state = state_;
    data.player_profile = player_profile_;
    data.ai_agent = ai_agent_;

    if (save_game_.save(save_path_, data)) {
        push_log("경기를 저장했습니다: " + save_path_.string());
    } else {
        push_log("저장에 실패했습니다.");
    }
}

void GameSession::load() {
    SaveData data{};
    if (save_game_.load(save_path_, data)) {
        state_ = data.state;
        player_profile_ = data.player_profile;
        ai_agent_ = data.ai_agent;
        pending_enemy_learning_state_.reset();
        pending_enemy_learning_action_.reset();
        pending_enemy_learning_requires_resolution_ = false;
        push_log("경기를 불러왔습니다: " + save_path_.string());
    } else {
        push_log("불러오기에 실패했습니다.");
    }
}


void GameSession::handle_realtime_command(const std::string& key) {
    if (key == "up" || key == "i") {
        move_away_from(state_, state_.player, state_.enemy, 1);
        last_player_action_ = Action::Wait;
        return;
    }

    if (key == "down" || key == "k") {
        move_toward(state_, state_.player, state_.enemy, 1);
        last_player_action_ = Action::Wait;
        return;
    }

    if (key == "left" || key == "j") {
        move_orbit_left(state_, state_.player, state_.enemy);
        last_player_action_ = Action::Wait;
        return;
    }

    if (key == "right" || key == "l") {
        move_orbit_right(state_, state_.player, state_.enemy);
        last_player_action_ = Action::Wait;
        return;
    }

    if (key == "escape" || key == "quit" || key == "exit") {
        running_ = false;
        return;
    }

    if (key == "v") {
        save();
        return;
    }

    if (key == "b") {
        load();
        return;
    }

    if (key == "n") {
        new_game();
        return;
    }

    if (key == "t") {
        print_stats();
        return;
    }

    apply_player_action(parse_action(key));
}

void GameSession::run() {
    renderer_.render(build_view());
    while (running_) {
        std::string key;
        if (pending_input_.has_value()) {
            key = std::move(*pending_input_);
            pending_input_.reset();
        } else {
            key = input_reader_.read_key_for(std::chrono::milliseconds(16));
        }

        if (is_combo_prefix(key)) {
            const auto suffix = input_reader_.read_key_for(std::chrono::milliseconds(24));
            if (is_combo_suffix(suffix)) {
                key = key + "+" + suffix;
            } else if (!suffix.empty()) {
                pending_input_ = suffix;
            }
        }

        if (phase_ == GamePhase::Title) {
            if (!key.empty()) {
                last_prompt_ = key;
                phase_ = GamePhase::Battle;
                push_log(round_banner(state_) + " 시작");
            }
            renderer_.render(build_view());
            continue;
        }

        if (phase_ == GamePhase::Victory) {
            if (!key.empty()) {
                last_prompt_ = key;
                if (key == "escape" || key == "quit" || key == "exit") {
                    running_ = false;
                } else if (key == "n" || key == "new") {
                    new_game();
                    phase_ = GamePhase::Battle;
                    push_log("새 경기를 시작합니다.");
                }
            }

            renderer_.render(build_view());
            continue;
        }

        if (key.empty()) {
            tick_world();
            renderer_.render(build_view());
            continue;
        }

        last_prompt_ = key;
        handle_realtime_command(key);

        tick_world();
        if (!running_) {
            renderer_.render(build_view());
            break;
        }
        renderer_.render(build_view());
    }

    std::cout << "\n세션 종료\n";
}

} // namespace game
