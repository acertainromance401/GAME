#pragma once

#include <chrono>
#include <string>

#ifndef _WIN32
#include <termios.h>
#endif

namespace game {

class InputReader {
public:
    InputReader();
    ~InputReader();

    InputReader(const InputReader&) = delete;
    InputReader& operator=(const InputReader&) = delete;

    [[nodiscard]] std::string read_key() const;
    [[nodiscard]] std::string read_key_for(std::chrono::milliseconds timeout) const;

private:
    bool raw_mode_enabled_{false};
#ifndef _WIN32
    termios original_state_{};
#endif
};

} // namespace game
