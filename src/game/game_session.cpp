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

std::string boxing_action_label(Action action) {
    switch (action) {
    case Action::Attack:
        return "잽";
    case Action::HeavyAttack:
        return "스트레이트";
    case Action::Defend:
        return "가드";
    case Action::Dodge:
        return "슬립";
    case Action::Parry:
        return "블록";
    case Action::Retreat:
        return "스텝 아웃";
    case Action::Approach:
        return "스텝 인";
    case Action::Heal:
        return "호흡 고르기";
    case Action::Dash:
        return "돌진";
    case Action::Jump:
        return "더킹";
    case Action::Wait:
    case Action::Count:
        return "대기";
    }

    return "대기";
}

Action parse_action(const std::string& command) {
    if (command == "a" || command == "jab" || command == "attack") {
        return Action::Attack;
    }
    if (command == "s" || command == "cross" || command == "heavy" || command == "heavyattack") {
        return Action::HeavyAttack;
    }
    if (command == "d" || command == "defend" || command == "guard") {
        return Action::Defend;
    }
    if (command == "space" || command == "slip" || command == "dod" || command == "dodge") {
        return Action::Dodge;
    }
    if (command == "f" || command == "block" || command == "parry") {
        return Action::Parry;
    }
    if (command == "u" || command == "back" || command == "retreat") {
        return Action::Retreat;
    }
    if (command == "o" || command == "in" || command == "approach") {
        return Action::Approach;
    }
    if (command == "h" || command == "recover" || command == "heal") {
        return Action::Heal;
    }
    if (command == "z" || command == "rush" || command == "dash") {
        return Action::Dash;
    }
    if (command == "x" || command == "duck" || command == "jump") {
        return Action::Jump;
    }

    return Action::Wait;
}

int clamp_position(int value, int width) {
    return std::clamp(value, 0, std::max(0, width - 1));
}

void sync_distance(BattleState& state);
bool can_take_damage(const Character& character);

int stamina_cost(Action action) {
    switch (action) {
    case Action::Attack:
        return 10;
    case Action::HeavyAttack:
        return 18;
    case Action::Defend:
        return 6;
    case Action::Dodge:
        return 12;
    case Action::Parry:
        return 8;
    case Action::Retreat:
    case Action::Approach:
        return 5;
    case Action::Heal:
        return 0;
    case Action::Dash:
        return 10;
    case Action::Jump:
        return 6;
    case Action::Wait:
    case Action::Count:
        return 0;
    }

    return 0;
}

int attack_reach(Action action) {
    switch (action) {
    case Action::Attack:
        return 3;
    case Action::HeavyAttack:
        return 2;
    default:
        return 0;
    }
}

int attack_damage(Action action) {
    switch (action) {
    case Action::Attack:
        return 9;
    case Action::HeavyAttack:
        return 16;
    default:
        return 0;
    }
}

int attack_knockback(Action action) {
    switch (action) {
    case Action::Attack:
        return 1;
    case Action::HeavyAttack:
        return 2;
    default:
        return 0;
    }
}

bool is_pressure_range(const BattleState& state) {
    return state.distance <= 3;
}

double defense_multiplier(const Character& target, Action attack_action, int distance) {
    switch (target.last_action) {
    case Action::Parry:
        return attack_action == Action::Attack ? 0.15 : 0.4;
    case Action::Defend:
        return 0.45;
    case Action::Dodge:
        if (distance <= 2) {
            return attack_action == Action::HeavyAttack ? 0.35 : 0.0;
        }
        return 0.2;
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
    case Action::Attack:
        character.set_motion(MotionState::Attack, 2);
        break;
    case Action::HeavyAttack:
        character.set_motion(MotionState::HeavyAttack, 3);
        break;
    case Action::Dash:
        character.set_motion(MotionState::Dash, 2);
        break;
    case Action::Jump:
        character.set_motion(MotionState::Jump, 3);
        break;
    case Action::Defend:
        character.set_motion(MotionState::Defend, 2);
        break;
    case Action::Dodge:
        character.set_motion(MotionState::Dodge, 2);
        break;
    case Action::Parry:
        character.set_motion(MotionState::Parry, 1);
        break;
    case Action::Heal:
        character.set_motion(MotionState::Heal, 2);
        break;
    default:
        character.set_motion(MotionState::Idle, 1);
        break;
    }
}

