cmake_minimum_required(VERSION 3.20)

project(GAME
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(CTest)
option(GAME_BUILD_TESTS "Build test targets" ON)
option(GAME_USE_FTXUI "Enable FTXUI UI if available" OFF)

include(FetchContent)

add_library(game_core
    src/game/action.cpp
    src/game/ai_agent.cpp
    src/game/character.cpp
    src/game/combat_engine.cpp
    src/game/battle_state.cpp
    src/game/game_session.cpp
    src/game/game_renderer.cpp
    src/game/input_reader.cpp
    src/game/save_game.cpp
    src/game/pattern_model.cpp
    src/game/player_profile.cpp
)

target_include_directories(game_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(game_core PUBLIC cxx_std_20)

if(GAME_USE_FTXUI)
    FetchContent_Declare(
        ftxui
        GIT_REPOSITORY https://github.com/ArthurSonzogni/FTXUI.git
        GIT_TAG v5.0.0
    )
    set(FTXUI_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(FTXUI_BUILD_DOCS OFF CACHE BOOL "" FORCE)
    set(FTXUI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(ftxui)

    target_compile_definitions(game_core PUBLIC GAME_HAS_FTXUI=1)
    target_link_libraries(game_core PUBLIC ftxui::screen ftxui::dom ftxui::component)
endif()

add_executable(game_tui
    src/main.cpp
)

target_link_libraries(game_tui PRIVATE game_core)
target_compile_features(game_tui PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(game_core PRIVATE /W4)
    target_compile_options(game_tui PRIVATE /W4)
else()
    target_compile_options(game_core PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(game_tui PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS game_tui)

if(GAME_BUILD_TESTS)
    add_executable(game_tests
        tests/smoke_tests.cpp
    )

    target_link_libraries(game_tests PRIVATE game_core)
    target_compile_features(game_tests PRIVATE cxx_std_20)

    add_test(NAME game_smoke_tests COMMAND game_tests)
endif()
