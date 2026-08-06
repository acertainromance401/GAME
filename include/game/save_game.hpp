#pragma once

#include "game/ai_agent.hpp"
#include "game/battle_state.hpp"
#include "game/player_profile.hpp"

#include <filesystem>
#include <string>

namespace game {

struct SaveData {
    BattleState state{};
    PlayerProfile player_profile{};
    AIAgent ai_agent{};
};

class SaveGame {
public:
    bool save(const std::filesystem::path& path, const SaveData& data) const;
    bool load(const std::filesystem::path& path, SaveData& data) const;

private:
    static std::string serialize(const SaveData& data);
    static bool deserialize(const std::string& text, SaveData& data);
};

} // namespace game