void begin_attack(Character& character, MotionState motion, int windup_ticks, int recovery_ticks) {
    character.start_attack(motion, windup_ticks, recovery_ticks);
}

void begin_dash(Character& character, BattleState& state, int dx, int dy) {
    character.prev_x = character.x;
    character.prev_y = character.y;
    character.start_dash(1);
    character.x = clamp_position(character.x + dx * 4, state.board_width);
    character.y = clamp_position(character.y + dy * 2, state.board_height);
    sync_distance(state);
}

void begin_jump(Character& character) {
    character.prev_x = character.x;
    character.prev_y = character.y;
    character.start_jump(2);
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

void move_character(BattleState& state, Character& character, int dx, int dy) {
    character.prev_x = character.x;
    character.prev_y = character.y;
    character.x = clamp_position(character.x + dx, state.board_width);
    character.y = clamp_position(character.y + dy, state.board_height);
    character.set_motion(MotionState::Move, 1);
    sync_distance(state);
}

std::pair<int, int> direction_delta(const std::string& key) {
    if (key == "up") {
        return {0, -1};
    }
    if (key == "down") {
        return {0, 1};
    }
    if (key == "left") {
        return {-1, 0};
    }
    if (key == "right") {
        return {1, 0};
    }
    if (key == "i") {
        return {0, -1};
    }
    if (key == "k") {
        return {0, 1};
    }
    if (key == "j") {
        return {-1, 0};
    }
    if (key == "l") {
        return {1, 0};
    }
    if (key == "u") {
        return {-1, 0};
    }
    if (key == "o") {
        return {1, 0};
    }

    return {0, 0};
}

void sync_distance(BattleState& state) {
    state.player.clamp_to_bounds(state.board_width, state.board_height);
    state.enemy.clamp_to_bounds(state.board_width, state.board_height);
    state.distance = std::abs(state.player.x - state.enemy.x) + std::abs(state.player.y - state.enemy.y);
}

void step_toward_player(BattleState& state) {
    const auto dx = state.player.x - state.enemy.x;
    const auto dy = state.player.y - state.enemy.y;

    if (std::abs(dx) >= std::abs(dy)) {
        state.enemy.x += dx == 0 ? 0 : (dx > 0 ? 1 : -1);
    } else {
        state.enemy.y += dy == 0 ? 0 : (dy > 0 ? 1 : -1);
    }

    state.enemy.clamp_to_bounds(state.board_width, state.board_height);
    state.enemy.set_motion(MotionState::Move, 1);
    sync_distance(state);
}

std::pair<int, int> enemy_step_circle(const BattleState& state) {
    if ((state.enemy.x + state.enemy.y + state.elapsed_turns) % 2 == 0) {
        return {0, state.enemy.y < state.board_height - 1 ? 1 : -1};
    }

    return {state.enemy.x < state.player.x ? 1 : -1, 0};
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
    if (log_entries_.size() > 6) {
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
    state_.player.set_motion(MotionState::Move, 1);
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
    case Action::Attack:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::Attack, 1, 1);
        push_log("플레이어가 잽을 보냅니다.");
        break;
    case Action::HeavyAttack:
        apply_motion(state_.player, action);
        begin_attack(state_.player, MotionState::HeavyAttack, 2, 3);
        push_log("플레이어가 스트레이트를 준비합니다.");
        break;
    case Action::Dash:
        apply_motion(state_.player, action);
        begin_dash(state_.player, state_, state_.player.x < state_.enemy.x ? 1 : -1, 0);
        push_log("플레이어가 스텝 인합니다.");
        break;
    case Action::Jump:
        apply_motion(state_.player, action);
        begin_jump(state_.player);
        push_log("플레이어가 더킹합니다.");
        break;
    case Action::Defend:
    case Action::Dodge:
    case Action::Parry:
    case Action::Heal:
    case Action::Retreat:
    case Action::Approach:
        apply_motion(state_.player, action);
        state_.player.action_lock_ticks = action == Action::Parry ? 1 : 2;
        state_.player.stamina = std::max(0, state_.player.stamina - stamina_cost(action));
        if (action == Action::Heal) {
            state_.player.hp = std::min(state_.max_hp, state_.player.hp + 12);
            state_.player.mark_hit(1);
        }
        if (action == Action::Retreat) {
            move_character(state_, state_.player, state_.player.x < state_.enemy.x ? -1 : 1, 0);
        } else if (action == Action::Approach) {
            move_character(state_, state_.player, state_.player.x < state_.enemy.x ? 1 : -1, 0);
        }
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
    pending_enemy_learning_requires_resolution_ = action == Action::Attack || action == Action::HeavyAttack;

    switch (action) {
    case Action::Attack:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::Attack, 1, 1);
        break;
    case Action::HeavyAttack:
        apply_motion(state_.enemy, action);
        begin_attack(state_.enemy, MotionState::HeavyAttack, 2, 3);
        break;
    case Action::Dash:
        apply_motion(state_.enemy, action);
        begin_dash(state_.enemy, state_, state_.enemy.x < state_.player.x ? 1 : -1, 0);
        break;
    case Action::Jump:
        apply_motion(state_.enemy, action);
        begin_jump(state_.enemy);
        break;
    case Action::Defend:
    case Action::Dodge:
    case Action::Parry:
    case Action::Heal:
    case Action::Retreat:
    case Action::Approach:
        apply_motion(state_.enemy, action);
        state_.enemy.action_lock_ticks = action == Action::Parry ? 1 : 2;
        state_.enemy.stamina = std::max(0, state_.enemy.stamina - stamina_cost(action));
        if (action == Action::Retreat) {
            move_character(state_, state_.enemy, state_.enemy.x < state_.player.x ? -1 : 1, 0);
        } else if (action == Action::Approach) {
            move_character(state_, state_.enemy, state_.enemy.x < state_.player.x ? 1 : -1, 0);
        }
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

    if (state_.player.attack_delay_ticks == 0) {
        const auto action = state_.player.last_action;
        const auto base_damage = attack_damage(action);
        if (can_land_punch(state_, action, state_.enemy)) {
            const auto multiplier = defense_multiplier(state_.enemy, action, state_.distance);
            const auto damage = static_cast<int>(std::round(static_cast<double>(base_damage) * multiplier));
            if (damage > 0) {
                apply_damage_with_flash(state_.enemy, damage);
            }
            if (multiplier > 0.0 && action == Action::HeavyAttack) {
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
            }
            if (multiplier > 0.0 && action == Action::HeavyAttack) {
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
            enemy_action = Action::Approach;
        } else if (is_pressure_range(state_) && enemy_action == Action::Wait) {
            enemy_action = Action::Attack;
        }

        if (enemy_action == Action::Wait) {
            const auto [dx, dy] = enemy_step_circle(state_);
            move_character(state_, state_.enemy, dx, dy);
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
        apply_enemy_action(state_.distance <= 2 ? Action::HeavyAttack : Action::Attack);
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
    const auto [dx, dy] = direction_delta(key);
    if (dx != 0 || dy != 0) {
        move_player(dx, dy);
        last_player_action_ = Action::Wait;
        return;
    }

    if (key == "q" || key == "quit" || key == "exit") {
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
        const auto key = input_reader_.read_key_for(std::chrono::milliseconds(16));
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
                if (key == "q" || key == "quit" || key == "exit") {
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
