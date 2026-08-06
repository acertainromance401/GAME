#include "game/input_reader.hpp"

#include <chrono>
#include <iostream>
#include <optional>

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#else
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>
#endif

namespace game {

InputReader::InputReader() {
#ifndef _WIN32
    if (tcgetattr(STDIN_FILENO, &original_state_) == 0) {
        auto terminal_state = original_state_;
        raw_mode_enabled_ = true;
        terminal_state.c_lflag &= static_cast<unsigned long>(~(ICANON | ECHO));
        terminal_state.c_cc[VMIN] = 1;
        terminal_state.c_cc[VTIME] = 0;
        tcsetattr(STDIN_FILENO, TCSANOW, &terminal_state);
    }
#else
    raw_mode_enabled_ = true;
#endif
}

InputReader::~InputReader() {
#ifndef _WIN32
    if (raw_mode_enabled_) {
        tcsetattr(STDIN_FILENO, TCSANOW, &original_state_);
    }
#endif
}

std::string InputReader::read_key() const {
    return read_key_for(std::chrono::milliseconds::max());
}

std::string InputReader::read_key_for(std::chrono::milliseconds timeout) const {
#ifdef _WIN32
    const auto start = std::chrono::steady_clock::now();
    while (!_kbhit()) {
        if (timeout != std::chrono::milliseconds::max() && std::chrono::steady_clock::now() - start >= timeout) {
            return {};
        }

        Sleep(10);
    }

    const auto key = _getch();
    if (key == 0 || key == 224) {
        const auto extended = _getch();
        switch (extended) {
        case 75:
            return "left";
        case 77:
            return "right";
        case 72:
            return "up";
        case 80:
            return "down";
        default:
            return "";
        }
    }

    if (key == ' ') {
        return "space";
    }

    return std::string(1, static_cast<char>(key));
#else
    const auto wait_for_input = [timeout]() {
        fd_set read_set;
        FD_ZERO(&read_set);
        FD_SET(STDIN_FILENO, &read_set);

        timeval tv{};
        timeval* tv_ptr = nullptr;
        if (timeout != std::chrono::milliseconds::max()) {
            tv.tv_sec = static_cast<long>(timeout.count() / 1000);
            tv.tv_usec = static_cast<long>((timeout.count() % 1000) * 1000);
            tv_ptr = &tv;
        }

        return select(STDIN_FILENO + 1, &read_set, nullptr, nullptr, tv_ptr) > 0;
    };

    if (!wait_for_input()) {
        return {};
    }

    const auto read_char = []() -> std::optional<char> {
        if (std::cin.peek() == EOF) {
            return std::nullopt;
        }

        return static_cast<char>(std::cin.get());
    };

    const auto key = read_char();
    if (!key.has_value()) {
        return {};
    }

    if (key.value() == '\x1b') {
        if (!wait_for_input()) {
            return "escape";
        }

        const auto next = read_char();
        if (!next.has_value() || next.value() != '[') {
            return "escape";
        }

        if (!wait_for_input()) {
            return {};
        }

        const auto third = read_char();
        if (!third.has_value()) {
            return {};
        }

        switch (third.value()) {
        case 'A':
            return "up";
        case 'B':
            return "down";
        case 'C':
            return "right";
        case 'D':
            return "left";
        default:
            return {};
        }
    }

    if (key.value() == ' ') {
        return "space";
    }
    if (key.value() == '\n' || key.value() == '\r') {
        return "";
    }
    return std::string(1, key.value());
#endif
}

} // namespace game
