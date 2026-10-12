#pragma once

#include "game/game_view.hpp"

#include <vector>

namespace game {

class GameRenderer {
public:
    GameRenderer();
    ~GameRenderer();

    void render(const GameView& view) const;

private:
    [[nodiscard]] std::vector<std::string> build_frame(const GameView& view) const;
    void present_frame(const std::vector<std::string>& frame) const;
    void sync_animated_hp(const GameView& view) const;

    mutable bool initialized_{false};
    mutable std::vector<std::string> previous_frame_;
    mutable int animated_player_hp_{100};
    mutable int animated_enemy_hp_{100};
};

} // namespace game
