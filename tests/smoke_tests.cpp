#include "game/action.hpp"
#include "game/ai_agent.hpp"
#include "game/battle_state.hpp"
#include "game/combat_engine.hpp"
#include "game/save_game.hpp"

#include <filesystem>
#include <iostream>

using namespace game;

int main() {
    {
        BattleState state{};
        AIAgent ai{};
        CombatEngine engine{};
        state.player.x = 5;
        state.player.y = 4;
        state.enemy.x = 6;
        state.enemy.y = 4;
        state.distance = 1;

        const auto result = engine.resolve_turn(state, ai, Action::Jab);
        if (result.enemy_damage <= 0) {
            std::cerr << "combat resolution failed\n";
            return 1;
        }
    }

    {
        SaveGame save_game{};
        SaveData data{};
        data.state.player.hp = 88;
        data.state.enemy.hp = 77;
        data.state.player.x = 3;
        data.state.player.y = 2;
        data.state.enemy.x = 14;
        data.state.enemy.y = 2;
        data.player_profile.record_action(Action::Jab);
        data.player_profile.record_action(Action::Guard);
        data.ai_agent.observe_player_action(Action::Jab);

        const auto path = std::filesystem::temp_directory_path() / "game_smoke_test_save.txt";
        if (!save_game.save(path, data)) {
            std::cerr << "save failed\n";
            return 1;
        }

        SaveData loaded{};
        if (!save_game.load(path, loaded)) {
            std::cerr << "load failed\n";
            return 1;
        }

        if (loaded.state.player.hp != 88 || loaded.state.enemy.hp != 77) {
            std::cerr << "state mismatch after load\n";
            return 1;
        }

        if (loaded.state.player.x != 3 || loaded.state.player.y != 2 || loaded.state.enemy.x != 14 || loaded.state.enemy.y != 2) {
            std::cerr << "arena mismatch after load\n";
            return 1;
        }

        if (loaded.player_profile.total_actions() != 2) {
            std::cerr << "profile mismatch after load\n";
            return 1;
        }
    }

    std::cout << "smoke tests passed\n";
    return 0;
}
