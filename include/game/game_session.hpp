#pragma once

#include "game/ai_agent.hpp"
#include "game/game_renderer.hpp"
#include "game/game_view.hpp"
#include "game/input_reader.hpp"
#include "game/player_profile.hpp"
#include "game/save_game.hpp"

#include <filesystem>
#include <cstddef>
#include <optional>
#include <string>
#include <vector>

namespace game {

class GameSession {
public:
    explicit GameSession(std::filesystem::path save_path = "game_save.txt");

    void run();

private:
    [[nodiscard]] GameView build_view() const;
    void move_player(int dx, int dy);
    void push_log(std::string message);
    void new_game();
    void start_round(int round_number);
    void respawn_player();
    void advance_round();
    void save();
    void load();
    void print_stats();
    void tick_world();
    void handle_realtime_command(const std::string& key);
    void apply_player_action(Action action);
    void apply_enemy_action(Action action);
    void commit_enemy_learning_if_ready();
    [[nodiscard]] double compute_enemy_reward(const BattleState& before, const BattleState& after, Action action) const;
    static std::string trim(std::string text);

    std::filesystem::path save_path_;
    BattleState state_{};
    PlayerProfile player_profile_{};
    AIAgent ai_agent_{};
    SaveGame save_game_{};
    std::vector<std::string> log_entries_{};
    std::string last_prompt_{};
    Action last_player_action_{Action::Wait};
    Action last_enemy_action_{Action::Wait};
    std::size_t world_ticks_{0};
    GamePhase phase_{GamePhase::Title};
    std::optional<BattleState> pending_enemy_learning_state_{};
    std::optional<Action> pending_enemy_learning_action_{};
    bool pending_enemy_learning_requires_resolution_{false};
    GameRenderer renderer_{};
    InputReader input_reader_{};
    bool running_{true};
};

} // namespace game
